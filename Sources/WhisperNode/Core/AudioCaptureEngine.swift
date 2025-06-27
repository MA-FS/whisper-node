import AVFoundation
import Accelerate
import Foundation
import os.log
#if os(macOS)
import CoreAudio
#endif

/// A comprehensive audio capture engine for real-time voice input processing
/// 
/// The `AudioCaptureEngine` provides a complete solution for capturing audio from the microphone
/// with voice activity detection, permission management, and real-time processing capabilities.
/// It's designed specifically for voice-to-text applications requiring low-latency audio capture.
///
/// ## Features
/// - 16kHz mono audio capture optimized for speech recognition
/// - Real-time voice activity detection with configurable threshold
/// - Thread-safe circular buffering for continuous audio streaming
/// - Comprehensive permission handling for microphone access
/// - Live input level monitoring and voice activity callbacks
/// - Support for audio device selection and management
///
/// ## Usage
/// ```swift
/// let audioEngine = AudioCaptureEngine()
/// 
/// // Request microphone permission
/// let granted = await audioEngine.requestPermission()
/// 
/// // Set up callbacks
/// audioEngine.onAudioDataAvailable = { audioData in
///     // Process captured audio data
/// }
/// 
/// audioEngine.onVoiceActivityChanged = { isVoiceDetected in
///     // Update UI based on voice activity
/// }
/// 
/// // Start capturing
/// try await audioEngine.startCapture()
/// ```
@MainActor
public class AudioCaptureEngine: ObservableObject {

    /// Shared singleton instance
    public static let shared = AudioCaptureEngine()

    /// Logger for audio capture operations
    private static let logger = Logger(subsystem: "com.whispernode.audio", category: "AudioCaptureEngine")

    // MARK: - Audio System Integration

    /// Audio device manager for enhanced device handling
    private let deviceManager = AudioDeviceManager.shared

    /// Audio permission manager for enhanced permission handling
    private let permissionManager = AudioPermissionManager.shared

    /// Audio diagnostics for system validation
    private let diagnostics = AudioDiagnostics.shared

    /// Time-based logging throttle properties
    private var lastLogTime: TimeInterval = 0
    private let logInterval: TimeInterval = 3.0
    
    /// Errors that can occur during audio capture operations
    public enum CaptureError: Error, LocalizedError, Equatable {
        /// Audio engine failed to start or is not currently running
        case engineNotRunning
        /// Microphone permission has been denied by the user
        case permissionDenied
        /// Requested audio device is not available or accessible
        case deviceNotAvailable
        /// Audio format configuration is not supported by the system
        case formatNotSupported
        /// Audio buffer has exceeded capacity and data may be lost
        case bufferOverrun
        
        public var errorDescription: String? {
            switch self {
            case .engineNotRunning:
                return "Audio engine is not running"
            case .permissionDenied:
                return "Microphone permission denied"
            case .deviceNotAvailable:
                return "Audio device not available"
            case .formatNotSupported:
                return "Audio format not supported"
            case .bufferOverrun:
                return "Audio buffer overrun detected"
            }
        }
    }
    
    /// Current state of the audio capture engine
    public enum CaptureState: Equatable {
        /// Engine is idle and not capturing audio
        case idle
        /// Engine is initializing and preparing to capture
        case starting
        /// Engine is actively recording audio
        case recording
        /// Engine is shutting down capture operations
        case stopping
        /// Engine encountered an error during operation
        case error(CaptureError)
    }
    
    /// Microphone permission status
    public enum PermissionStatus {
        /// User has granted microphone access
        case granted
        /// User has denied microphone access
        case denied
        /// Permission status has not been determined yet
        case undetermined
    }
    
    private let audioEngine = AVAudioEngine()
    private let circularBuffer: CircularAudioBuffer
    private let vadDetector: VoiceActivityDetector
    
    /// Current state of the audio capture engine
    @Published public private(set) var captureState: CaptureState = .idle
    
    /// Current input level in decibels (dB)
    @Published public private(set) var inputLevel: Float = 0.0
    
    /// Whether voice activity is currently detected
    @Published public private(set) var isVoiceDetected: Bool = false

