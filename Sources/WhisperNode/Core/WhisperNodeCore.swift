import Foundation
import os.log

/// Central coordination class for Whisper Node core functionality
/// 
/// Manages the integration between audio capture, model inference, and text insertion
/// with comprehensive performance monitoring and memory management.
@MainActor
public class WhisperNodeCore: ObservableObject {
    private static let logger = Logger(subsystem: "com.whispernode.core", category: "initialization")
    
    // Core managers
    @Published public private(set) var hotkeyManager = GlobalHotkeyManager()
    @Published public private(set) var audioEngine = AudioCaptureEngine()
    
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
        performanceTimer = Timer.scheduledTimer(withTimeInterval: performanceUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updatePerformanceMetrics()
            }
        }
    }
    
    // MARK: - Public Methods
    
    public func startVoiceActivation() {
        hotkeyManager.startListening()
    }
    
    public func stopVoiceActivation() {
        hotkeyManager.stopListening()
    }
    
    public func updateHotkey(_ configuration: HotkeyConfiguration) {
        hotkeyManager.updateHotkey(configuration)
    }
    
    /// Load a whisper model for transcription
    /// - Parameter modelName: Name of the model (tiny.en, small.en, medium.en)
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
            }
        }
    }
    
    /// Switch to a different model (requires app restart for full memory cleanup)
    /// - Parameter modelName: Name of the new model
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
    public func getPerformanceMetrics() -> (memory: UInt64, cpu: Float, modelDowngradeNeeded: Bool) {
        return (memoryUsage, averageCpuUsage, checkModelDowngradeNeeded())
    }
    
    /// Force memory cleanup
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
        // In production, this would check bundle resources first, then downloads folder
        // For now, return a placeholder path
        return "/tmp/\(modelName).bin"
    }
    
    private func processAudioData(_ audioData: Data) async {
        guard let engine = whisperEngine else { return }
        
        // Convert Data to Float array for whisper processing
        let audioSamples = audioData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
        
        // Perform transcription
        let result = await engine.transcribe(audioData: audioSamples)
        
        if result.success {
            Self.logger.info("Transcription completed: \(result.text)")
            // TODO: Insert text using text insertion engine (T07)
            
            // Check for performance warnings
            if let metrics = result.metrics, metrics.isDowngradeNeeded {
                Self.logger.warning("High CPU usage detected, model downgrade recommended")
            }
        } else {
            Self.logger.error("Transcription failed: \(result.error ?? "Unknown error")")
        }
    }
    
    private func handleVoiceActivityChange(_ isVoiceDetected: Bool) {
        Self.logger.debug("Voice activity changed: \(isVoiceDetected)")
        // TODO: Update visual indicator (T05)
    }
    
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
    
    private func checkModelDowngradeNeeded() -> Bool {
        guard let engine = whisperEngine else { return false }
        
        Task {
            let (needed, _) = await engine.shouldDowngradeModel()
            return needed
        }
        
        return false // Synchronous fallback
    }
}

// MARK: - GlobalHotkeyManagerDelegate

extension WhisperNodeCore: GlobalHotkeyManagerDelegate {
    public func hotkeyManager(_ manager: GlobalHotkeyManager, didStartListening isListening: Bool) {
        Self.logger.info("Hotkey listening status changed: \(isListening)")
    }
    
    public func hotkeyManager(_ manager: GlobalHotkeyManager, didStartRecording isRecording: Bool) {
        self.isRecording = true
        Self.logger.info("Voice recording started")
        
        // Start audio capture engine
        Task {
            do {
                try await audioEngine.startCapture()
                Self.logger.info("Audio capture started successfully")
            } catch {
                Self.logger.error("Failed to start audio capture: \(error.localizedDescription)")
                self.isRecording = false
            }
        }
    }
    
    public func hotkeyManager(_ manager: GlobalHotkeyManager, didCompleteRecording duration: CFTimeInterval) {
        isRecording = false
        Self.logger.info("Voice recording completed after \(duration)s")
        
        // Stop audio capture
        audioEngine.stopCapture()
        Self.logger.info("Audio capture stopped")
        
        // The audio processing will be handled by the audioEngine callbacks
        // which will trigger processAudioData() automatically
    }
    
    public func hotkeyManager(_ manager: GlobalHotkeyManager, didCancelRecording reason: RecordingCancelReason) {
        isRecording = false
        Self.logger.info("Voice recording cancelled")
        
        // Stop audio capture
        audioEngine.stopCapture()
    }
    
    public func hotkeyManager(_ manager: GlobalHotkeyManager, didFailWithError error: HotkeyError) {
        Self.logger.error("Hotkey manager error: \(error.localizedDescription)")
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