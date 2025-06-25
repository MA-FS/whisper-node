import Foundation
import os.log
import ApplicationServices
import AppKit

extension Notification.Name {
    static let whisperModelLoadFailed = Notification.Name("whisperModelLoadFailed")
}

/// Central coordination class for Whisper Node core functionality
///
/// Manages the complete speech-to-text pipeline including audio capture, model inference,
/// and text insertion with comprehensive performance monitoring and memory management.
///
/// ## Architecture
/// WhisperNodeCore serves as the main coordinator between:
/// - Global hotkey management for press-and-hold voice input
/// - Audio capture engine for 16kHz mono recording
/// - Whisper model integration for speech recognition
/// - Performance monitoring and automatic optimization
///
/// ## Key Features
/// - **Press-and-Hold Input**: Keyboard-style voice activation
/// - **Real-time Processing**: Low-latency speech-to-text conversion
/// - **Performance Monitoring**: CPU and memory usage tracking
/// - **Automatic Optimization**: Model downgrade recommendations
/// - **Memory Management**: Automatic cleanup and resource management
///
/// ## Usage
/// ```swift
/// let core = WhisperNodeCore.shared
/// core.startVoiceActivation()
/// core.loadModel("small.en")
/// 
/// // Performance monitoring
/// let (memory, cpu, downgradeNeeded) = await core.getPerformanceMetrics()
/// ```
///
/// - Important: All UI updates are automatically dispatched to the main actor
/// - Note: This is a singleton class - use `WhisperNodeCore.shared`
@MainActor
public class WhisperNodeCore: ObservableObject {
    private static let logger = Logger(subsystem: "com.whispernode.core", category: "initialization")
    
    // Display duration constants
    private static let errorDisplayDuration: UInt64 = 2_000_000_000 // 2 seconds
    private static let hotkeyErrorDisplayDuration: UInt64 = 3_000_000_000 // 3 seconds
    private static let processingStateDelay: UInt64 = 200_000_000 // 0.2 seconds
    
    // Core managers
    @Published public private(set) var hotkeyManager = GlobalHotkeyManager()
    @Published public private(set) var audioEngine = AudioCaptureEngine.shared
    @Published public private(set) var menuBarManager = MenuBarManager()
    @Published public private(set) var indicatorManager = RecordingIndicatorWindowManager()
    @Published public private(set) var performanceMonitor = PerformanceMonitor.shared
    private let textInsertionEngine = TextInsertionEngine()
    private let errorManager = ErrorHandlingManager.shared
    
    // Whisper integration
    private var whisperEngine: WhisperEngine?
    private var currentModelPath: String?
    
    // Application state
    @Published public private(set) var isInitialized = false
    @Published public private(set) var isRecording = false
    @Published public private(set) var currentModel: String = "tiny.en"

    // Permission monitoring
    private var permissionMonitorTimer: Timer?
    private var lastAccessibilityPermissionStatus = false
    private var appActivationObserver: NSObjectProtocol?
    
    // Performance monitoring properties for backward compatibility
    public var memoryUsage: UInt64 {
        performanceMonitor.memoryUsage
    }
    
    public var averageCpuUsage: Float {
        Float(performanceMonitor.getAverageCPUUsage())
    }
    
    public static let shared = WhisperNodeCore()
    
    private init() {
        initialize()
    }

    deinit {
        // Clean up permission monitoring resources
        permissionMonitorTimer?.invalidate()
        permissionMonitorTimer = nil

        if let observer = appActivationObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        // Note: Can't use logger in deinit due to main actor isolation
        print("WhisperNodeCore deinitialized")
    }
    
    public func initialize() {
        Self.logger.info("WhisperNode Core initializing...")

        // Setup hotkey manager delegate
        hotkeyManager.delegate = self

        // Setup audio engine callbacks
        setupAudioEngine()

        // Initialize with default model
        loadDefaultModel()

        // Setup performance monitoring with automatic adjustments
        setupPerformanceMonitoring()

        // Setup runtime permission monitoring
        setupPermissionMonitoring()

        isInitialized = true
        Self.logger.info("WhisperNode Core initialized successfully")
        
        // Start voice activation automatically if onboarding is complete AND accessibility permissions are granted
        if SettingsManager.shared.hasCompletedOnboarding {
            if checkAccessibilityPermissions() {
                Self.logger.info("🚀 Auto-starting voice activation - onboarding complete and permissions granted")
                startVoiceActivation()
            } else {
                Self.logger.warning("⚠️ Voice activation deferred - accessibility permissions not granted")
                Self.logger.info("💡 User can manually enable voice activation after granting accessibility permissions")
            }
        } else {
            Self.logger.info("⏳ Voice activation deferred - onboarding not complete")
        }
    }
    
