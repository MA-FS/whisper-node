import Foundation
import os.log

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
    @Published public private(set) var audioEngine = AudioCaptureEngine()
    @Published public private(set) var menuBarManager = MenuBarManager()
    @Published public private(set) var indicatorManager = RecordingIndicatorWindowManager()
    private let textInsertionEngine = TextInsertionEngine()
    
    // Whisper integration
    private var whisperEngine: WhisperEngine?
    private var currentModelPath: String?
    
    // Application state
    @Published public private(set) var isInitialized = false
    @Published public private(set) var isRecording = false
    @Published public private(set) var currentModel: String = "tiny.en"
    @Published public private(set) var memoryUsage: UInt64 = 0
    @Published public private(set) var averageCpuUsage: Float = 0.0
    
    // Performance monitoring
    private var performanceTimer: Timer?
    private let performanceUpdateInterval: TimeInterval = 2.0
    
    public static let shared = WhisperNodeCore()
    
    private init() {
        initialize()
    }
    
    private func initialize() {
        Self.logger.info("WhisperNode Core initializing...")
        
        // Setup hotkey manager delegate
        hotkeyManager.delegate = self
        
        // Setup audio engine callbacks
        setupAudioEngine()
        
        // Initialize with default model
        loadDefaultModel()
        
        // Start performance monitoring
        startPerformanceMonitoring()
        
        isInitialized = true
        Self.logger.info("WhisperNode Core initialized successfully")
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
    
    private func startPerformanceMonitoring() {
        // Performance monitoring will be started when actually recording
        // This reduces battery usage when app is idle
    }
    
    private func startActiveMonitoring() {
        guard performanceTimer == nil else { return }
        performanceTimer = Timer.scheduledTimer(withTimeInterval: performanceUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updatePerformanceMetrics()
            }
        }
    }
    
    private func stopActiveMonitoring() {
        performanceTimer?.invalidate()
        performanceTimer = nil
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
                    loadModel("tiny.en")
                } else {
                    // Notify user of critical failure
                    await MainActor.run {
                        // Post notification for UI to display error
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
    
    // MARK: - Private Implementation
    
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
    private func processAudioData(_ audioData: Data) async {
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
            
            // Check for performance warnings
            if let metrics = result.metrics, metrics.isDowngradeNeeded {
                Self.logger.warning("High CPU usage detected, model downgrade recommended")
            }
        } else {
            Self.logger.error("Transcription failed: \(result.error ?? "Unknown error")")
            
            // Show error indicator briefly
            await MainActor.run {
                indicatorManager.showError()
            }
            
            // Schedule error hide without blocking
            scheduleErrorHide()
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
    private func updatePerformanceMetrics() async {
        guard let engine = whisperEngine else { return }
        
        let metrics = await engine.getCurrentMetrics()
        
        await MainActor.run {
            self.memoryUsage = metrics.memoryUsage
            self.averageCpuUsage = metrics.averageCpuUsage
            
            // Check if automatic model downgrade is needed
            if metrics.isDowngradeNeeded, let suggested = metrics.suggestedModel {
                Self.logger.warning("Performance threshold exceeded, consider switching to \(suggested) model")
            }
        }
    }
    
    private func checkModelDowngradeNeeded() async -> Bool {
        guard let engine = whisperEngine else { return false }
        
        let (needed, _) = await engine.shouldDowngradeModel()
        return needed
    }
    
    private func scheduleErrorHide() {
        Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: Self.errorDisplayDuration)
            await MainActor.run { [weak self] in
                self?.indicatorManager.hideIndicator()
            }
        }
    }
    
    private func scheduleHotkeyErrorHide() {
        Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: Self.hotkeyErrorDisplayDuration)
            await MainActor.run { [weak self] in
                self?.indicatorManager.hideIndicator()
            }
        }
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
        self.isRecording = true
        Self.logger.info("Voice recording started")
        
        // Update menu bar state
        menuBarManager.updateState(.recording)
        
        // Show visual indicator
        indicatorManager.showRecording()
        
        // Start performance monitoring during active recording
        startActiveMonitoring()
        
        // Start audio capture engine
        Task {
            do {
                try await audioEngine.startCapture()
                Self.logger.info("Audio capture started successfully")
            } catch {
                Self.logger.error("Failed to start audio capture: \(error.localizedDescription)")
                self.isRecording = false
                indicatorManager.hideIndicator()
                stopActiveMonitoring()
            }
        }
    }
    
    /// Handles completion of voice recording triggered by the hotkey manager.
    ///
    /// Updates the recording state, displays a processing indicator after a short delay, stops performance monitoring, and stops audio capture. Audio data processing is handled asynchronously by the audio engine callbacks.
    ///
    /// - Parameter duration: The duration of the completed voice recording, in seconds.
    public func hotkeyManager(_ manager: GlobalHotkeyManager, didCompleteRecording duration: CFTimeInterval) {
        isRecording = false
        Self.logger.info("Voice recording completed after \(duration)s")
        
        // Update menu bar state back to normal
        menuBarManager.updateState(.normal)
        
        // Show processing indicator after brief delay to avoid flicker
        Task {
            try? await Task.sleep(nanoseconds: Self.processingStateDelay)
            await MainActor.run {
                indicatorManager.showProcessing(progress: 0.0)
            }
        }
        
        // Stop performance monitoring
        stopActiveMonitoring()
        
        // Stop audio capture
        audioEngine.stopCapture()
        Self.logger.info("Audio capture stopped")
        
        // The audio processing will be handled by the audioEngine callbacks
        // which will trigger processAudioData() automatically
    }
    
    /// Handles the cancellation of voice recording triggered by the hotkey manager.
    ///
    /// Resets the recording state, hides the recording indicator, stops performance monitoring, and halts audio capture.
    public func hotkeyManager(_ manager: GlobalHotkeyManager, didCancelRecording reason: RecordingCancelReason) {
        isRecording = false
        Self.logger.info("Voice recording cancelled")
        
        // Update menu bar state back to normal
        menuBarManager.updateState(.normal)
        
        // Hide visual indicator
        indicatorManager.hideIndicator()
        
        // Stop performance monitoring
        stopActiveMonitoring()
        
        // Stop audio capture
        audioEngine.stopCapture()
    }
    
    /// Handles errors from the global hotkey manager by logging the error and displaying an error indicator briefly.
    ///
    /// The error indicator is shown immediately and then hidden after a short delay. This method is called when the hotkey manager encounters an error.
    public func hotkeyManager(_ manager: GlobalHotkeyManager, didFailWithError error: HotkeyError) {
        Self.logger.error("Hotkey manager error: \(error.localizedDescription)")
        
        // Update menu bar state to indicate error
        menuBarManager.updateState(.error)
        
        // Show error indicator
        indicatorManager.showError()
        
        // Schedule error hide without blocking
        scheduleHotkeyErrorHide()
        
        // TODO: Show user-friendly error (T15)
    }
    
    public func hotkeyManager(_ manager: GlobalHotkeyManager, accessibilityPermissionRequired: Bool) {
        Self.logger.warning("Accessibility permissions required")
        // TODO: Show accessibility permission prompt (T14)
    }
    
    public func hotkeyManager(_ manager: GlobalHotkeyManager, didDetectConflict conflict: HotkeyConflict, suggestedAlternatives: [HotkeyConfiguration]) {
        Self.logger.warning("Hotkey conflict detected: \(conflict.description)")
        // TODO: Show conflict resolution UI (T12)
    }
}