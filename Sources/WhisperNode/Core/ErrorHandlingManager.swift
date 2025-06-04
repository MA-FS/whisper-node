import Foundation
import AppKit
import UserNotifications
import os.log

/// Protocol for recording indicator management to enable dependency injection
protocol RecordingIndicatorWindowManagerProtocol {
    func showError()
    func hideIndicator()
}

/// Centralized error handling and recovery system for WhisperNode
///
/// Provides comprehensive error management with user-friendly messaging, 
/// automatic recovery mechanisms, and graceful degradation for all error states.
///
/// ## Features
/// - Non-intrusive error reporting through multiple channels
/// - Automatic recovery where possible
/// - Clear user guidance for manual fixes
/// - Graceful degradation of features during error states
/// - System notification integration for critical issues
///
/// ## Error Handling Strategy
/// - Visual feedback through orb color changes for minor errors
/// - System notifications for critical issues requiring user action
/// - In-app alerts with actionable buttons for recoverable errors
/// - Silent failure modes for non-critical operations
///
/// ## Usage
/// ```swift
/// let errorManager = ErrorHandlingManager.shared
/// 
/// // Handle microphone access denial
/// errorManager.handleError(.microphoneAccessDenied)
/// 
/// // Handle with recovery options
/// errorManager.handleError(.modelDownloadFailed("Failed to download model"), 
///                         recovery: { await self.retryModelDownload() })
/// ```
@MainActor
public class ErrorHandlingManager: ObservableObject {
    public static let shared = ErrorHandlingManager()
    
    private static let logger = Logger(subsystem: "com.whispernode.error", category: "handling")
    
    // MARK: - Constants
    
    // Error display configuration
    private static let errorOrbDisplayDuration: UInt64 = 3_000_000_000 // 3 seconds
    private static let criticalNotificationDelay: TimeInterval = 0.5 // Delay before showing notifications
    
    // Disk space management
    /// Buffer space to maintain after downloads to prevent system instability
    /// This accounts for temporary files, system operations, and user comfort margin
    private static let diskSpaceBuffer: UInt64 = 500_000_000 // 500MB
    
    /// Warning threshold for low disk space notifications
    private static let lowSpaceThreshold: UInt64 = 1_000_000_000 // 1GB
    
    // MARK: - Dependency Injection
    
    /// Optional indicator manager for dependency injection (improves testability)
    /// Using Any to avoid circular dependency issues
    public var indicatorManager: Any?
    
    // MARK: - Degradation State Tracking
    
    /// Internal state tracking for graceful degradation
    private var degradationState: [String: Bool] = [
        "voiceInput": true,
        "modelDownload": true,
        "transcription": true,
        "hotkey": true
    ]
    
    private init() {
        setupNotificationPermissions()
    }
    
    // MARK: - Error Types
    
    /// Core error types for WhisperNode operations
    public enum WhisperNodeError: Error, LocalizedError, Equatable {
        case microphoneAccessDenied
        case audioCaptureFailure(String)
        case modelDownloadFailed(String)
        case transcriptionFailed
        case hotkeyConflict(String)
        case insufficientDiskSpace
        case networkConnectionFailed
        case modelCorrupted(String)
        case systemResourcesExhausted
        
        public var errorDescription: String? {
            switch self {
            case .microphoneAccessDenied:
                return "Microphone access is required for voice input"
            case .audioCaptureFailure(let details):
                return "Audio capture failed: \(details)"
            case .modelDownloadFailed(let details):
                return "Failed to download model: \(details)"
            case .transcriptionFailed:
                return "Voice transcription failed"
            case .hotkeyConflict(let conflictDetails):
                return "Hotkey conflict detected: \(conflictDetails)"
            case .insufficientDiskSpace:
                return "Insufficient disk space for operation"
            case .networkConnectionFailed:
                return "Network connection failed"
            case .modelCorrupted(let modelName):
                return "Model file corrupted: \(modelName)"
            case .systemResourcesExhausted:
                return "System resources exhausted"
            }
        }
        