    private func setupAudioEngine() {
        audioEngine.onAudioDataAvailable = { [weak self] audioData in
            Task { @MainActor in
                await self?.processAudioData(audioData)
            }
        }
        
        audioEngine.onVoiceActivityChanged = { [weak self] isVoiceDetected in
            Task { @MainActor in
                self?.handleVoiceActivityChange(isVoiceDetected)
            }
        }
    }
    
    private func loadDefaultModel() {
        // Use bundled tiny.en model by default for fast startup
        let modelName = "tiny.en"
        loadModel(modelName)
    }
    
    private func setupPerformanceMonitoring() {
        // PerformanceMonitor.shared is already started automatically
        // Setup performance observation for automatic adjustments
        setupPerformanceObservation()
    }

    /// Sets up runtime permission monitoring to automatically activate hotkey system when permissions become available
    private func setupPermissionMonitoring() {
        Self.logger.info("Setting up runtime permission monitoring using PermissionHelper")

        // Initialize current permission status
        lastAccessibilityPermissionStatus = PermissionHelper.shared.hasAccessibilityPermission
        Self.logger.info("Initial accessibility permission status: \(self.lastAccessibilityPermissionStatus)")

        // Use PermissionHelper's monitoring instead of duplicate timer
        PermissionHelper.shared.onPermissionChanged = { [weak self] granted in
            Task { @MainActor in
                await self?.handlePermissionChange(granted)
            }
        }

        // Start PermissionHelper monitoring if not already started
        if !PermissionHelper.shared.isMonitoring {
            PermissionHelper.shared.startMonitoring(interval: 5.0) // Use 5s for battery efficiency
        }
    }

    /// Handles permission status changes from PermissionHelper
    @MainActor
    private func handlePermissionChange(_ granted: Bool) async {
        let wasGranted = lastAccessibilityPermissionStatus
        let isNowGranted = granted

        // Update stored status
        lastAccessibilityPermissionStatus = granted

        // Only activate if permission status changed from denied to granted
        if !wasGranted && isNowGranted {
            Self.logger.info("Accessibility permissions detected as newly granted - activating hotkey system")

            // Start hotkey system immediately
            startVoiceActivation()

            // Update menu bar state to reflect activation
            menuBarManager.updateState(.normal)

            Self.logger.info("Hotkey system automatically activated after permission grant - no restart required")
        } else if wasGranted != isNowGranted {
            // Permission status changed (could be revoked)
            Self.logger.debug("Accessibility permission status changed to: \(isNowGranted)")

            if !isNowGranted {
                // Permission was revoked - stop hotkey system
                stopVoiceActivation()
                menuBarManager.updateState(.permissionRequired)
            }
        }
    }

    /// Checks current permission status and activates hotkey system if permissions became available
    @MainActor
    private func checkPermissionStatusAndActivateIfNeeded() async {
        // Use PermissionHelper's current status instead of direct AX call
        let currentPermissionStatus = PermissionHelper.shared.hasAccessibilityPermission

        // Delegate to the new permission change handler
        await handlePermissionChange(currentPermissionStatus)
    }
    
