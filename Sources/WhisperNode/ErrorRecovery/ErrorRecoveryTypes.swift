import Foundation

// MARK: - App Components

/// Application components that can experience errors and require recovery
public enum AppComponent: String, CaseIterable, Codable {
    case hotkeySystem = "hotkey_system"
    case audioSystem = "audio_system"
    case whisperEngine = "whisper_engine"
    case textInsertion = "text_insertion"
    case systemResources = "system_resources"
    
    public var displayName: String {
        switch self {
        case .hotkeySystem:
            return "Hotkey System"
        case .audioSystem:
            return "Audio System"
        case .whisperEngine:
            return "Whisper Engine"
        case .textInsertion:
            return "Text Insertion"
        case .systemResources:
            return "System Resources"
        }
    }
    
    public var description: String {
        switch self {
        case .hotkeySystem:
            return "Global hotkey detection and handling"
        case .audioSystem:
            return "Audio capture and processing"
        case .whisperEngine:
            return "Speech-to-text transcription"
        case .textInsertion:
            return "Text insertion into target applications"
        case .systemResources:
            return "System resource monitoring and management"
        }
    }
}

// MARK: - App Errors

/// Application errors that can occur and potentially be recovered from
public enum AppError: Equatable, Codable, Hashable {
    case permissionDenied
    case audioDeviceUnavailable
    case audioCaptureFailure(String)
    case transcriptionFailed
    case modelLoadFailed(String)
    case textInsertionFailed
    case hotkeyConflict(String)
    case hotkeySystemError(String)
    case networkConnectionFailed
    case systemResourcesExhausted
    case componentFailure(String)
    
    public var displayName: String {
        switch self {
        case .permissionDenied:
            return "Permission Denied"
        case .audioDeviceUnavailable:
            return "Audio Device Unavailable"
        case .audioCaptureFailure:
            return "Audio Capture Failure"
        case .transcriptionFailed:
            return "Transcription Failed"
        case .modelLoadFailed:
            return "Model Load Failed"
        case .textInsertionFailed:
            return "Text Insertion Failed"
        case .hotkeyConflict:
            return "Hotkey Conflict"
        case .hotkeySystemError:
            return "Hotkey System Error"
        case .networkConnectionFailed:
            return "Network Connection Failed"
        case .systemResourcesExhausted:
            return "System Resources Exhausted"
        case .componentFailure:
            return "Component Failure"
        }
    }
    
    public var isRecoverable: Bool {
        switch self {
        case .audioDeviceUnavailable, .audioCaptureFailure, .transcriptionFailed, .modelLoadFailed, .textInsertionFailed, .hotkeySystemError, .networkConnectionFailed, .componentFailure:
            return true
        case .permissionDenied, .hotkeyConflict, .systemResourcesExhausted:
            return false
        }
    }
    
    public var severity: ErrorSeverity {
        switch self {
        case .permissionDenied, .systemResourcesExhausted:
            return .critical
        case .audioDeviceUnavailable, .modelLoadFailed, .hotkeyConflict, .hotkeySystemError, .componentFailure:
            return .warning
        case .audioCaptureFailure, .transcriptionFailed, .textInsertionFailed, .networkConnectionFailed:
            return .minor
        }
    }
}

public enum ErrorSeverity: String, Codable {
    case minor
    case warning
    case critical
    
    public var displayName: String {
        switch self {
        case .minor:
            return "Minor"
        case .warning:
            return "Warning"
        case .critical:
            return "Critical"
        }
    }
}

// MARK: - Error Records

/// Record of an error occurrence for diagnostic tracking
public struct ErrorRecord: Identifiable, Codable {
    public let id = UUID()
    public let error: AppError
    public let component: AppComponent
    public let timestamp: Date
    public let context: [String: String] // Simplified for Codable
    public var resolved: Bool
    public var resolvedAt: Date?
    
    public init(error: AppError, component: AppComponent, timestamp: Date, context: [String: Any] = [:], resolved: Bool = false) {
        self.error = error
        self.component = component
        self.timestamp = timestamp
        self.context = context.compactMapValues { "\($0)" } // Convert to String for Codable
        self.resolved = resolved
    }
    
    public var displayDescription: String {
        let status = resolved ? "✅ Resolved" : "❌ Active"
        return "\(component.displayName): \(error.displayName) - \(status)"
    }
}

// MARK: - Error Guidance

/// User-friendly error guidance provider
public class ErrorGuidanceProvider {
    public static let shared = ErrorGuidanceProvider()
    
    private init() {}
    