        public var recoverySuggestion: String? {
            switch self {
            case .microphoneAccessDenied:
                return "Please enable microphone access in System Preferences > Security & Privacy > Privacy > Microphone"
            case .audioCaptureFailure:
                return "Check your audio settings and try again"
            case .modelDownloadFailed:
                return "Check your internet connection and try again"
            case .transcriptionFailed:
                return "Please try recording again"
            case .hotkeyConflict:
                return "Choose a different hotkey combination"
            case .insufficientDiskSpace:
                return "Free up disk space and try again"
            case .networkConnectionFailed:
                return "Check your network connection"
            case .modelCorrupted:
                return "The model will be re-downloaded automatically"
            case .systemResourcesExhausted:
                return "Close other applications to free up resources"
            }
        }
        
        /// Determines if this error type should trigger automatic recovery
        public var isRecoverable: Bool {
            switch self {
            case .modelDownloadFailed, .networkConnectionFailed, .modelCorrupted, .transcriptionFailed, .audioCaptureFailure:
                return true
            case .microphoneAccessDenied, .hotkeyConflict, .insufficientDiskSpace, .systemResourcesExhausted:
                return false
            }
        }
        
        /// Determines error severity for display strategy
        public var severity: ErrorSeverity {
            switch self {
            case .microphoneAccessDenied, .insufficientDiskSpace:
                return .critical
            case .modelDownloadFailed, .hotkeyConflict, .systemResourcesExhausted, .audioCaptureFailure:
                return .warning
            case .transcriptionFailed, .networkConnectionFailed, .modelCorrupted:
                return .minor
            }
        }
    }
    
    /// Error severity levels for determining display strategy
    public enum ErrorSeverity {
        case minor      // Brief orb color change
        case warning    // Non-blocking notification
        case critical   // System alert with action buttons
    }
    
    // MARK: - Error Handling Interface
    
    /// Handle an error with appropriate user feedback and recovery options
    ///
    /// Provides comprehensive error handling including visual feedback, user notifications,
    /// and automatic recovery mechanisms based on error type and severity.
    ///
    /// - Parameters:
    ///   - error: The error to handle
    ///   - recovery: Optional recovery closure to execute after user notification
    ///   - userContext: Additional context for user-facing error messages
    ///
    /// ## Error Handling Strategy
    /// - **Minor errors**: Brief visual feedback through orb color changes
    /// - **Warning errors**: Non-blocking system notifications
    /// - **Critical errors**: Modal alerts with action buttons
    /// - **Recoverable errors**: Automatic retry with fallback options
    ///
    /// ## Visual Feedback
    /// Visual feedback is provided through the recording indicator orb:
    /// - Red flash for transcription failures
    /// - Persistent red for critical errors
    /// - Orange pulse for warnings
    ///
    /// - Important: This method coordinates with the recording indicator system
    /// - Note: Recovery actions are executed asynchronously
    public func handleError(
        _ error: WhisperNodeError,
        recovery: (() async -> Void)? = nil,
        userContext: String? = nil
    ) {
        Self.logger.error("Handling error: \(error.localizedDescription)")
        
        // Log error details for debugging
        logErrorDetails(error, context: userContext)
        
        // Determine handling strategy based on severity
        switch error.severity {
        case .minor:
            handleMinorError(error, recovery: recovery)
        case .warning:
            handleWarningError(error, recovery: recovery)
        case .critical:
            handleCriticalError(error, recovery: recovery)
        }
    }
    