    private func setupPerformanceObservation() {
        // Monitor performance changes and apply automatic optimizations
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkAndApplyPerformanceAdjustments()
            }
        }
    }
    
    private func checkAndApplyPerformanceAdjustments() async {
        let monitor = performanceMonitor
        
        // Check if we need to downgrade model due to high CPU usage
        if monitor.shouldReducePerformance() {
            if let recommendedModel = monitor.getRecommendedModelDowngrade() {
                Self.logger.warning("High resource usage detected. Recommending model downgrade to \(recommendedModel)")
                
                // Apply automatic model downgrade if CPU usage > 80%
                if monitor.cpuUsage > 80.0 && recommendedModel != self.currentModel {
                    Self.logger.info("Automatically downgrading model from \(self.currentModel) to \(recommendedModel)")
                    loadModel(recommendedModel)
                }
            }
        }
        
        // Apply battery-aware optimizations
        if monitor.isOnBattery {
            let batterySettings = monitor.getBatteryOptimizedSettings()
            applyBatteryOptimizations(batterySettings)
        }
        
        // Handle thermal throttling
        if monitor.thermalState == .serious || monitor.thermalState == .critical {
            Self.logger.warning("Thermal throttling detected: \(monitor.thermalState.description)")
            applyThermalOptimizations()
        }
    }
    
    private func applyBatteryOptimizations(_ settings: [String: Any]) {
        if let enablePowerSaving = settings["enablePowerSaving"] as? Bool, enablePowerSaving {
            Self.logger.info("Applying battery power saving optimizations")
            // TODO: Implement battery optimizations
            // Reduce processing frequency or quality when battery is low
        }
    }
    
    private func applyThermalOptimizations() {
        Self.logger.info("Applying thermal throttling optimizations")
        // TODO: Implement thermal optimizations  
        // Reduce processing intensity during thermal pressure
    }
    
    // MARK: - Public Methods
    
    /// Start voice activation system
    ///
    /// Begins listening for the configured hotkey press-and-hold sequence.
    /// When activated, the system will start audio capture and transcription.
    ///
    /// ## Behavior
    /// - Registers global hotkey listener
    /// - Begins monitoring for press-and-hold activation
    /// - Requires accessibility permissions on macOS
    ///
    /// - Important: Ensure accessibility permissions are granted before calling
    /// - Note: This method is safe to call multiple times
    public func startVoiceActivation() {
        hotkeyManager.startListening()
    }
    
    /// Stop voice activation system
    ///
    /// Disables hotkey listening and stops all voice activation monitoring.
    /// Any active recording will be cancelled.
    ///
    /// ## Behavior
    /// - Unregisters global hotkey listener
    /// - Cancels any active recording session
    /// - Stops performance monitoring
    ///
    /// - Note: Safe to call even if voice activation is not currently active
    public func stopVoiceActivation() {
        hotkeyManager.stopListening()
    }
    
    public func updateHotkey(_ configuration: HotkeyConfiguration) {
        hotkeyManager.updateHotkey(configuration)
    }
    
    /// Load a whisper model for transcription
    ///
    /// Asynchronously loads the specified Whisper model for speech recognition.
    /// Includes automatic fallback to smaller models if loading fails.
    ///
    /// - Parameter modelName: Name of the model to load
    ///
    /// ## Supported Models
    /// - `tiny.en`: ~39MB, fastest inference, basic accuracy
    /// - `small.en`: ~244MB, balanced performance and accuracy  
    /// - `medium.en`: ~769MB, highest accuracy, slower inference
    ///
    /// ## Fallback Behavior
    /// If the requested model fails to load:
    /// 1. Automatically attempts to load `tiny.en` as fallback
    /// 2. Posts notification if all models fail to load
    /// 3. Logs detailed error information for debugging
    ///
    /// ## Memory Management
    /// - Models are loaded lazily on first transcription
    /// - Automatic cleanup after 30 seconds of inactivity
    /// - Memory usage enforced per model type limits
    ///
    /// - Important: Model switching requires app restart for full memory cleanup
    public func loadModel(_ modelName: String) {
        Task {
            Self.logger.info("Loading whisper model: \(modelName)")
            
            // Construct model path (in production this would be in app bundle or downloads)
            let modelPath = getModelPath(for: modelName)
            
            if let engine = WhisperEngine(modelPath: modelPath) {
                await MainActor.run {
                    self.whisperEngine = engine
                    self.currentModel = modelName
                    self.currentModelPath = modelPath
                    Self.logger.info("Whisper model loaded successfully: \(modelName)")
                }
            } else {
                Self.logger.error("Failed to load whisper model: \(modelName)")
                // Try fallback to smaller model
                if modelName != "tiny.en" {
                    Self.logger.info("Attempting fallback to tiny.en model")
                    await MainActor.run {
                        errorManager.handleModelDownloadFailure("Model \(modelName) failed to load") {
                            self.loadModel("tiny.en")
                        }
                    }
                } else {
                    // Critical failure - no fallback available
                    await MainActor.run {
                        errorManager.handleError(.modelDownloadFailed("All available models failed to load"))
                        NotificationCenter.default.post(name: .whisperModelLoadFailed, object: nil)
                    }
                }
            }
        }
    }
    
    /// Switch to a different model (requires app restart for full memory cleanup)
    ///
    /// Changes the active Whisper model with automatic cleanup of the previous model.
    /// For complete memory cleanup, an app restart is recommended.
    ///
    /// - Parameter modelName: Name of the new model to load
    ///
    /// ## Memory Considerations
    /// - Previous model memory is cleaned up automatically
    /// - Some memory fragmentation may remain until app restart
    /// - Large model switches may temporarily exceed memory limits
    ///
    /// ## Performance Impact
    /// - Brief interruption in transcription capability during switch
    /// - First transcription may have higher latency while loading
    /// - Performance monitoring continues throughout switch
    ///
    /// - Important: Consider app restart after switching to large models
    /// - Note: Model loading is performed asynchronously
    public func switchModel(_ modelName: String) {
        Self.logger.info("Switching model from \(self.currentModel) to \(modelName)")
        
        // Clean up current model
        Task {
            if let engine = whisperEngine {
                await engine.cleanupMemory()
            }
            
            // Load new model
            loadModel(modelName)
        }
    }
    
    /// Get current performance metrics
    ///
    /// Retrieves comprehensive performance data including memory usage,
    /// CPU utilization, and automatic optimization recommendations.
    ///
    /// - Returns: Tuple containing:
    ///   - `memory`: Current memory usage in bytes
    ///   - `cpu`: Average CPU usage percentage (0-100)
    ///   - `modelDowngradeNeeded`: Whether model optimization is recommended
    ///
    /// ## Performance Monitoring
    /// - Memory usage includes model and processing overhead
    /// - CPU usage is averaged over recent transcription operations
    /// - Downgrade recommendations based on performance thresholds
    ///
    /// ## Usage
    /// ```swift
    /// let (memory, cpu, needsDowngrade) = await core.getPerformanceMetrics()
    /// if needsDowngrade {
    ///     // Consider switching to a smaller model
    /// }
    /// ```
    ///
    /// - Important: This method is async and should be called with await
    /// - Note: Metrics are updated in real-time during transcription
    public func getPerformanceMetrics() async -> (memory: UInt64, cpu: Float, modelDowngradeNeeded: Bool) {
        return (memoryUsage, averageCpuUsage, await checkModelDowngradeNeeded())
    }
    
    /// Force memory cleanup
    ///
    /// Immediately triggers comprehensive memory cleanup including model unloading,
    /// cache clearing, and resource deallocation.
    ///
    /// ## Cleanup Operations
    /// - Unloads idle Whisper models
    /// - Clears audio processing buffers
    /// - Deallocates temporary resources
    /// - Triggers garbage collection
    ///
    /// ## When to Use
    /// - Before loading large models
    /// - On memory pressure warnings
    /// - During app backgrounding
    /// - Manual optimization
    ///
    /// ## Performance Impact
    /// - Brief interruption in transcription capability
    /// - Next transcription may have higher latency
    /// - Reduces overall memory footprint
    ///
    /// - Note: Cleanup is performed asynchronously
    /// - Important: Safe to call during active recording
    public func cleanupMemory() {
        Task {
            if let engine = whisperEngine {
                let success = await engine.cleanupMemory()
                Self.logger.info("Memory cleanup \(success ? "successful" : "failed")")
            }
        }
    }

    /// Manually trigger permission status check and hotkey activation if permissions are available
    ///
    /// This method can be called when preferences window closes or when the app needs to
    /// check if accessibility permissions have been granted at runtime.
    ///
    /// ## Usage
    /// - Call when preferences window closes
    /// - Call after user might have granted permissions in System Preferences
    /// - Safe to call multiple times
    ///
    /// ## Behavior
    /// - Checks current accessibility permission status
    /// - Automatically starts hotkey system if permissions are newly available
    /// - Updates UI state to reflect activation
    /// - Logs permission status changes
    ///
    /// - Note: This method is async and should be called with await
    /// - Important: Safe to call even if hotkey system is already active
    public func checkPermissionsAndActivateIfNeeded() async {
        await checkPermissionStatusAndActivateIfNeeded()
    }
    
    // MARK: - Private Implementation
    
    /// Check if accessibility permissions are granted for global hotkey functionality
    ///
    /// This method performs a non-intrusive check for accessibility permissions without
    /// showing system prompts. It's used for auto-start permission verification.
    ///
    /// - Returns: `true` if accessibility permissions are granted, `false` otherwise
    /// - Note: This method does NOT trigger permission prompts, making it safe for auto-start checks
    private func checkAccessibilityPermissions() -> Bool {
        let trusted = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [trusted: false] as CFDictionary // Don't prompt during auto-start check
        let hasPermissions = AXIsProcessTrustedWithOptions(options)
        
        Self.logger.info("Auto-start accessibility permissions check: \(hasPermissions ? "granted" : "denied")")
        
        return hasPermissions
    }
    
    private func getModelPath(for modelName: String) -> String {
        // Check bundle resources first
        if let bundlePath = Bundle.main.path(forResource: modelName, ofType: "bin") {
            return bundlePath
        }
        
        // Fallback to app documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, 
                                                    in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("\(modelName).bin").path
    }
    
    /// Processes captured audio data by transcribing it with the Whisper engine and updating the UI indicator to reflect processing progress, success, or error states.
    ///
    /// Converts raw audio data to float samples, simulates progress updates on the processing indicator, and performs asynchronous transcription. On success, hides the indicator and logs the result; on failure, displays an error indicator briefly before hiding it. Performance warnings are logged if high resource usage is detected.
    public func processAudioData(_ audioData: Data) async {
        guard let engine = whisperEngine else { return }
        
        // Convert Data to Float array for whisper processing
        let audioSamples = audioData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
        
        // Show processing state immediately (real progress updates should come from whisper engine)
        await MainActor.run {
            indicatorManager.updateState(.processing, progress: 0.0)
        }
        
        // Perform transcription
        let result = await engine.transcribe(audioData: audioSamples)
        
        if result.success {
            Self.logger.info("Transcription completed: \(result.text)")
            
            // Hide indicator after successful transcription
            await MainActor.run {
                indicatorManager.hideIndicator()
            }
            
            // Insert transcribed text at cursor position
            await textInsertionEngine.insertText(result.text)
            
            // Haptic feedback for successful text insertion
            await MainActor.run {
                HapticManager.shared.textInserted()
            }
            
            // Check for performance warnings
            if let metrics = result.metrics, metrics.isDowngradeNeeded {
                Self.logger.warning("High CPU usage detected, model downgrade recommended")
            }
        } else {
            Self.logger.error("Transcription failed: \(result.error ?? "Unknown error")")
            
            // Handle transcription failure with error manager (silent failure with red orb flash)
            await MainActor.run {
                errorManager.handleTranscriptionFailure()
                // Haptic feedback for transcription error
                HapticManager.shared.errorOccurred()
            }
        }
    }
    
    /// Updates the recording indicator based on current voice activity and recording state.
    ///
    /// Shows the recording indicator when voice is detected during recording, or shows the idle indicator if recording is active but no voice is detected.
    ///
    /// - Parameter isVoiceDetected: Indicates whether voice activity is currently detected.
    private func handleVoiceActivityChange(_ isVoiceDetected: Bool) {
        Self.logger.debug("Voice activity changed: \(isVoiceDetected)")
        
        // Update visual indicator based on voice activity
        if isVoiceDetected && isRecording {
            indicatorManager.showRecording()
        } else if isRecording {
            indicatorManager.showIdle()
        }
    }
    
    /// Asynchronously updates memory and CPU usage metrics from the Whisper engine.
    ///
    /// If performance thresholds are exceeded, logs a warning with a suggested model downgrade.
    private func checkModelDowngradeNeeded() async -> Bool {
        // Use the new PerformanceMonitor for downgrade decisions
        return performanceMonitor.shouldReducePerformance()
    }
    
}

