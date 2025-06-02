import AVFoundation
import Accelerate
import Foundation
#if os(macOS)
import CoreAudio
#endif

@MainActor
public class AudioCaptureEngine: ObservableObject {
    
    public enum CaptureError: Error, LocalizedError, Equatable {
        case engineNotRunning
        case permissionDenied
        case deviceNotAvailable
        case formatNotSupported
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
    
    public enum CaptureState: Equatable {
        case idle
        case starting
        case recording
        case stopping
        case error(CaptureError)
    }
    
    public enum PermissionStatus {
        case granted
        case denied
        case undetermined
    }
    
    private let audioEngine = AVAudioEngine()
    private let circularBuffer: CircularAudioBuffer
    private let vadDetector: VoiceActivityDetector
    
    @Published public private(set) var captureState: CaptureState = .idle
    @Published public private(set) var inputLevel: Float = 0.0
    @Published public private(set) var isVoiceDetected: Bool = false
    
    public var onAudioDataAvailable: ((Data) -> Void)?
    public var onVoiceActivityChanged: ((Bool) -> Void)?
    
    private var recordingFormat: AVAudioFormat? {
        return AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)
    }
    
    public init() {
        self.circularBuffer = CircularAudioBuffer(capacity: 16384) // 1 second at 16kHz
        self.vadDetector = VoiceActivityDetector(threshold: -40.0)
        
        setupNotifications()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        // Note: Cannot call async methods in deinit
        // Audio engine will be cleaned up automatically
    }
    
    // MARK: - Public Interface
    
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
    
    public func getAvailableInputDevices() -> [AVAudioUnit] {
        #if os(macOS)
        // On macOS, use AVAudioEngine to get available input devices
        return [] // Simplified for now - would need AudioObjectGetPropertyData for full implementation
        #else
        return AVAudioSession.sharedInstance().availableInputs?.compactMap { _ in AVAudioUnit() } ?? []
        #endif
    }
    
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

public class CircularAudioBuffer {
    private var buffer: [Float]
    private var writeIndex: Int = 0
    private var readIndex: Int = 0
    private let capacity: Int
    private let lock = NSLock()
    
    public init(capacity: Int) {
        self.capacity = capacity
        self.buffer = Array(repeating: 0.0, count: capacity)
    }
    
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
    
    public func availableDataCount() -> Int {
        if writeIndex >= readIndex {
            return writeIndex - readIndex
        } else {
            return capacity - readIndex + writeIndex
        }
    }
    
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        writeIndex = 0
        readIndex = 0
    }
}

public class VoiceActivityDetector {
    private let threshold: Float
    private var smoothedLevel: Float = -80.0
    private let smoothingFactor: Float = 0.1
    
    public init(threshold: Float) {
        self.threshold = threshold
    }
    
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