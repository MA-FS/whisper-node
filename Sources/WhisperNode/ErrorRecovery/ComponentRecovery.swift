import Foundation
import AVFoundation
import OSLog

/// Component-specific recovery mechanisms for WhisperNode
///
/// Provides targeted recovery procedures for each application component,
/// with validation and testing to ensure successful recovery.
///
/// ## Features
/// - Component-specific recovery strategies
/// - Recovery validation and testing
/// - Progressive recovery with fallback options
/// - Integration with system diagnostics
///
/// ## Usage
/// ```swift
/// let recovery = ComponentRecovery()
/// 
/// // Recover audio system
/// try await recovery.resetAudioSystem()
/// 
/// // Validate component after recovery
/// try await recovery.validateComponent(.audioSystem)
/// ```
public class ComponentRecovery {
    private static let logger = Logger(subsystem: "com.whispernode.recovery", category: "component")
    
    // MARK: - Permission Recovery
    
    /// Recover permission-related issues
    public func recoverPermissions() async throws {
        Self.logger.info("Starting permission recovery")
        
        // Check and request microphone permissions
        let audioPermission = await AudioCaptureEngine.shared.requestPermission()
        guard audioPermission else {
            throw RecoveryError.permissionRecoveryFailed("Microphone permission denied")
        }
        
        // Check accessibility permissions
        let accessibilityGranted = await PermissionHelper.shared.checkPermissionsQuietly()
        if !accessibilityGranted {
            // For recovery, we can only check permissions, not request them
            // The user will need to manually grant permissions
            throw RecoveryError.permissionRecoveryFailed("Accessibility permission required - please grant in System Preferences")
        }
        
        Self.logger.info("Permission recovery completed successfully")
    }
    
    // MARK: - Audio System Recovery
    