// MARK: - GlobalHotkeyManagerDelegate

extension WhisperNodeCore: GlobalHotkeyManagerDelegate {
    public func hotkeyManager(_ manager: GlobalHotkeyManager, didStartListening isListening: Bool) {
        Self.logger.info("Hotkey listening status changed: \(isListening)")
    }
    
    /// Handles the start of voice recording triggered by the global hotkey.
    ///
    /// Updates the recording state, displays the recording indicator, starts performance monitoring, and initiates audio capture. If audio capture fails to start, resets the recording state, hides the indicator, and stops monitoring.
    public func hotkeyManager(_ manager: GlobalHotkeyManager, didStartRecording isRecording: Bool) {
        Self.logger.info("🎤 Voice recording started - delegate callback received")

        // Validate state consistency before proceeding
        if !validateAudioEngineState() {
            Self.logger.warning("State inconsistency detected during recording start")
        }

        // Update state first
        self.isRecording = isRecording
        Self.logger.info("🔊 WhisperNodeCore delegate method called successfully")

        // Haptic feedback for recording start
        HapticManager.shared.recordingStarted()

        // Update menu bar state
        menuBarManager.updateState(.recording)

        // Show visual indicator with enhanced logging
        Self.logger.info("🟢 Attempting to show recording indicator")
        indicatorManager.showRecording()
        Self.logger.info("✅ indicatorManager.showRecording() called")

        // Verify indicator manager state
        Self.logger.info("📊 Indicator state - isVisible: \(self.indicatorManager.isVisible), currentState: \(String(describing: self.indicatorManager.currentState))")

        // Performance monitoring is always active via PerformanceMonitor.shared

        // Start audio capture engine with enhanced error handling
        Task { [weak self] in
            do {
                try await self?.audioEngine.startCapture()
                Self.logger.info("Audio capture started successfully")

                // Validate state after successful start
                await MainActor.run {
                    if let self = self, !self.validateAudioEngineState() {
                        Self.logger.warning("State mismatch after successful audio start")
                    }
                }
            } catch {
                Self.logger.error("Failed to start audio capture: \(error.localizedDescription)")

                // Revert state on failure
                await MainActor.run {
                    self?.handleAudioStartFailure(error)
                }
            }
        }
    }
    