    /// Handle disk space checking before downloads
    ///
    /// Checks available disk space and prevents downloads if insufficient space exists.
    /// Displays appropriate warnings and guidance for the user.
    ///
    /// - Parameter requiredBytes: Minimum bytes required for the operation
    /// - Returns: Whether sufficient disk space is available
    ///
    /// ## Space Requirements
    /// - Checks both available space and additional buffer (500MB)
    /// - Considers temporary download space requirements
    /// - Warns user before critical space threshold
    ///
    /// - Important: Call before any model download operations
    /// - Note: Returns false and shows error if space is insufficient
    public func checkDiskSpace(requiredBytes: UInt64) -> Bool {
        let fileManager = FileManager.default
        
        do {
            let documentDirectory = try fileManager.url(for: .documentDirectory,
                                                       in: .userDomainMask,
                                                       appropriateFor: nil,
                                                       create: false)
            
            let resourceValues = try documentDirectory.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            
            if let availableSpace = resourceValues.volumeAvailableCapacity {
                let availableBytes = UInt64(availableSpace)
                let bufferSpace = Self.diskSpaceBuffer
                let totalRequired = requiredBytes + bufferSpace
                
                if availableBytes < totalRequired {
                    Self.logger.warning("Insufficient disk space: available \(availableBytes), required \(totalRequired)")
                    handleError(.insufficientDiskSpace)
                    return false
                }
                
                // Warn if space is getting low (less than 1GB after operation)
                if availableBytes - requiredBytes < 1_000_000_000 {
                    showLowDiskSpaceWarning(availableBytes: availableBytes)
                }
                
                return true
            }
        } catch {
            Self.logger.error("Failed to check disk space: \(error.localizedDescription)")
            handleError(.systemResourcesExhausted)
            return false // Fail safely when disk space check fails
        }
        
        Self.logger.error("Disk space check failed for unknown reason")
        handleError(.systemResourcesExhausted) 
        return false // Fail safely when disk space check fails
    }
    
    // MARK: - Specific Error Handlers
    
    /// Handle microphone access denial with system preferences link
    public func handleMicrophoneAccessDenied() {
        degradationState["voiceInput"] = false
        handleError(.microphoneAccessDenied)
    }
    
    /// Handle model download failure with automatic retry and fallback
    public func handleModelDownloadFailure(_ details: String, retryAction: @escaping () async -> Void) {
        degradationState["modelDownload"] = false
        handleError(.modelDownloadFailed(details), recovery: retryAction)
    }
    
    /// Handle transcription failure with silent error and visual feedback
    public func handleTranscriptionFailure() {
        degradationState["transcription"] = false
        handleError(.transcriptionFailed)
    }
    
    /// Handle hotkey conflicts with non-blocking notification
    public func handleHotkeyConflict(_ conflictDetails: String) {
        degradationState["hotkey"] = false
        handleError(.hotkeyConflict(conflictDetails))
    }

    /// Handle network connectivity failures with appropriate user feedback
    public func handleNetworkConnectionFailure(_ details: String) {
        degradationState["modelDownload"] = false
        handleError(.networkConnectionFailed)
    }
    
    // MARK: - Recovery Methods
    
    /// Restore functionality when issues are resolved
    public func restoreFunctionality(for component: String) {
        degradationState[component] = true
        Self.logger.info("Functionality restored for component: \(component)")
    }
    
    /// Restore all functionality (e.g., after app restart or successful recovery)
    public func restoreAllFunctionality() {
        degradationState = [
            "voiceInput": true,
            "modelDownload": true,
            "transcription": true,
            "hotkey": true
        ]
        Self.logger.info("All functionality restored")
    }
    
    // MARK: - Private Implementation
    