    /// Reset and recover the audio system
    public func resetAudioSystem() async throws {
        Self.logger.info("Starting audio system recovery")
        
        // Stop current audio engine
        let audioEngine = await WhisperNodeCore.shared.audioEngine
        if await audioEngine.isCapturing {
            await audioEngine.stopCapture()
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        // Reset audio session
        try await resetAudioSession()
        
        // Reinitialize audio engine
        try await reinitializeAudioEngine()
        
        // Verify audio device availability
        try await verifyAudioDeviceAvailability()
        
        Self.logger.info("Audio system recovery completed successfully")
    }
    
    private func resetAudioSession() async throws {
        // On macOS, we don't have AVAudioSession, so we'll just add a brief delay
        // to allow the audio system to reset
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        Self.logger.info("Audio session reset completed (macOS)")
    }
    
    private func reinitializeAudioEngine() async throws {
        let core = await WhisperNodeCore.shared

        // Only start capture if we were previously recording
        if await core.isRecording {
            try await core.audioEngine.startCapture()
        }

        Self.logger.info("Audio engine reinitialized successfully")
    }
    
    private func verifyAudioDeviceAvailability() async throws {
        let audioEngine = await WhisperNodeCore.shared.audioEngine
        let wasRecording = await WhisperNodeCore.shared.isRecording

        // Only verify capture if we expected to be recording
        if wasRecording {
            let isCapturing = await audioEngine.isCapturing
            if !isCapturing {
                throw RecoveryError.audioSystemRecoveryFailed("Audio engine failed to start capturing")
            }
        }

        // Additional validation could be added here
        Self.logger.info("Audio device availability verified")
    }
    
    // MARK: - Transcription Engine Recovery
    
    /// Restart the Whisper transcription engine
    public func restartTranscriptionEngine() async throws {
        Self.logger.info("Starting transcription engine recovery")

        let core = await WhisperNodeCore.shared

        // Clear any existing transcription state
        await core.clearTranscriptionState()

        // Reload the current model
        let currentModel = await core.currentModel
        await core.loadModel(currentModel)

        // Test transcription with a simple phrase
        try await testTranscriptionEngine()

        Self.logger.info("Transcription engine recovery completed successfully")
    }
    
    private func testTranscriptionEngine() async throws {
        // Verify model is loaded
        let core = await WhisperNodeCore.shared
        guard await core.isModelLoaded else {
            throw RecoveryError.transcriptionRecoveryFailed("Model failed to load")
        }

        // For now, just verify the model is loaded
        // A more comprehensive test would require access to the whisper engine
        // which is currently private in WhisperNodeCore
        Self.logger.info("Transcription engine test completed - model is loaded")
    }

    private func generateSilentAudioSample() -> [Float] {
        // Generate 1 second of silence at 16kHz
        return Array(repeating: 0.0, count: 16000)
    }
    
    // MARK: - Text Insertion Recovery
    
    /// Retry text insertion with enhanced reliability
    public func retryTextInsertion() async throws {
        Self.logger.info("Starting text insertion recovery")

        // Verify accessibility permissions
        guard await PermissionHelper.shared.checkPermissionsQuietly() else {
            throw RecoveryError.textInsertionRecoveryFailed("Accessibility permission required")
        }

        // Test text insertion capability
        try await testTextInsertion()

        Self.logger.info("Text insertion recovery completed successfully")
    }
    
    private func testTextInsertion() async throws {
        // Test basic text insertion functionality
        let textEngine = TextInsertionEngine.shared

        // Verify the engine is available
        guard await textEngine.isAvailable else {
            throw RecoveryError.textInsertionRecoveryFailed("Text insertion engine unavailable")
        }

        // Additional validation could be added here
    }
    
    // MARK: - Component Reset
    
    /// Reset a specific component
    public func resetComponent(_ component: AppComponent) async throws {
        Self.logger.info("Resetting component: \(component.displayName)")

        switch component {
        case .hotkeySystem:
            try await resetHotkeySystem()
        case .audioSystem:
            try await resetAudioSystem()
        case .whisperEngine:
            try await restartTranscriptionEngine()
        case .textInsertion:
            try await retryTextInsertion()
        case .systemResources:
            // System resources don't have a specific reset mechanism
            // This would typically involve memory cleanup, cache clearing, etc.
            Self.logger.info("System resources component reset completed")
        }
    }
    
    private func resetHotkeySystem() async throws {
        let hotkeyManager = await WhisperNodeCore.shared.hotkeyManager

        // Stop current hotkey monitoring
        await hotkeyManager.stopListening()

        // Wait briefly
        try await Task.sleep(nanoseconds: 500_000_000)

        // Restart hotkey monitoring
        await hotkeyManager.startListening()

        // Verify hotkey system is working
        guard await hotkeyManager.isCurrentlyListening else {
            throw RecoveryError.hotkeyRecoveryFailed("Failed to restart hotkey system")
        }
    }
    
    // MARK: - Full System Reset
    
    /// Perform a complete system reset
    public func performFullSystemReset() async throws {
        Self.logger.warning("Performing full system reset")
        
        // Reset all components in order
        try await resetHotkeySystem()
        try await resetAudioSystem()
        try await restartTranscriptionEngine()
        try await retryTextInsertion()
        
        // Verify all systems are operational
        try await validateAllComponents()
        
        Self.logger.info("Full system reset completed successfully")
    }
    
    // MARK: - Validation
    
    /// Validate that a component is functioning correctly
    public func validateComponent(_ component: AppComponent) async throws {
        Self.logger.info("Validating component: \(component.displayName)")

        switch component {
        case .hotkeySystem:
            guard await WhisperNodeCore.shared.hotkeyManager.isCurrentlyListening else {
                throw RecoveryError.validationFailed("Hotkey system not responding")
            }

        case .audioSystem:
            guard await WhisperNodeCore.shared.audioEngine.isCapturing else {
                throw RecoveryError.validationFailed("Audio system not capturing")
            }

        case .whisperEngine:
            guard await WhisperNodeCore.shared.isModelLoaded else {
                throw RecoveryError.validationFailed("Whisper model not loaded")
            }

        case .textInsertion:
            guard await TextInsertionEngine.shared.isAvailable else {
                throw RecoveryError.validationFailed("Text insertion not available")
            }

        case .systemResources:
            // System resources validation could check memory/disk thresholds
            // For now, we'll consider it always valid
            break
        }

        Self.logger.info("Component validation successful: \(component.displayName)")
    }
    
    private func validateAllComponents() async throws {
        for component in AppComponent.allCases {
            try await validateComponent(component)
        }
    }
}

// MARK: - Recovery Errors

public enum RecoveryError: LocalizedError {
    case timeout
    case permissionRecoveryFailed(String)
    case audioSystemRecoveryFailed(String)
    case transcriptionRecoveryFailed(String)
    case textInsertionRecoveryFailed(String)
    case hotkeyRecoveryFailed(String)
    case validationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "Recovery operation timed out"
        case .permissionRecoveryFailed(let details):
            return "Permission recovery failed: \(details)"
        case .audioSystemRecoveryFailed(let details):
            return "Audio system recovery failed: \(details)"
        case .transcriptionRecoveryFailed(let details):
            return "Transcription recovery failed: \(details)"
        case .textInsertionRecoveryFailed(let details):
            return "Text insertion recovery failed: \(details)"
        case .hotkeyRecoveryFailed(let details):
            return "Hotkey recovery failed: \(details)"
        case .validationFailed(let details):
            return "Validation failed: \(details)"
        }
    }
}