    /// Handles completion of voice recording triggered by the hotkey manager.
    ///
    /// Updates the recording state, displays a processing indicator after a short delay, stops performance monitoring, and stops audio capture. Audio data processing is handled asynchronously by the audio engine callbacks.
    ///
    /// - Parameter duration: The duration of the completed voice recording, in seconds.
    public func hotkeyManager(_ manager: GlobalHotkeyManager, didCompleteRecording duration: CFTimeInterval) {
        Self.logger.info("Voice recording completed after \(duration)s")

        // Validate state consistency before proceeding
        if !validateAudioEngineState() {
            Self.logger.warning("State inconsistency detected during recording completion")
        }

        // Update state
        isRecording = false

        // Haptic feedback for recording completion
        HapticManager.shared.recordingStopped()

        // Update menu bar state back to normal
        menuBarManager.updateState(.normal)

        // Show processing indicator after brief delay to avoid flicker
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.processingStateDelay)
            await MainActor.run {
                self?.indicatorManager.showProcessing(progress: 0.0)
            }
        }

        // Performance monitoring continues in background

        // Stop audio capture with state validation
        Task { [weak self] in
            // Note: stopCapture() is synchronous and doesn't throw
            await MainActor.run {
                self?.audioEngine.stopCapture()
            }
            Self.logger.info("Audio capture stopped successfully")

            // Validate state after stop
            await MainActor.run {
                if let self = self, !self.validateAudioEngineState() {
                    Self.logger.warning("State mismatch after audio stop")
                }
            }

            // The audio processing will be handled by the audioEngine callbacks
            // which will trigger processAudioData() automatically
        }
    }
    
    /// Handles the cancellation of voice recording triggered by the hotkey manager.
    ///
    /// Resets the recording state, hides the recording indicator, stops performance monitoring, and halts audio capture.
    public func hotkeyManager(_ manager: GlobalHotkeyManager, didCancelRecording reason: RecordingCancelReason) {
        Self.logger.info("Voice recording cancelled - reason: \(String(describing: reason))")

        // Validate state consistency before proceeding
        if !validateAudioEngineState() {
            Self.logger.warning("State inconsistency detected during recording cancellation")
        }

        // Update state
        isRecording = false

        // Haptic feedback for recording cancellation
        HapticManager.shared.recordingCancelled()

        // Update menu bar state back to normal
        menuBarManager.updateState(.normal)

        // Hide visual indicator
        indicatorManager.hideIndicator()

        // Performance monitoring continues in background

        // Stop audio capture with state validation
        Task { [weak self] in
            // Note: stopCapture() is synchronous and doesn't throw
            await MainActor.run {
                self?.audioEngine.stopCapture()
            }
            Self.logger.info("Audio capture cancelled successfully")

            // Validate state after cancellation
            await MainActor.run {
                if let self = self, !self.validateAudioEngineState() {
                    Self.logger.warning("State mismatch after audio cancellation")
                }
            }
        }
    }
    
    /// Handles errors from the global hotkey manager by logging the error and displaying an error indicator briefly.
    ///
    /// The error indicator is shown immediately and then hidden after a short delay. This method is called when the hotkey manager encounters an error.
    public func hotkeyManager(_ manager: GlobalHotkeyManager, didFailWithError error: HotkeyError) {
        Self.logger.error("Hotkey manager error: \(error.localizedDescription)")
        
        // Haptic feedback for error
        HapticManager.shared.errorOccurred()
        
        // Update menu bar state to indicate error
        menuBarManager.updateState(.error)
        
        // Handle hotkey error through error manager with proper error mapping
        switch error {
        case .accessibilityPermissionDenied:
            errorManager.handleError(.accessibilityPermissionDenied)
        case .eventTapCreationFailed:
            errorManager.handleError(.hotkeySystemError("Failed to create global event tap"))
        case .hotkeyConflict(let description):
            errorManager.handleError(.hotkeyConflict(description))
        }
    }
    
    public func hotkeyManager(_ manager: GlobalHotkeyManager, accessibilityPermissionRequired: Bool) {
        Self.logger.warning("Accessibility permissions required for global hotkey functionality")

        // Show user-friendly error message with proper error type
        errorManager.handleError(.accessibilityPermissionDenied)

        // Update menu bar to indicate permission issue (use specific permission state)
        menuBarManager.updateState(.permissionRequired)

        // Haptic feedback for permission error
        HapticManager.shared.errorOccurred()
    }
    
    public func hotkeyManager(_ manager: GlobalHotkeyManager, didDetectConflict conflict: HotkeyConflict, suggestedAlternatives: [HotkeyConfiguration]) {
        Self.logger.warning("Hotkey conflict detected: \(conflict.description)")

        // Handle hotkey conflict with non-blocking notification
        errorManager.handleHotkeyConflict(conflict.description)
    }
}

