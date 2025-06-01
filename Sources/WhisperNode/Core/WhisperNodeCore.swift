import Foundation
import os.log

public class WhisperNodeCore: ObservableObject {
    private static let logger = Logger(subsystem: "com.whispernode.core", category: "initialization")
    
    // Core managers
    @Published public private(set) var hotkeyManager = GlobalHotkeyManager()
    
    // Application state
    @Published public private(set) var isInitialized = false
    @Published public private(set) var isRecording = false
    
    public static let shared = WhisperNodeCore()
    
    private init() {
        initialize()
    }
    
    private func initialize() {
        Self.logger.info("WhisperNode Core initializing...")
        
        // Setup hotkey manager delegate
        hotkeyManager.delegate = self
        
        isInitialized = true
        Self.logger.info("WhisperNode Core initialized successfully")
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
}

// MARK: - GlobalHotkeyManagerDelegate

extension WhisperNodeCore: GlobalHotkeyManagerDelegate {
    public func hotkeyManager(_ manager: GlobalHotkeyManager, didStartListening: Bool) {
        Self.logger.info("Hotkey listening status changed: \(didStartListening)")
    }
    
    public func hotkeyManager(_ manager: GlobalHotkeyManager, didStartRecording: Bool) {
        isRecording = true
        Self.logger.info("Voice recording started")
        // TODO: Start audio capture (T04)
    }
    
    public func hotkeyManager(_ manager: GlobalHotkeyManager, didCompleteRecording duration: CFTimeInterval) {
        isRecording = false
        Self.logger.info("Voice recording completed after \(duration)s")
        // TODO: Process audio and transcribe (T06)
    }
    
    public func hotkeyManager(_ manager: GlobalHotkeyManager, didCancelRecording reason: RecordingCancelReason) {
        isRecording = false
        Self.logger.info("Voice recording cancelled")
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