    public func getGuidance(for error: AppError, component: AppComponent) -> ErrorGuidance {
        switch (error, component) {
        case (.permissionDenied, .audioSystem):
            return ErrorGuidance(
                title: "Microphone Permission Required",
                message: "WhisperNode needs access to your microphone to capture audio for transcription.",
                actions: [
                    ErrorAction(title: "Open System Preferences", type: .openSystemPreferences),
                    ErrorAction(title: "Try Again", type: .retry)
                ],
                helpUrl: "https://support.apple.com/guide/mac-help/control-access-to-your-microphone-on-mac-mchla1b1e1fe/mac"
            )
            
        case (.permissionDenied, .textInsertion):
            return ErrorGuidance(
                title: "Accessibility Permission Required",
                message: "WhisperNode needs accessibility permissions to insert text into other applications.",
                actions: [
                    ErrorAction(title: "Open Accessibility Settings", type: .openAccessibilitySettings),
                    ErrorAction(title: "Try Again", type: .retry)
                ],
                helpUrl: "https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac"
            )
            
        case (.audioDeviceUnavailable, .audioSystem):
            return ErrorGuidance(
                title: "Audio Device Not Available",
                message: "No audio input device is available. Please check your microphone connection.",
                actions: [
                    ErrorAction(title: "Check Audio Settings", type: .openAudioSettings),
                    ErrorAction(title: "Retry", type: .retry)
                ],
                helpUrl: nil
            )
            
        case (.transcriptionFailed, .whisperEngine):
            return ErrorGuidance(
                title: "Transcription Failed",
                message: "The speech recognition failed. This might be due to unclear audio or system load.",
                actions: [
                    ErrorAction(title: "Try Again", type: .retry),
                    ErrorAction(title: "Check Audio Quality", type: .checkAudioQuality)
                ],
                helpUrl: nil
            )
            
        default:
            return ErrorGuidance(
                title: "Something Went Wrong",
                message: "WhisperNode encountered an issue. You can try restarting the affected component.",
                actions: [
                    ErrorAction(title: "Restart Component", type: .restartComponent),
                    ErrorAction(title: "Contact Support", type: .contactSupport)
                ],
                helpUrl: nil
            )
        }
    }
}

public struct ErrorGuidance {
    public let title: String
    public let message: String
    public let actions: [ErrorAction]
    public let helpUrl: String?
}

public struct ErrorAction {
    public let title: String
    public let type: ErrorActionType
}

public enum ErrorActionType {
    case retry
    case openSystemPreferences
    case openAccessibilitySettings
    case openAudioSettings
    case checkAudioQuality
    case restartComponent
    case contactSupport
}

// MARK: - Error Analysis

/// Error analysis and statistics
public struct ErrorAnalysis {
    public let totalErrors: Int
    public let resolvedErrors: Int
    public let errorsByComponent: [AppComponent: Int]
    public let errorsByType: [AppError: Int]
    public let mostProblematicComponent: AppComponent?
    public let mostCommonError: AppError?
    public let errorTrends: [String]
    
    public var resolutionRate: Double {
        guard totalErrors > 0 else { return 0.0 }
        return Double(resolvedErrors) / Double(totalErrors)
    }
}

// MARK: - Extensions

extension AppError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Permission denied for required system access"
        case .audioDeviceUnavailable:
            return "Audio input device is not available"
        case .audioCaptureFailure(let details):
            return "Audio capture failed: \(details)"
        case .transcriptionFailed:
            return "Speech transcription failed"
        case .modelLoadFailed(let details):
            return "Failed to load transcription model: \(details)"
        case .textInsertionFailed:
            return "Failed to insert text into target application"
        case .hotkeyConflict(let details):
            return "Hotkey conflict detected: \(details)"
        case .hotkeySystemError(let details):
            return "Hotkey system error: \(details)"
        case .networkConnectionFailed:
            return "Network connection failed"
        case .systemResourcesExhausted:
            return "System resources are exhausted"
        case .componentFailure(let component):
            return "Component failure: \(component)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "Grant the required permissions in System Preferences"
        case .audioDeviceUnavailable:
            return "Check your microphone connection and audio settings"
        case .audioCaptureFailure:
            return "Restart the audio system or check device settings"
        case .transcriptionFailed:
            return "Try speaking more clearly or check audio quality"
        case .modelLoadFailed:
            return "Restart the application or re-download the model"
        case .textInsertionFailed:
            return "Check accessibility permissions and target application"
        case .hotkeyConflict:
            return "Choose a different hotkey combination"
        case .hotkeySystemError:
            return "Restart the hotkey system"
        case .networkConnectionFailed:
            return "Check your internet connection"
        case .systemResourcesExhausted:
            return "Close other applications to free up resources"
        case .componentFailure:
            return "Restart the affected component"
        }
    }
}