// MARK: - Audio Engine Error Handling & State Management

extension WhisperNodeCore {

    /// Handles audio engine start failures with comprehensive error recovery
    ///
    /// Reverts all state changes, provides user feedback, and ensures clean system state
    /// - Parameter error: The error that occurred during audio engine start
    private func handleAudioStartFailure(_ error: Error) {
        Self.logger.error("Audio start failure: \(error)")

        // Revert state to ensure consistency
        isRecording = false
        menuBarManager.updateState(.normal)
        indicatorManager.hideIndicator()

        // Handle specific audio capture errors with appropriate user feedback
        if let captureError = error as? AudioCaptureEngine.CaptureError {
            switch captureError {
            case .permissionDenied:
                errorManager.handleMicrophoneAccessDenied()
            case .deviceNotAvailable:
                errorManager.handleError(.audioCaptureFailure("Audio device not available"))
            case .formatNotSupported:
                errorManager.handleError(.audioCaptureFailure("Audio format not supported"))
            case .bufferOverrun:
                errorManager.handleError(.audioCaptureFailure("Audio buffer overrun"))
            case .engineNotRunning:
                errorManager.handleError(.audioCaptureFailure("Audio engine not running"))
            }
        } else {
            // Generic audio failure
            errorManager.handleError(.audioCaptureFailure("Failed to start audio capture: \(error.localizedDescription)"))
        }

        // Provide haptic feedback for error
        HapticManager.shared.errorOccurred()

        // Validate final state
        if !validateAudioEngineState() {
            Self.logger.error("State still inconsistent after error handling")
        }
    }