    private func setupNotificationPermissions() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                Self.logger.error("Failed to request notification permissions: \(error.localizedDescription)")
            } else {
                Self.logger.info("Notification permissions: \(granted ? "granted" : "denied")")
                if !granted {
                    // Store the denial state for fallback handling
                    UserDefaults.standard.set(false, forKey: "notificationPermissionsGranted")
                }
            }
        }
    }
    
    private func logErrorDetails(_ error: WhisperNodeError, context: String?) {
        var logMessage = "Error occurred: \(error.localizedDescription)"
        if let context = context {
            logMessage += " | Context: \(context)"
        }
        if let suggestion = error.recoverySuggestion {
            logMessage += " | Suggestion: \(suggestion)"
        }
        Self.logger.info("\(logMessage)")
    }
    
    private func handleMinorError(_ error: WhisperNodeError, recovery: (() async -> Void)?) {
        // Brief visual feedback through recording indicator
        showErrorOrb()
        
        // Execute recovery if available
        if let recovery = recovery {
            Task { [weak self] in
                guard self != nil else { return }
                await recovery()
            }
        }
    }
    
    private func handleWarningError(_ error: WhisperNodeError, recovery: (() async -> Void)?) {
        // Show non-blocking notification
        showWarningNotification(error)
        
        // Execute recovery if available and error is recoverable
        if error.isRecoverable, let recovery = recovery {
            Task { [weak self] in
                guard self != nil else { return }
                await recovery()
            }
        }
    }
    
    private func handleCriticalError(_ error: WhisperNodeError, recovery: (() async -> Void)?) {
        // Show system alert with action buttons
        showCriticalAlert(error, recovery: recovery)
    }
    
    private func showErrorOrb() {
        // Get the recording indicator manager and show error state
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            if let customManager = self.indicatorManager as? RecordingIndicatorWindowManagerProtocol {
                // Use injected manager
                customManager.showError()
                try? await Task.sleep(nanoseconds: Self.errorOrbDisplayDuration)
                customManager.hideIndicator()
            } else {
                // Use default manager
                WhisperNodeCore.shared.indicatorManager.showError()
                try? await Task.sleep(nanoseconds: Self.errorOrbDisplayDuration)
                WhisperNodeCore.shared.indicatorManager.hideIndicator()
            }
        }
    }
    
    private func showWarningNotification(_ error: WhisperNodeError) {
        // Check if notifications are available as fallback
        let notificationsGranted = UserDefaults.standard.object(forKey: "notificationPermissionsGranted") as? Bool ?? true
        
        if !notificationsGranted {
            // Use NSAlert as fallback for critical warnings when notifications are denied
            Task { @MainActor in
                let alert = NSAlert()
                alert.messageText = "WhisperNode Warning"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "WhisperNode Warning"
        content.body = error.localizedDescription
        content.sound = UNNotificationSound.default
        
        if let suggestion = error.recoverySuggestion {
            content.subtitle = suggestion
        }
        
        let request = UNNotificationRequest(
            identifier: "whispernode-warning-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: Self.criticalNotificationDelay, repeats: false)
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Self.logger.error("Failed to show warning notification: \(error.localizedDescription)")
                // Fallback to alert if notification fails
                Task { @MainActor in
                    let alert = NSAlert()
                    alert.messageText = "WhisperNode Warning"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
    
    private func showCriticalAlert(_ error: WhisperNodeError, recovery: (() async -> Void)?) {
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = "WhisperNode Error"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            
            // Add action button for microphone permissions
            if case .microphoneAccessDenied = error {
                alert.addButton(withTitle: "Open System Preferences")
                alert.addButton(withTitle: "Cancel")
                
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    openSystemPreferencesPrivacy()
                }
            } else if error.isRecoverable && recovery != nil {
                alert.addButton(withTitle: "Retry")
                alert.addButton(withTitle: "Cancel")
                
                let response = alert.runModal()
                if response == .alertFirstButtonReturn, let recovery = recovery {
                    await recovery()
                }
            } else {
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    private func showLowDiskSpaceWarning(availableBytes: UInt64) {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        let availableString = formatter.string(fromByteCount: Int64(availableBytes))
        
        let content = UNMutableNotificationContent()
        content.title = "Low Disk Space"
        content.body = "Only \(availableString) available. Consider freeing up space."
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(
            identifier: "whispernode-diskspace-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Self.logger.error("Failed to show disk space warning: \(error.localizedDescription)")
            }
        }
    }
    
    private func openSystemPreferencesPrivacy() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Graceful Degradation Support

extension ErrorHandlingManager {
    /// Determine if the app can continue operating with reduced functionality
    ///
    /// Evaluates current error states to determine what functionality should be
    /// disabled or modified to maintain stable operation.
    ///
    /// - Returns: Dictionary of feature states and their availability
    ///
    /// ## Degradation Strategy
    /// - Microphone access denied: Disable all voice input features
    /// - Model download failed: Fall back to smaller bundled model
    /// - Transcription failures: Reduce processing complexity
    /// - Hotkey conflicts: Suggest alternative shortcuts
    ///
    /// - Important: Call this after major error events to update UI state
    /// - Note: Returns current degradation state, not future predictions
    public func getCurrentDegradationState() -> [String: Bool] {
        return degradationState
    }
    
    /// Check if critical functionality is available
    public var isCriticalFunctionalityAvailable: Bool {
        let state = getCurrentDegradationState()
        return state["voiceInput"] == true && state["transcription"] == true
    }
}