    /// Convenience property to check if the engine is actively capturing audio
    public var isCapturing: Bool {
        return captureState == .recording
    }

    /// Callback invoked when audio data is available (only when voice is detected)
    /// - Parameter data: Raw audio data as Float samples converted to Data
    public var onAudioDataAvailable: ((Data) -> Void)?
    
    /// Callback invoked for all raw audio data (regardless of voice detection)
    /// - Parameter data: Raw audio data as Float samples converted to Data
    public var onRawAudioDataAvailable: ((Data) -> Void)?
    
    /// Callback invoked when voice activity status changes
    /// - Parameter detected: True if voice activity is detected, false otherwise
    public var onVoiceActivityChanged: ((Bool) -> Void)?
    
    private var recordingFormat: AVAudioFormat? {
        // Use the input node's native format for better compatibility
        let inputFormat = audioEngine.inputNode.inputFormat(forBus: 0)
        Self.logger.debug("Input node native format: \(String(describing: inputFormat))")

        // If the input format is valid, use it; otherwise fall back to 16kHz mono
        if inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 {
            return inputFormat
        } else {
            Self.logger.info("Input format invalid, using fallback 16kHz mono")
            return AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)
        }
    }
    
    /// Initialize the audio capture engine
    /// - Parameters:
    ///   - bufferDuration: Duration of the circular buffer in seconds (default: 1.0 second)
    ///   - vadThreshold: Voice activity detection threshold in decibels (default: -40.0 dB)
    private init(bufferDuration: TimeInterval = 1.0, vadThreshold: Float = -40.0) {
        let sampleRate = 16000.0 // 16kHz mono
        let capacity = Int(sampleRate * bufferDuration)
        self.circularBuffer = CircularAudioBuffer(capacity: capacity)
        self.vadDetector = VoiceActivityDetector(threshold: vadThreshold)
        
        setupNotifications()
        setupBufferOverrunHandling()
        setupAudioSystemIntegration()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        // Note: Cannot call async methods in deinit
        // Audio engine will be cleaned up automatically
    }
    
    // MARK: - Public Interface
    
    /// Request microphone permission from the user with enhanced guidance
    ///
    /// Uses the enhanced AudioPermissionManager for better user experience
    /// and comprehensive permission handling.
    ///
    /// - Returns: True if permission is granted, false otherwise
    public func requestPermission() async -> Bool {
        let result = await permissionManager.requestPermissionWithGuidance()
        return result.status.allowsCapture
    }

    /// Request microphone permission with detailed result information
    ///
    /// - Returns: Detailed permission result with guidance and recovery actions
    public func requestPermissionWithGuidance() async -> AudioPermissionManager.PermissionResult {
        return await permissionManager.requestPermissionWithGuidance()
    }
    
    /// Check the current microphone permission status
    ///
    /// Uses the enhanced AudioPermissionManager for comprehensive status checking.
    ///
    /// - Returns: Current permission status without prompting the user
    public func checkPermissionStatus() -> PermissionStatus {
        let enhancedStatus = permissionManager.checkPermissionStatus()

        // Convert enhanced status to legacy format for compatibility
        switch enhancedStatus {
        case .granted: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined, .temporarilyUnavailable: return .undetermined
        }
    }
    
    /// Start audio capture with voice activity detection
    ///
    /// Initializes the audio engine and begins capturing audio from the default input device.
    /// The engine will process audio in real-time, detecting voice activity and providing
    /// callbacks when voice is detected.
    ///
    /// - Throws: `CaptureError.permissionDenied` if microphone access is denied
    /// - Throws: `CaptureError.engineNotRunning` if the audio engine fails to start
    public func startCapture() async throws {
        Self.logger.info("Starting audio capture with enhanced validation...")

        // Enhanced permission validation
        let permissionResult = await permissionManager.requestPermissionWithGuidance()
        Self.logger.debug("Enhanced permission status: \(permissionResult.status.description)")

        guard permissionResult.status.allowsCapture else {
            Self.logger.error("Permission denied, cannot start capture: \(permissionResult.userMessage ?? "Unknown reason")")
            updateCaptureState(.error(.permissionDenied))
            throw CaptureError.permissionDenied
        }

        // Check if already running
        if captureState == .recording {
            Self.logger.debug("Already recording, skipping start")
            return
        }

        // Validate audio system configuration
        let configurationValid = diagnostics.validateAudioConfiguration()
        if !configurationValid {
            Self.logger.warning("Audio configuration validation failed, proceeding with caution")
        }

        // Log available audio devices for debugging
        logAvailableAudioDevices()

        updateCaptureState(.starting)

        do {
            Self.logger.debug("Setting up audio engine...")

            // Check if input node is available
            let inputNode = audioEngine.inputNode
            Self.logger.debug("Input node: \(String(describing: inputNode))")
            Self.logger.debug("Input node format: \(String(describing: inputNode.inputFormat(forBus: 0)))")

            try setupAudioEngine()

            Self.logger.debug("Starting audio engine...")
            try audioEngine.start()

            // Verify the engine is actually running
            if audioEngine.isRunning {
                Self.logger.info("Audio engine confirmed running")
                updateCaptureState(.recording)
            } else {
                Self.logger.error("Audio engine failed to start - not running")
                updateCaptureState(.error(.engineNotRunning))
                throw CaptureError.engineNotRunning
            }

            Self.logger.info("Audio capture started successfully")
        } catch {
            Self.logger.error("Failed to start audio capture: \(error.localizedDescription)")
            updateCaptureState(.error(.engineNotRunning))
            throw CaptureError.engineNotRunning
        }
    }
    
    /// Stop audio capture and clean up resources
    ///
    /// Safely stops the audio engine and resets all state variables.
    /// This method is safe to call multiple times and includes enhanced error handling.
    public func stopCapture() {
        Task { @MainActor in
            Self.logger.info("Stopping audio capture...")

            // Check current state before stopping
            let wasRecording = (captureState == .recording)
            captureState = .stopping

            // Stop the audio engine
            if audioEngine.isRunning {
                audioEngine.stop()
                Self.logger.debug("Audio engine stopped successfully")
            } else {
                Self.logger.debug("Audio engine was not running")
            }

            // Remove the input tap safely
            if wasRecording {
                audioEngine.inputNode.removeTap(onBus: 0)
                Self.logger.debug("Input tap removed")
            }

            // Ensure all connections are disconnected to prevent any residual audio routing
            let mainMixerNode = audioEngine.mainMixerNode
            let outputNode = audioEngine.outputNode
            audioEngine.disconnectNodeInput(mainMixerNode)
            audioEngine.disconnectNodeInput(outputNode)

            Self.logger.debug("All audio connections disconnected")

            // Reset state variables
            captureState = .idle
            inputLevel = 0.0
            isVoiceDetected = false

            Self.logger.info("Audio capture stopped successfully")
        }
    }
    
    /// Get available audio input devices
    /// 
    /// - Returns: Array of tuples containing device ID and name
    public func getAvailableInputDevices() -> [(deviceID: AudioDeviceID, name: String)] {
        #if os(macOS)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        guard status == noErr else { return [] }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var audioDevices = Array<AudioDeviceID>(repeating: 0, count: deviceCount)
        
        let getDevicesStatus = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &audioDevices)
        guard getDevicesStatus == noErr else { return [] }
        
        return audioDevices.compactMap { deviceID in
            // Check if device has input streams
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var inputDataSize: UInt32 = 0
            let inputStatus = AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &inputDataSize)
            guard inputStatus == noErr && inputDataSize > 0 else { return nil }
            
            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var nameDataSize: UInt32 = 0
            let nameStatus = AudioObjectGetPropertyDataSize(deviceID, &nameAddress, 0, nil, &nameDataSize)
            guard nameStatus == noErr else { return (deviceID: deviceID, name: "Unknown Device") }
            
            var deviceName: Unmanaged<CFString>?
            let getNameStatus = AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameDataSize, &deviceName)
            
            let name: String
            if getNameStatus == noErr, let unmanagedName = deviceName {
                let cfString = unmanagedName.takeUnretainedValue()
                name = String(cfString)
            } else {
                name = "Audio Device \(deviceID)"
            }
                
            return (deviceID: deviceID, name: name)
        }
        #else
        return AVAudioSession.sharedInstance().availableInputs?.compactMap { input in
            (deviceID: 0, name: input.portName)
        } ?? []
        #endif
    }
    
    /// Set the preferred audio input device
    /// 
    /// - Parameter deviceID: The Core Audio device ID to use, or nil for default
    /// - Throws: `CaptureError.deviceNotAvailable` if the device cannot be set
    public func setPreferredInputDevice(_ deviceID: AudioDeviceID?) throws {
        #if os(macOS)
        // On macOS, device selection is handled differently
        // This would require Core Audio APIs for full implementation
        if let deviceID = deviceID {
            var device = deviceID
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            let result = AudioObjectSetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                0,
                nil,
                UInt32(MemoryLayout<AudioDeviceID>.size),
                &device
            )
            
            if result != noErr {
                throw CaptureError.deviceNotAvailable
            }
        }
        #else
        // iOS implementation would go here
        #endif
    }

    // MARK: - Enhanced Audio System Methods

    /// Run comprehensive audio system diagnostics
    ///
    /// - Returns: Detailed diagnostic report with recommendations
    public func runAudioDiagnostics() async -> AudioDiagnostics.SystemDiagnosticReport {
        return await diagnostics.runCompleteSystemCheck()
    }

    /// Get current audio performance metrics
    ///
    /// - Returns: Current performance metrics
    public func getPerformanceMetrics() -> AudioDiagnostics.PerformanceMetrics {
        return diagnostics.collectPerformanceMetrics()
    }

    /// Get available input devices with enhanced information
    ///
    /// - Returns: Array of detailed device information
    public func getEnhancedInputDevices() -> [AudioDeviceManager.AudioDeviceInfo] {
        return deviceManager.getAvailableInputDevices()
    }

    /// Get recommended device for speech recognition
    ///
    /// - Returns: Best available device for speech recognition
    public func getRecommendedSpeechDevice() -> AudioDeviceManager.AudioDeviceInfo? {
        return deviceManager.getRecommendedSpeechDevice()
    }

    /// Validate device compatibility for speech recognition
    ///
    /// - Parameter deviceID: Device ID to validate
    /// - Returns: True if device is suitable for speech recognition
    public func validateDeviceForSpeechRecognition(_ deviceID: AudioDeviceID) -> Bool {
        return deviceManager.validateDeviceForSpeechRecognition(deviceID)
    }

    /// Set preferred input device with enhanced validation
    ///
    /// - Parameter deviceID: Device ID to set as preferred
    /// - Throws: DeviceError if device cannot be set
    public func setEnhancedPreferredInputDevice(_ deviceID: AudioDeviceID?) throws {
        try deviceManager.setPreferredInputDevice(deviceID)
    }

    /// Get current permission status with enhanced information
    ///
    /// - Returns: Enhanced permission status
    public func getEnhancedPermissionStatus() -> AudioPermissionManager.PermissionStatus {
        return permissionManager.currentPermissionStatus
    }

    /// Validate microphone access
    ///
    /// - Returns: True if microphone can be accessed for recording
    public func validateMicrophoneAccess() async -> Bool {
        return await permissionManager.validateMicrophoneAccess()
    }

    /// Get audio system health status
    ///
    /// - Returns: True if audio system is healthy for speech recognition
    public func isAudioSystemHealthy() -> Bool {
        return diagnostics.validateAudioConfiguration()
    }

    // MARK: - Private Implementation
    
    private func setupNotifications() {
        #if os(macOS)
        // On macOS, monitor for audio configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: audioEngine
        )
        #else
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        #endif
    }
    
    @objc private func handleConfigurationChange(_ notification: Notification) {
        #if os(macOS)
        // Handle audio configuration changes on macOS
        stopCapture()
        #endif
    }
    
    @objc private func handleRouteChange(_ notification: Notification) {
        #if !os(macOS)
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        if reason == .oldDeviceUnavailable {
            stopCapture()
        }
        #endif
    }
    
    @objc private func handleInterruption(_ notification: Notification) {
        #if !os(macOS)
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            stopCapture()
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    Task { @MainActor in
                        do {
                            try await startCapture()
                        } catch {
                            // Handle restart failure
                            updateCaptureState(.error(.engineNotRunning))
                            Self.logger.error("Failed to restart audio capture after interruption: \(error.localizedDescription)")
                        }
                    }
                }
            }
        @unknown default:
            break
        }
        #endif
    }
    
    private func setupBufferOverrunHandling() {
        circularBuffer.onOverrun = { [weak self] droppedSamples in
            Task { @MainActor in
                self?.updateCaptureState(.error(.bufferOverrun))
                Self.logger.error("Audio buffer overrun: \(droppedSamples) samples dropped")
            }
        }
    }

    /// Setup audio system integration with enhanced utilities
    private func setupAudioSystemIntegration() {
        // Start device monitoring
        deviceManager.startMonitoring()

        // Setup device change callbacks
        deviceManager.onDeviceListChanged = { [weak self] devices in
            Task { @MainActor in
                self?.handleDeviceListChange(devices)
            }
        }

        deviceManager.onDefaultDeviceChanged = { [weak self] device in
            Task { @MainActor in
                self?.handleDefaultDeviceChange(device)
            }
        }

        // Setup permission monitoring
        permissionManager.startMonitoring()

        permissionManager.onPermissionStatusChanged = { [weak self] status in
            Task { @MainActor in
                self?.handlePermissionStatusChange(status)
            }
        }

        // Start performance monitoring for diagnostics
        diagnostics.startPerformanceMonitoring()

        Self.logger.info("Audio system integration setup complete")
    }

    /// Handle device list changes
    private func handleDeviceListChange(_ devices: [AudioDeviceManager.AudioDeviceInfo]) {
        Self.logger.info("Audio device list changed: \(devices.count) devices available")

        // If currently recording and default device changed, may need to restart
        if captureState == .recording {
            Self.logger.debug("Device list changed during recording, validating current setup")
            Task {
                await validateCurrentAudioSetupWithRecovery()
            }
        }
    }

    /// Handle default device changes
    private func handleDefaultDeviceChange(_ device: AudioDeviceManager.AudioDeviceInfo?) {
        if let device = device {
            Self.logger.info("Default audio device changed to: \(device.name)")
        } else {
            Self.logger.warning("Default audio device removed")
        }

        // If currently recording, may need to restart with new device
        if captureState == .recording {
            Self.logger.info("Restarting audio capture due to default device change")
            Task {
                do {
                    stopCapture()
                    try await startCapture()
                } catch {
                    Self.logger.error("Failed to restart audio capture after device change: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Handle permission status changes
    private func handlePermissionStatusChange(_ status: AudioPermissionManager.PermissionStatus) {
        Self.logger.info("Audio permission status changed: \(status.description)")

        if !status.allowsCapture && captureState == .recording {
            Self.logger.warning("Permission revoked during recording, stopping capture")
            stopCapture()
            updateCaptureState(.error(.permissionDenied))
        }
    }

    /// Validate current audio setup with recovery actions
    private func validateCurrentAudioSetupWithRecovery() async {
        let isValid = diagnostics.validateAudioConfiguration()
        if !isValid {
            Self.logger.warning("Current audio setup validation failed, running diagnostics")

            // Run comprehensive diagnostics to understand the issue
            let report = await diagnostics.runCompleteSystemCheck()
            Self.logger.error("Audio diagnostic report: \(self.diagnostics.formatDiagnosticReport(report))")

            // Take recovery actions based on health status
            switch report.overallHealth {
            case .critical, .poor:
                Self.logger.error("Critical audio system issues detected, stopping capture")
                updateCaptureState(.error(.formatNotSupported))

                // Update capture state to indicate error
                // Note: Error callbacks would be handled by the UI layer

            case .fair:
                Self.logger.warning("Audio system issues detected, attempting recovery")
                // Attempt to restart audio engine
                if captureState == .recording {
                    Task {
                        stopCapture()
                        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms delay
                        try? await startCapture()
                    }
                }

            case .good, .excellent:
                Self.logger.info("Audio system validation passed after detailed check")
            }
        }
    }



    private func logAvailableAudioDevices() {
        Self.logger.debug("=== Enhanced Audio Device Information ===")

        let devices = deviceManager.getAvailableInputDevices()
        let defaultDevice = deviceManager.defaultInputDevice

        Self.logger.debug("Found \(devices.count) input device(s)")

        if let defaultDevice = defaultDevice {
            Self.logger.debug("Default device: \(defaultDevice.name) (ID: \(defaultDevice.id))")
            Self.logger.debug("  - Manufacturer: \(defaultDevice.manufacturer)")
            Self.logger.debug("  - Sample rates: \(defaultDevice.sampleRates)")
            Self.logger.debug("  - Channels: \(defaultDevice.channelCounts)")
            Self.logger.debug("  - Connected: \(defaultDevice.isConnected)")
            Self.logger.debug("  - Speech compatible: \(self.deviceManager.validateDeviceForSpeechRecognition(defaultDevice.id))")
        } else {
            Self.logger.warning("No default input device found")
        }

        // Log all available devices
        for device in devices {
            let marker = device.isDefault ? "* " : "  "
            Self.logger.debug("\(marker)\(device.name) (ID: \(device.id))")
            Self.logger.debug("    - Manufacturer: \(device.manufacturer)")
            Self.logger.debug("    - Connected: \(device.isConnected)")
            Self.logger.debug("    - Speech compatible: \(self.deviceManager.validateDeviceForSpeechRecognition(device.id))")
        }

        // Log recommended device for speech recognition
        if let recommended = deviceManager.getRecommendedSpeechDevice() {
            Self.logger.debug("Recommended for speech: \(recommended.name)")
        } else {
            Self.logger.warning("No suitable device found for speech recognition")
        }

        Self.logger.debug("=== End Audio Device Information ===")
    }
    
    private func setupAudioEngine() throws {
        guard let format = recordingFormat else {
            Self.logger.error("Recording format not supported")
            throw CaptureError.formatNotSupported
        }

        Self.logger.debug("Setting up audio engine with format: \(String(describing: format))")

        let inputNode = audioEngine.inputNode
        let mainMixerNode = audioEngine.mainMixerNode
        let outputNode = audioEngine.outputNode

        // CRITICAL: Prevent audio feedback by ensuring no input-to-output routing
        Self.logger.debug("Configuring input-only operation to prevent feedback...")

        // 1. Remove any existing connections that could cause feedback
        audioEngine.disconnectNodeInput(mainMixerNode)
        audioEngine.disconnectNodeOutput(inputNode)
        audioEngine.disconnectNodeInput(outputNode)

        // 2. Remove any existing tap first
        inputNode.removeTap(onBus: 0)

        // 3. Ensure output node has no input (prevents any audio from playing)
        // This is crucial to prevent feedback loops
        Self.logger.debug("Ensuring output node is disconnected to prevent feedback")

        // 4. Install tap for input capture only (no output routing)
        Self.logger.debug("Installing audio tap with buffer size 1024")
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Process audio buffer directly without MainActor to avoid delays
            self.processAudioBufferSync(buffer)
        }

        Self.logger.debug("Preparing audio engine...")
        audioEngine.prepare()
        Self.logger.info("Audio engine setup complete - input-only configuration")
    }
    
    private func processAudioBufferSync(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else {
            Self.logger.error("No channel data in buffer")
            return
        }

        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

        // Time-based logging to avoid spam and prevent audio thread blocking
        let now = Date().timeIntervalSinceReferenceDate
        if now - lastLogTime >= logInterval {
            Self.logger.debug("Processing buffer with \(frameCount) samples")
            lastLogTime = now
        }

        // Calculate input level (RMS)
        let rms = calculateRMS(samples)
        let dbLevel = 20 * log10(max(rms, 1e-10))

        // Update UI properties on main thread
        DispatchQueue.main.async { [weak self] in
            self?.updateInputLevel(dbLevel)
        }

        // Voice activity detection
        let voiceDetected = vadDetector.detectVoiceActivity(samples)
        DispatchQueue.main.async { [weak self] in
            self?.updateVoiceActivity(voiceDetected)
        }

        // Add to circular buffer
        circularBuffer.write(samples)

        // Always notify with raw audio data for test recording purposes
        let audioData = samplesToData(samples)
        onRawAudioDataAvailable?(audioData)

        // If voice is detected, notify with audio data
        if voiceDetected {
            onAudioDataAvailable?(audioData)
        }

        // Throttled debug logging for audio levels
        if now - lastLogTime >= logInterval {
            Self.logger.debug("Current level: \(String(format: "%.1f", dbLevel)) dB, voice: \(voiceDetected)")
        }
    }
    
    private func calculateRMS(_ samples: [Float]) -> Float {
        var sum: Float = 0
        vDSP_svesq(samples, 1, &sum, vDSP_Length(samples.count))
        return sqrt(sum / Float(samples.count))
    }
    
    private func samplesToData(_ samples: [Float]) -> Data {
        return Data(bytes: samples, count: samples.count * MemoryLayout<Float>.stride)
    }
    
    private func updateCaptureState(_ newState: CaptureState) {
        captureState = newState
    }
    
    private func updateInputLevel(_ level: Float) {
        inputLevel = level
    }
    
    private func updateVoiceActivity(_ detected: Bool) {
        if isVoiceDetected != detected {
            isVoiceDetected = detected
            onVoiceActivityChanged?(detected)
        }
    }

    /// Provides comprehensive diagnostics about the audio engine state
    ///
    /// Returns detailed information about the current state of the audio capture engine,
    /// including capture state, audio engine status, and configuration details.
    /// Useful for debugging and state validation.
    ///
    /// - Returns: Dictionary containing diagnostic information
    public func getDiagnostics() -> [String: Any] {
        return [
            "captureState": String(describing: self.captureState),
            "audioEngineRunning": self.audioEngine.isRunning,
            "inputLevel": self.inputLevel,
            "isVoiceDetected": self.isVoiceDetected,
            "isCapturing": self.isCapturing,
            "inputFormat": self.audioEngine.inputNode.inputFormat(forBus: 0).description,
            "sampleRate": self.audioEngine.inputNode.inputFormat(forBus: 0).sampleRate,
            "channelCount": self.audioEngine.inputNode.inputFormat(forBus: 0).channelCount,
            "hasCallbacks": [
                "onAudioDataAvailable": self.onAudioDataAvailable != nil,
                "onRawAudioDataAvailable": self.onRawAudioDataAvailable != nil,
                "onVoiceActivityChanged": self.onVoiceActivityChanged != nil
            ]
        ]
    }

    /// Validates the current state of the audio engine
    ///
    /// Checks for consistency between the capture state and actual audio engine state.
    /// Useful for detecting state synchronization issues.
    ///
    /// - Returns: `true` if the state is consistent, `false` otherwise
    public func validateState() -> Bool {
        let stateConsistent = (self.captureState == .recording) == self.audioEngine.isRunning

        if !stateConsistent {
            Self.logger.warning("Audio engine state inconsistency - captureState: \(String(describing: self.captureState)), engineRunning: \(self.audioEngine.isRunning)")
        }

        return stateConsistent
    }
}

// MARK: - Supporting Classes

/// Thread-safe circular buffer for real-time audio data
/// 
/// The `CircularAudioBuffer` provides a fixed-size ring buffer that automatically
/// overwrites old data when capacity is exceeded. This is ideal for real-time
/// audio processing where maintaining low latency is more important than
/// preserving all historical data.
///
/// ## Thread Safety
/// All operations are protected by an internal lock, making it safe to use
/// from multiple threads simultaneously.
///
/// ## Usage
/// ```swift
/// let buffer = CircularAudioBuffer(capacity: 16384)
/// buffer.onOverrun = { droppedSamples in
///     print("Buffer overrun: \(droppedSamples) samples dropped")
/// }
/// 
/// // Writer thread
/// buffer.write([1.0, 2.0, 3.0])
/// 
/// // Reader thread  
/// let samples = buffer.read(1024)
/// ```
public class CircularAudioBuffer {
    private var buffer: [Float]
    private var writeIndex: Int = 0
    private var readIndex: Int = 0
    private let capacity: Int
    private let lock = NSLock()
    
    /// Callback invoked when buffer overrun occurs
    /// - Parameter droppedSamples: Number of samples that were dropped due to overrun
    public var onOverrun: ((Int) -> Void)?
    
    /// Initialize a new circular buffer
    /// - Parameter capacity: Maximum number of samples the buffer can hold
    public init(capacity: Int) {
        self.capacity = capacity
        self.buffer = Array(repeating: 0.0, count: capacity)
    }
    
    /// Write samples to the buffer
    /// 
    /// If the buffer becomes full, old samples will be automatically overwritten.
    /// This operation is thread-safe.
    /// 
    /// - Parameter samples: Array of audio samples to write
    public func write(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        
        var droppedSamples = 0
        
        for sample in samples {
            buffer[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
            
            // Handle buffer overrun
            if writeIndex == readIndex {
                readIndex = (readIndex + 1) % capacity
                droppedSamples += 1
            }
        }
        
        // Report overrun if any samples were dropped
        if droppedSamples > 0 {
            onOverrun?(droppedSamples)
        }
    }
    
    /// Read samples from the buffer
    /// 
    /// Reads up to the specified number of samples from the buffer.
    /// If fewer samples are available, only the available samples are returned.
    /// This operation is thread-safe.
    /// 
    /// - Parameter count: Maximum number of samples to read
    /// - Returns: Array of audio samples (may be fewer than requested)
    public func read(_ count: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        
        var result: [Float] = []
        result.reserveCapacity(count)
        
        for _ in 0..<min(count, availableDataCount()) {
            result.append(buffer[readIndex])
            readIndex = (readIndex + 1) % capacity
        }
        
        return result
    }
    
    /// Get the number of samples currently available for reading
    /// - Returns: Number of samples that can be read without blocking
    public func availableDataCount() -> Int {
        if writeIndex >= readIndex {
            return writeIndex - readIndex
        } else {
            return capacity - readIndex + writeIndex
        }
    }
    
    /// Clear all data from the buffer
    /// 
    /// Resets both read and write indices, effectively clearing all stored data.
    /// This operation is thread-safe.
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        writeIndex = 0
        readIndex = 0
    }
}

/// Voice Activity Detection (VAD) using threshold-based analysis with smoothing
/// 
/// The `VoiceActivityDetector` analyzes audio samples to determine if voice activity
/// is present. It uses RMS (Root Mean Square) calculation to measure signal energy
/// and applies smoothing to reduce false triggers from noise.
///
/// ## Algorithm
/// 1. Calculate RMS energy of input samples
/// 2. Convert to decibel scale
/// 3. Apply exponential smoothing to reduce noise sensitivity
/// 4. Compare against threshold to determine voice activity
///
/// ## Usage
/// ```swift
/// let vad = VoiceActivityDetector(threshold: -40.0)
/// let isVoice = vad.detectVoiceActivity(audioSamples)
/// ```
public class VoiceActivityDetector {
    private let threshold: Float
    private var smoothedLevel: Float = -80.0
    private let smoothingFactor: Float = 0.1
    
    /// Initialize voice activity detector
    /// - Parameter threshold: Voice detection threshold in decibels (typically -40 to -20 dB)
    public init(threshold: Float) {
        self.threshold = threshold
    }
    
    /// Analyze audio samples for voice activity
    /// 
    /// Calculates the RMS energy of the samples, applies smoothing, and compares
    /// against the configured threshold to determine if voice is present.
    /// 
    /// - Parameter samples: Array of audio samples to analyze
    /// - Returns: True if voice activity is detected, false otherwise
    public func detectVoiceActivity(_ samples: [Float]) -> Bool {
        let rms = calculateRMS(samples)
        let dbLevel = 20 * log10(max(rms, 1e-10))
        
        // Smooth the level to reduce noise
        smoothedLevel = smoothedLevel * (1 - smoothingFactor) + dbLevel * smoothingFactor
        
        return smoothedLevel > threshold
    }
    
    private func calculateRMS(_ samples: [Float]) -> Float {
        var sum: Float = 0
        vDSP_svesq(samples, 1, &sum, vDSP_Length(samples.count))
        return sqrt(sum / Float(samples.count))
    }

}