    /// Handles audio engine stop failures during recording completion
    ///
    /// Ensures clean state and provides appropriate error feedback
    /// - Parameter error: The error that occurred during audio engine stop
    private func handleAudioStopFailure(_ error: Error) {
        Self.logger.error("Audio stop failure: \(error)")

        // Ensure clean state regardless of stop failure
        isRecording = false
        menuBarManager.updateState(.normal)
        indicatorManager.hideIndicator()

        // Show error to user
        errorManager.handleError(.audioCaptureFailure("Failed to stop audio capture: \(error.localizedDescription)"))

        // Validate final state
        if !validateAudioEngineState() {
            Self.logger.error("State still inconsistent after stop failure handling")
        }
    }

    /// Handles audio engine cancellation failures
    ///
    /// Ensures clean state but avoids showing errors to user (cancellation should be silent)
    /// - Parameter error: The error that occurred during audio engine cancellation
    private func handleAudioCancelFailure(_ error: Error) {
        Self.logger.error("Audio cancel failure: \(error)")

        // Ensure clean state regardless of cancellation error
        isRecording = false
        menuBarManager.updateState(.normal)
        indicatorManager.hideIndicator()

        // Log error but don't show to user (cancellation should be silent)
        // Only log for debugging purposes

        // Validate final state
        if !validateAudioEngineState() {
            Self.logger.error("State still inconsistent after cancel failure handling")
        }
    }

