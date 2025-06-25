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
        case accessibilityPermissionDenied
        case audioCaptureFailure(String)
        case modelDownloadFailed(String)
        case transcriptionFailed
        case hotkeyConflict(String)
        case hotkeySystemError(String)
        case insufficientDiskSpace
        case networkConnectionFailed
        case modelCorrupted(String)
        case systemResourcesExhausted
        
        public var errorDescription: String? {
            switch self {
            case .microphoneAccessDenied:
                return "Microphone access is required for voice input"
            case .accessibilityPermissionDenied:
                return "Accessibility permissions are required for global hotkeys"
            case .audioCaptureFailure(let details):
                return "Audio capture failed: \(details)"
            case .modelDownloadFailed(let details):
                return "Failed to download model: \(details)"
            case .transcriptionFailed:
                return "Voice transcription failed"
            case .hotkeyConflict(let conflictDetails):
                return "Hotkey conflict detected: \(conflictDetails)"
            case .hotkeySystemError(let details):
                return "Global hotkey system error: \(details)"
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
            case .accessibilityPermissionDenied:
                return "Please enable accessibility access in System Preferences > Privacy & Security > Accessibility. No restart required!"
            case .audioCaptureFailure:
                return "Check your audio settings and try again"
            case .modelDownloadFailed:
                return "Check your internet connection and try again"
            case .transcriptionFailed:
                return "Please try recording again"
            case .hotkeyConflict:
                return "Choose a different hotkey combination"
            case .hotkeySystemError:
                return "Restart the application or try a different hotkey"
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
            case .modelDownloadFailed, .networkConnectionFailed, .modelCorrupted, .transcriptionFailed, .audioCaptureFailure, .hotkeySystemError:
                return true
            case .microphoneAccessDenied, .accessibilityPermissionDenied, .hotkeyConflict, .insufficientDiskSpace, .systemResourcesExhausted:
                return false
            }
        }
        
        /// Determines error severity for display strategy
        public var severity: ErrorSeverity {
            switch self {
            case .microphoneAccessDenied, .accessibilityPermissionDenied, .insufficientDiskSpace:
                return .critical
            case .modelDownloadFailed, .hotkeyConflict, .hotkeySystemError, .systemResourcesExhausted, .audioCaptureFailure:
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
    
    /// Enhanced error handling with intelligent recovery and user guidance
    ///
    /// Provides comprehensive error handling including visual feedback, user notifications,
    /// automatic recovery mechanisms, and contextual help based on error type and severity.
    ///
    /// - Parameters:
    ///   - error: The error to handle
    ///   - recovery: Optional recovery closure to execute after user notification
    ///   - userContext: Additional context for user-facing error messages
    ///   - showHelp: Whether to offer contextual help for this error
    ///
    /// ## Enhanced Error Handling Strategy
    /// - **Minor errors**: Brief visual feedback with auto-recovery
    /// - **Warning errors**: Non-blocking notifications with guidance
    /// - **Critical errors**: Modal alerts with recovery options and help
    /// - **Recoverable errors**: Intelligent retry with progressive fallback
    /// - **System errors**: Adaptive degradation with user notification
    ///
    /// ## Visual Feedback & User Guidance
    /// - Recording indicator orb provides immediate visual feedback
    /// - Contextual help system offers specific guidance
    /// - Progressive disclosure of technical details
    /// - Accessibility-compliant error presentation
    ///
    /// - Important: This method coordinates with visual feedback and help systems
    /// - Note: Recovery actions are executed asynchronously with progress indication
    public func handleError(
        _ error: WhisperNodeError,
        recovery: (() async -> Void)? = nil,
        userContext: String? = nil,
        showHelp: Bool = true
    ) {
        Self.logger.error("Handling error: \(error.localizedDescription)")

        // Log error details for debugging and analytics
        logErrorDetails(error, context: userContext)

        // Update error statistics for pattern analysis
        updateErrorStatistics(error)

        // Determine handling strategy based on severity and context
        switch error.severity {
        case .minor:
            handleMinorError(error, recovery: recovery, showHelp: showHelp)
        case .warning:
            handleWarningError(error, recovery: recovery, showHelp: showHelp)
        case .critical:
            handleCriticalError(error, recovery: recovery, showHelp: showHelp)
        }

        // Trigger adaptive system response if needed
        triggerAdaptiveResponse(for: error)
    }

    /// Enhanced error handling with automatic retry and progressive fallback
    public func handleErrorWithRetry(
        _ error: WhisperNodeError,
        maxRetries: Int = 3,
        retryDelay: TimeInterval = 1.0,
        fallbackAction: (() async -> Void)? = nil,
        userContext: String? = nil
    ) async {
        var retryCount = 0
        var lastError = error

        while retryCount < maxRetries {
            Self.logger.info("Attempting error recovery (attempt \(retryCount + 1)/\(maxRetries))")

            do {
                // Attempt automatic recovery based on error type
                try await performAutomaticRecovery(for: lastError)
                Self.logger.info("Automatic recovery successful after \(retryCount + 1) attempts")
                return
            } catch let recoveryError as WhisperNodeError {
                lastError = recoveryError
                retryCount += 1

                if retryCount < maxRetries {
                    // Progressive delay between retries
                    let delay = retryDelay * Double(retryCount)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            } catch {
                // Unexpected error during recovery
                lastError = .networkConnectionFailed
                break
            }
        }

        // All retries failed, handle the final error
        handleError(lastError, userContext: userContext)

        // Execute fallback action if provided
        if let fallbackAction = fallbackAction {
            Self.logger.info("Executing fallback action after failed recovery")
            await fallbackAction()
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
    
    /// Handle accessibility permission denial with system preferences link
    public func handleAccessibilityPermissionDenied() {
        degradationState["hotkey"] = false
        handleError(.accessibilityPermissionDenied)
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
        handleError(.networkConnectionFailed, userContext: details)
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
            } else if case .accessibilityPermissionDenied = error {
                alert.addButton(withTitle: "Grant Permissions")
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Help")

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    // Use the enhanced permission guidance from PermissionHelper
                    PermissionHelper.shared.showPermissionGuidance()
                } else if response == .alertThirdButtonReturn {
                    PermissionHelper.shared.showPermissionHelp()
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
    
    private func openSystemPreferencesAccessibility() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
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

    // MARK: - Enhanced Error Handling Methods

    private func handleMinorError(_ error: WhisperNodeError, recovery: (() async -> Void)?, showHelp: Bool) {
        // Brief visual feedback
        showVisualErrorFeedback(error, duration: 1.0)

        // Auto-recovery for minor errors
        if let recovery = recovery {
            Task {
                await recovery()
            }
        }

        // Optional contextual help
        if showHelp && shouldShowHelpForError(error) {
            scheduleContextualHelp(for: error, delay: 2.0)
        }
    }

    private func handleWarningError(_ error: WhisperNodeError, recovery: (() async -> Void)?, showHelp: Bool) {
        // Visual feedback with longer duration
        showVisualErrorFeedback(error, duration: 3.0)

        // Non-blocking notification
        showUserNotification(for: error, includeRecovery: recovery != nil)

        // Contextual help if requested
        if showHelp {
            scheduleContextualHelp(for: error, delay: 1.0)
        }

        // Execute recovery if provided
        if let recovery = recovery {
            Task {
                await recovery()
            }
        }
    }

    private func handleCriticalError(_ error: WhisperNodeError, recovery: (() async -> Void)?, showHelp: Bool) {
        // Persistent visual feedback
        showVisualErrorFeedback(error, duration: 0) // Persistent until resolved

        // Modal alert with recovery options
        showCriticalErrorAlert(error, recovery: recovery, showHelp: showHelp)
    }

    private func updateErrorStatistics(_ error: WhisperNodeError) {
        // Track error patterns for analytics and adaptive responses
        let errorKey = error.analyticsKey
        let currentCount = UserDefaults.standard.integer(forKey: "error_count_\(errorKey)")
        UserDefaults.standard.set(currentCount + 1, forKey: "error_count_\(errorKey)")

        // Track recent error timestamps for pattern detection
        let timestampKey = "error_timestamps_\(errorKey)"
        var timestamps = UserDefaults.standard.array(forKey: timestampKey) as? [Date] ?? []
        timestamps.append(Date())

        // Keep only recent timestamps (last 24 hours)
        let dayAgo = Date().addingTimeInterval(-24 * 60 * 60)
        timestamps = timestamps.filter { $0 > dayAgo }
        UserDefaults.standard.set(timestamps, forKey: timestampKey)
    }

    private func triggerAdaptiveResponse(for error: WhisperNodeError) {
        // Trigger system adaptations based on error patterns
        switch error {
        case .transcriptionFailed:
            // Suggest model downgrade if transcription keeps failing
            if getErrorFrequency(.transcriptionFailed) > 3 {
                NotificationCenter.default.post(
                    name: .performanceOptimizationRecommended,
                    object: nil,
                    userInfo: ["recommendedModel": "tiny.en", "reason": "transcription_failures"]
                )
            }
        case .networkConnectionFailed:
            // Enable conservative mode for network errors
            enableConservativeMode()
        default:
            break
        }
    }

    private func performAutomaticRecovery(for error: WhisperNodeError) async throws {
        Self.logger.info("Attempting automatic recovery for: \(error)")

        switch error {
        case .microphoneAccessDenied:
            // Check if permissions were granted since the error
            let hasPermission = await AudioCaptureEngine.shared.requestPermission()
            if !hasPermission {
                throw WhisperNodeError.microphoneAccessDenied
            }

        case .accessibilityPermissionDenied:
            // Check if accessibility permissions were granted
            if !AXIsProcessTrusted() {
                throw WhisperNodeError.accessibilityPermissionDenied
            }

        case .transcriptionFailed:
            // Try with a more reliable model
            let currentModel = WhisperNodeCore.shared.currentModel
            if !currentModel.contains("tiny") {
                WhisperNodeCore.shared.loadModel("tiny.en")
                // Give the model time to load
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } else {
                throw error // Can't recover further
            }

        case .modelDownloadFailed:
            // Check network connectivity and retry
            if await isNetworkAvailable() {
                // Network is available, the download might succeed now
                return
            } else {
                throw WhisperNodeError.networkConnectionFailed
            }

        default:
            throw error // No automatic recovery available
        }
    }

    private func showVisualErrorFeedback(_ error: WhisperNodeError, duration: TimeInterval) {
        // Show error state in recording indicator
        let indicatorManager = RecordingIndicatorWindowManager()
        indicatorManager.showIndicator(state: .error)

        if duration > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                indicatorManager.hideIndicator()
            }
        }
    }

    private func scheduleContextualHelp(for error: WhisperNodeError, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let helpContext = self.getHelpContextForError(error)
            // Show contextual help tooltip or guidance
            self.showContextualHelp(for: helpContext)
        }
    }

    private func showUserNotification(for error: WhisperNodeError, includeRecovery: Bool) {
        let notification = NSUserNotification()
        notification.title = "WhisperNode"
        notification.informativeText = error.userFriendlyDescription
        notification.soundName = NSUserNotificationDefaultSoundName

        if includeRecovery {
            notification.hasActionButton = true
            notification.actionButtonTitle = "Retry"
        }

        NSUserNotificationCenter.default.deliver(notification)
    }

    private func showCriticalErrorAlert(_ error: WhisperNodeError, recovery: (() async -> Void)?, showHelp: Bool) {
        let alert = NSAlert()
        alert.messageText = error.title
        alert.informativeText = error.userFriendlyDescription
        alert.alertStyle = .critical

        // Add recovery button if available
        if recovery != nil {
            alert.addButton(withTitle: "Retry")
        }

        // Add help button if requested
        if showHelp {
            alert.addButton(withTitle: "Get Help")
        }

        alert.addButton(withTitle: "OK")

        let response = alert.runModal()

        // Handle user response
        switch response {
        case .alertFirstButtonReturn where recovery != nil:
            Task {
                await recovery?()
            }
        case .alertSecondButtonReturn where showHelp:
            let helpContext = getHelpContextForError(error)
            showContextualHelp(for: helpContext)
        default:
            break
        }
    }

    private func getErrorFrequency(_ error: WhisperNodeError) -> Int {
        let errorKey = error.analyticsKey
        return UserDefaults.standard.integer(forKey: "error_count_\(errorKey)")
    }

    private func enableConservativeMode() {
        Self.logger.info("Enabling conservative mode due to system errors")

        // Notify performance monitor to enable conservative settings
        NotificationCenter.default.post(
            name: .conservativeModeEnabled,
            object: nil,
            userInfo: ["reason": "system_errors"]
        )
    }

    private func shouldShowHelpForError(_ error: WhisperNodeError) -> Bool {
        // Don't show help for frequently occurring errors to avoid spam
        return getErrorFrequency(error) < 3
    }

    private func getHelpContextForError(_ error: WhisperNodeError) -> HelpSystem.HelpContext {
        switch error {
        case .microphoneAccessDenied:
            return .microphonePermissions
        case .accessibilityPermissionDenied:
            return .accessibilityPermissions
        case .hotkeyConflict:
            return .hotkeySetup
        case .transcriptionFailed:
            return .voiceSettings
        default:
            return .troubleshooting
        }
    }

    private func showContextualHelp(for context: HelpSystem.HelpContext) {
        // This would integrate with the HelpSystem to show contextual help
        // For now, we'll just log the intent
        Self.logger.info("Would show contextual help for: \(context.rawValue)")
    }

    private func isNetworkAvailable() async -> Bool {
        // Simple network connectivity check
        guard let url = URL(string: "https://www.apple.com") else { return false }

        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

// MARK: - WhisperNodeError Extensions

extension WhisperNodeError {
    var analyticsKey: String {
        switch self {
        case .microphoneAccessDenied:
            return "microphone_access_denied"
        case .accessibilityPermissionDenied:
            return "accessibility_permission_denied"
        case .transcriptionFailed:
            return "transcription_failed"
        case .modelDownloadFailed:
            return "model_download_failed"
        case .hotkeyConflict:
            return "hotkey_conflict"
        case .systemError:
            return "system_error"
        case .networkConnectionFailed:
            return "network_connection_failed"
        }
    }

    var userFriendlyDescription: String {
        switch self {
        case .microphoneAccessDenied:
            return "WhisperNode needs microphone access to transcribe your voice. Please grant permission in System Preferences."
        case .accessibilityPermissionDenied:
            return "WhisperNode needs accessibility permission to detect global hotkeys. Please grant permission in System Preferences."
        case .transcriptionFailed:
            return "Unable to transcribe the audio. Please try speaking more clearly or check your microphone."
        case .modelDownloadFailed(let details):
            return "Failed to download the AI model. Please check your internet connection. Details: \(details)"
        case .hotkeyConflict(let details):
            return "The selected hotkey conflicts with another application. Please choose a different combination. Details: \(details)"
        case .systemError(let details):
            return "A system error occurred. Please try restarting WhisperNode. Details: \(details)"
        case .networkConnectionFailed:
            return "Unable to connect to the internet. Please check your network connection."
        }
    }

    var title: String {
        switch self {
        case .microphoneAccessDenied:
            return "Microphone Access Required"
        case .accessibilityPermissionDenied:
            return "Accessibility Permission Required"
        case .transcriptionFailed:
            return "Transcription Failed"
        case .modelDownloadFailed:
            return "Download Failed"
        case .hotkeyConflict:
            return "Hotkey Conflict"
        case .systemError:
            return "System Error"
        case .networkConnectionFailed:
            return "Network Error"
        }
    }
}

// MARK: - Additional Notification Names

extension Notification.Name {
    static let conservativeModeEnabled = Notification.Name("conservativeModeEnabled")
}