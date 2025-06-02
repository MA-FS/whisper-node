import AVFoundation
import Accelerate
import Foundation
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
    
    /// Callback invoked when audio data is available (only when voice is detected)
    /// - Parameter data: Raw audio data as Float samples converted to Data
    public var onAudioDataAvailable: ((Data) -> Void)?
    
    /// Callback invoked when voice activity status changes
    /// - Parameter detected: True if voice activity is detected, false otherwise
    public var onVoiceActivityChanged: ((Bool) -> Void)?
    
    private var recordingFormat: AVAudioFormat? {
        return AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)
    }
    
    /// Initialize the audio capture engine
    /// - Parameters:
    ///   - bufferDuration: Duration of the circular buffer in seconds (default: 1.0 second)
    ///   - vadThreshold: Voice activity detection threshold in decibels (default: -40.0 dB)
    public init(bufferDuration: TimeInterval = 1.0, vadThreshold: Float = -40.0) {
        let sampleRate = 16000.0 // 16kHz mono
        let capacity = Int(sampleRate * bufferDuration)
        self.circularBuffer = CircularAudioBuffer(capacity: capacity)
        self.vadDetector = VoiceActivityDetector(threshold: vadThreshold)
        
        setupNotifications()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        // Note: Cannot call async methods in deinit
        // Audio engine will be cleaned up automatically
    }
    
    // MARK: - Public Interface
    
    /// Request microphone permission from the user
    /// 
    /// This method handles platform-specific permission requests. On macOS,
    /// permission is typically checked during audio engine initialization.
    /// 
    /// - Returns: True if permission is granted, false otherwise
    public func requestPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            #if os(macOS)
            // On macOS, check system preferences privacy settings
            let status = checkPermissionStatus()
            continuation.resume(returning: status == .granted)
            #else
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    continuation.resume(returning: granted)
                }
            }
            #endif
        }
    }
    
    /// Check the current microphone permission status
    /// 
    /// - Returns: Current permission status without prompting the user
    public func checkPermissionStatus() -> PermissionStatus {
        #if os(macOS)
        // On macOS, we need to attempt to access the microphone to check permissions
        // This is a simplified check - in practice, the engine will fail if permission is denied
        return .granted // Assume granted for now, real check happens during engine start
        #else
        let status = AVAudioSession.sharedInstance().recordPermission
        switch status {
        case .granted: return .granted
        case .denied: return .denied
        case .undetermined: return .undetermined
        @unknown default: return .undetermined
        }
        #endif
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
        guard checkPermissionStatus() == .granted else {
            updateCaptureState(.error(.permissionDenied))
            throw CaptureError.permissionDenied
        }
        
        updateCaptureState(.starting)
        
        do {
            try setupAudioEngine()
            try audioEngine.start()
            updateCaptureState(.recording)
        } catch {
            updateCaptureState(.error(.engineNotRunning))
            throw CaptureError.engineNotRunning
        }
    }
    
    /// Stop audio capture and clean up resources
    /// 
    /// Safely stops the audio engine and resets all state variables.
    /// This method is safe to call multiple times.
    public func stopCapture() {
        Task { @MainActor in
            captureState = .stopping
            
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            
            captureState = .idle
            inputLevel = 0.0
            isVoiceDetected = false
        }
    }
    
    /// Get available audio input devices
    /// 
    /// - Returns: Array of available input devices (simplified implementation)
    /// - Note: Full device enumeration would require additional Core Audio APIs
    public func getAvailableInputDevices() -> [AVAudioUnit] {
        #if os(macOS)
        // On macOS, use AVAudioEngine to get available input devices
        return [] // Simplified for now - would need AudioObjectGetPropertyData for full implementation
        #else
        return AVAudioSession.sharedInstance().availableInputs?.compactMap { _ in AVAudioUnit() } ?? []
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
                    Task {
                        try? await startCapture()
                    }
                }
            }
        @unknown default:
            break
        }
        #endif
    }
    
    private func setupAudioEngine() throws {
        guard let format = recordingFormat else {
            throw CaptureError.formatNotSupported
        }
        
        let inputNode = audioEngine.inputNode
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                await self.processAudioBuffer(buffer)
            }
        }
        
        audioEngine.prepare()
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        
        // Calculate input level (RMS)
        let rms = calculateRMS(samples)
        let dbLevel = 20 * log10(max(rms, 1e-10))
        
        updateInputLevel(dbLevel)
        
        // Voice activity detection
        let voiceDetected = vadDetector.detectVoiceActivity(samples)
        updateVoiceActivity(voiceDetected)
        
        // Add to circular buffer
        circularBuffer.write(samples)
        
        // If voice is detected, notify with audio data
        if voiceDetected {
            let audioData = samplesToData(samples)
            onAudioDataAvailable?(audioData)
        }
    }
    
    private func calculateRMS(_ samples: [Float]) -> Float {
        var sum: Float = 0
        vDSP_svesq(samples, 1, &sum, vDSP_Length(samples.count))
        return sqrt(sum / Float(samples.count))
    }
    
    private func samplesToData(_ samples: [Float]) -> Data {
        return samples.withUnsafeBytes { bytes in
            Data(bytes.bindMemory(to: UInt8.self))
        }
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
        
        for sample in samples {
            buffer[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
            
            // Handle buffer overrun
            if writeIndex == readIndex {
                readIndex = (readIndex + 1) % capacity
            }
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