    /// Validates that UI state matches audio engine state
    ///
    /// Detects and attempts to correct state inconsistencies between the core recording state
    /// and the actual audio engine state. This helps prevent silent failures where the UI
    /// shows recording but no audio is being captured.
    ///
    /// - Returns: `true` if states are consistent, `false` if inconsistencies were detected
    private func validateAudioEngineState() -> Bool {
        let engineIsRecording = audioEngine.isCapturing
        let coreIsRecording = isRecording

        // First validate the audio engine's internal state
        let audioEngineStateValid = audioEngine.validateState()
        if !audioEngineStateValid {
            Self.logger.warning("Audio engine internal state is inconsistent")
        }

        if engineIsRecording != coreIsRecording {
            Self.logger.warning("State mismatch detected - Engine recording: \(engineIsRecording), Core recording: \(coreIsRecording)")

            // Log detailed diagnostics for debugging
            let diagnostics = audioEngine.getDiagnostics()
            Self.logger.debug("Audio engine diagnostics: \(diagnostics)")

            // Attempt to synchronize states
            if engineIsRecording && !coreIsRecording {
                // Engine is capturing but core thinks it's not - stop engine
                Self.logger.info("Stopping orphaned audio engine")
                audioEngine.stopCapture()
            } else if !engineIsRecording && coreIsRecording {
                // Core thinks it's recording but engine is not - update core state
                Self.logger.info("Correcting core state to match engine")
                isRecording = false
                menuBarManager.updateState(.normal)
                indicatorManager.hideIndicator()
            }

            return false
        }

        return audioEngineStateValid
    }

    /// Provides comprehensive diagnostics for the entire recording system
    ///
    /// Returns detailed information about all components involved in the recording pipeline,
    /// including core state, audio engine state, UI state, and system configuration.
    /// Useful for debugging complex state synchronization issues.
    ///
    /// - Returns: Dictionary containing comprehensive diagnostic information
    public func getRecordingSystemDiagnostics() -> [String: Any] {
        let audioEngineDiagnostics = audioEngine.getDiagnostics()

        return [
            "coreState": [
                "isRecording": isRecording,
                "stateValidation": validateAudioEngineState()
            ],
            "audioEngine": audioEngineDiagnostics,
            "ui": [
                "indicatorVisible": indicatorManager.isVisible,
                "indicatorState": String(describing: indicatorManager.currentState),
                "menuBarState": String(describing: menuBarManager.currentState)
            ],
            "system": [
                "timestamp": Date().timeIntervalSince1970,
                "performanceSnapshot": [
                    "cpuUsage": performanceMonitor.getCurrentSnapshot().cpuUsage,
                    "memoryUsageMB": performanceMonitor.getCurrentSnapshot().memoryUsageMB,
                    "batteryLevel": performanceMonitor.getCurrentSnapshot().batteryLevel,
                    "isOnBattery": performanceMonitor.getCurrentSnapshot().isOnBattery,
                    "isThrottling": performanceMonitor.getCurrentSnapshot().isThrottling
                ]
            ]
        ]
    }
}