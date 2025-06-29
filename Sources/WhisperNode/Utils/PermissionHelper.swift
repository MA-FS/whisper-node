import Foundation
import Cocoa
import OSLog

/// Centralized utility for managing accessibility permissions
///
/// Provides a unified interface for checking, monitoring, and handling accessibility permissions
/// required for global hotkey functionality. Eliminates restart requirements through runtime
/// monitoring and provides enhanced user guidance.
///
/// ## Features
/// - Non-intrusive permission checking
/// - Runtime permission monitoring with notifications
/// - Enhanced user guidance with step-by-step instructions
/// - Centralized permission state management
/// - Automatic permission change detection
///
/// ## Usage
/// ```swift
/// let helper = PermissionHelper.shared
/// helper.startMonitoring()
/// 
/// // Check current status
/// if helper.hasAccessibilityPermission {
///     // Permissions granted
/// }
/// 
/// // Listen for changes
/// helper.onPermissionChanged = { granted in
///     // Handle permission change
/// }
/// ```
@MainActor
public class PermissionHelper: ObservableObject {
    public static let shared = PermissionHelper()
    
    private static let logger = Logger(subsystem: "com.whispernode.utils", category: "permissions")
    
    // MARK: - Published Properties
    
    /// Current accessibility permission status
    @Published public var hasAccessibilityPermission = false
    
    /// Whether permission monitoring is active
    @Published public var isMonitoring = false
    
    // MARK: - Private Properties

    private var monitoringTimer: Timer?
    private var appActivationObserver: NSObjectProtocol?
    private var lastRefreshTime: Date = .distantPast
    private let minimumRefreshInterval: TimeInterval = 0.5
    
    // MARK: - Callbacks
    
    /// Called when permission status changes
    public var onPermissionChanged: ((Bool) -> Void)?
    
    /// Called when permission is newly granted (false -> true)
    public var onPermissionGranted: (() -> Void)?
    
    /// Called when permission is revoked (true -> false)
    public var onPermissionRevoked: (() -> Void)?
    
    // MARK: - Initialization
    
    private init() {
        // Initialize with current permission status
        updatePermissionStatus()
    }
    
    deinit {
        // Clean up synchronously in deinit
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
        if let observer = appActivationObserver {
            NotificationCenter.default.removeObserver(observer)
            appActivationObserver = nil
        }
    }
    
    // MARK: - Public Methods
    
    /// Check accessibility permissions without showing system prompt
    ///
    /// This method performs a non-intrusive check suitable for auto-start verification
    /// and runtime monitoring without triggering system permission dialogs.
    ///
    /// - Returns: `true` if accessibility permissions are granted, `false` otherwise
    public func checkPermissionsQuietly() -> Bool {
        let trusted = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [trusted: false] as CFDictionary
        let result = AXIsProcessTrustedWithOptions(options)

        // Enhanced debugging for permission issues - only log when denied or first time
        if !result {
            Self.logger.debug("Accessibility permission check: DENIED")
            Self.logger.debug("Bundle identifier: \(Bundle.main.bundleIdentifier ?? "unknown")")
            Self.logger.debug("Process name: \(ProcessInfo.processInfo.processName)")
        }

        return result
    }
    
    /// Check accessibility permissions with optional system prompt
    ///
    /// This method can optionally trigger the system permission dialog if permissions
    /// are not granted. Use for user-initiated permission requests.
    ///
    /// - Parameter showPrompt: Whether to show system permission dialog if not granted
    /// - Returns: `true` if accessibility permissions are granted, `false` otherwise
    public func checkPermissions(showPrompt: Bool = false) -> Bool {
        let trusted = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [trusted: showPrompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    /// Start monitoring accessibility permissions for runtime changes
    ///
    /// Begins periodic checking for permission changes and sets up app activation
    /// observers. Automatically detects when permissions are granted or revoked
    /// without requiring app restart.
    ///
    /// - Parameter interval: Monitoring interval in seconds (default: 1.0 for more responsive detection)
    /// - Note: Safe to call multiple times - will not create duplicate monitors
    public func startMonitoring(interval: TimeInterval = 1.0) {
        guard !isMonitoring else {
            Self.logger.debug("Permission monitoring already active")
            return
        }

        Self.logger.info("Starting accessibility permission monitoring with \(interval)s interval")

        // Update initial status
        updatePermissionStatus()

        // Set up periodic checking with configurable interval
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePermissionStatus()
            }
        }

        // Set up app activation observer for immediate checking when app becomes active
        setupAppActivationObserver()

        isMonitoring = true
        Self.logger.info("Permission monitoring started successfully")
    }
    
    /// Stop monitoring accessibility permissions
    ///
    /// Cleans up timers and observers. Safe to call multiple times.
    public func stopMonitoring() {
        guard isMonitoring else { return }

        Self.logger.info("Stopping accessibility permission monitoring")

        // Clean up timer
        monitoringTimer?.invalidate()
        monitoringTimer = nil

        // Clean up app activation observer
        if let observer = appActivationObserver {
            NotificationCenter.default.removeObserver(observer)
            appActivationObserver = nil
        }

        isMonitoring = false
        Self.logger.info("Permission monitoring stopped")
    }

    /// Manually refresh permission status
    ///
    /// Forces an immediate check of accessibility permissions. Useful when users
    /// have just granted permissions and want to verify the change is detected.
    /// This method provides immediate feedback without waiting for the next
    /// monitoring cycle.
    ///
    /// - Returns: Current permission status after refresh
    @discardableResult
    public func refreshPermissionStatus() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastRefreshTime) >= minimumRefreshInterval else {
            Self.logger.debug("Permission refresh rate limited - returning cached status")
            return hasAccessibilityPermission
        }
        lastRefreshTime = now

        Self.logger.info("Manually refreshing accessibility permission status")

        // Force multiple checks to handle timing issues
        let check1 = checkPermissionsQuietly()

        // Small delay to handle potential system timing issues
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            let check2 = self?.checkPermissionsQuietly() ?? false
            Self.logger.debug("Secondary permission check: \(check2 ? "GRANTED" : "DENIED")")

            if check1 != check2 {
                Self.logger.warning("Permission status inconsistent between checks: \(check1) vs \(check2)")
                // Update with the more recent check
                self?.updatePermissionStatus()
            }
        }

        updatePermissionStatus()
        Self.logger.info("Permission status after refresh: \(self.hasAccessibilityPermission)")
        return self.hasAccessibilityPermission
    }

    /// Show detailed permission help with troubleshooting steps
    public func showPermissionHelp() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Help"
        alert.informativeText = """
        WhisperNode needs accessibility permissions to capture global hotkeys.

        Troubleshooting Steps:

        1. Open System Preferences → Privacy & Security → Accessibility
        2. Look for "WhisperNode" in the list
        3. If not found, click the "+" button and add WhisperNode manually
        4. Make sure the checkbox next to WhisperNode is checked
        5. Click the lock icon if you need to make changes

        Advanced Troubleshooting:
        • Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")
        • Current status: \(hasAccessibilityPermission ? "Granted" : "Denied")
        • If issues persist, try restarting WhisperNode after granting permissions

        Note: Some security software may interfere with accessibility permissions.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Check Again")
        alert.addButton(withTitle: "Close")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            openSystemPreferences()
        case .alertSecondButtonReturn:
            let _ = refreshPermissionStatus()
        default:
            break
        }
    }

    /// Show enhanced accessibility permission guidance dialog
    ///
    /// Displays a user-friendly dialog with step-by-step instructions for granting
    /// accessibility permissions. Includes direct link to System Preferences and
    /// emphasizes that no restart is required.
    ///
    /// - Parameter parentWindow: Optional parent window for modal presentation
    public func showPermissionGuidance(parentWindow: NSWindow? = nil) {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permissions Required"
        alert.informativeText = """
        WhisperNode needs accessibility permissions to capture global hotkeys.
        
        Steps to enable:
        1. Click "Open System Preferences" below
        2. Go to Privacy & Security → Accessibility
        3. Click the lock icon to make changes
        4. Find WhisperNode in the list and enable it
        5. Return to WhisperNode (no restart needed!)
        
        WhisperNode will automatically detect when permissions are granted.
        """
        
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Check Again")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Help")

        // Show alert (parentWindow support can be added later if needed)
        let response = alert.runModal()

        // Handle response
        switch response {
        case .alertFirstButtonReturn:
            openSystemPreferences()
        case .alertSecondButtonReturn:
            // Check permissions again and show result
            let hasPermissions = refreshPermissionStatus()
            if hasPermissions {
                showPermissionGrantedConfirmation()
            } else {
                showPermissionStillMissingAlert()
            }
        case .alertThirdButtonReturn:
            // Cancel - do nothing
            break
        case NSApplication.ModalResponse(rawValue: 1003): // Fourth button (Help)
            showPermissionHelp()
        default:
            break
        }
    }
    
    /// Open System Preferences to Accessibility section
    ///
    /// Opens the macOS System Preferences directly to the Accessibility privacy section
    /// where users can grant permissions to WhisperNode.
    public func openSystemPreferences() {
        Self.logger.info("Opening System Preferences to Accessibility section")

        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security"
        ]

        for urlString in urls {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                Self.logger.info("Successfully opened System Preferences with URL: \(urlString)")
                return // Success
            }
        }

        // Fallback: show error if all URLs fail
        Self.logger.error("Failed to open System Preferences - all URLs failed")
        showSystemPreferencesError()
    }

    /// Show error when System Preferences cannot be opened
    private func showSystemPreferencesError() {
        let alert = NSAlert()
        alert.messageText = "Unable to Open System Preferences"
        alert.informativeText = """
        WhisperNode couldn't automatically open System Preferences.

        Please manually open:
        System Preferences → Privacy & Security → Accessibility

        Then add WhisperNode to the list and enable it.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    


    /// Show confirmation when permissions are successfully granted
    private func showPermissionGrantedConfirmation() {
        let alert = NSAlert()
        alert.messageText = "Permissions Granted Successfully!"
        alert.informativeText = """
        WhisperNode now has accessibility permissions and can capture global hotkeys.

        You can now use your configured hotkey to activate voice recording.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Great!")
        alert.runModal()
    }

    /// Show alert when permissions are still missing after check
    private func showPermissionStillMissingAlert() {
        let alert = NSAlert()
        alert.messageText = "Permissions Still Required"
        alert.informativeText = """
        WhisperNode still doesn't have accessibility permissions.

        Please make sure you:
        1. Opened System Preferences → Privacy & Security → Accessibility
        2. Found WhisperNode in the list and enabled it
        3. Clicked the lock icon if needed to make changes
        4. If WhisperNode isn't in the list, try restarting the app

        Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")

        If the issue persists, try restarting WhisperNode after granting permissions.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Restart App")
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            // Restart app
            restartApplication()
        case .alertSecondButtonReturn:
            // Try checking again
            let _ = refreshPermissionStatus()
        default:
            break
        }
    }

    /// Restart the application
    private func restartApplication() {
        guard let resourcePath = Bundle.main.resourcePath else {
            Self.logger.error("Failed to get resource path for app restart")
            return
        }

        let url = URL(fileURLWithPath: resourcePath)
        let appURL = url.deletingLastPathComponent().deletingLastPathComponent()

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [appURL.path]

        do {
            try task.run()
            Self.logger.info("Successfully initiated app restart")
            NSApplication.shared.terminate(nil)
        } catch {
            Self.logger.error("Failed to restart application: \(error)")
        }
    }
    
    // MARK: - Private Methods
    
    /// Update current permission status and notify observers of changes
    private func updatePermissionStatus() {
        let currentStatus = checkPermissionsQuietly()
        let previousStatus = hasAccessibilityPermission

        // Log detailed permission check for debugging
        Self.logger.debug("Permission check: previous=\(previousStatus), current=\(currentStatus)")

        // Update published property
        hasAccessibilityPermission = currentStatus

        // Check for status changes
        if previousStatus != currentStatus {
            Self.logger.info("Accessibility permission status changed: \(previousStatus) -> \(currentStatus)")

            // Notify observers
            onPermissionChanged?(currentStatus)

            if currentStatus && !previousStatus {
                // Permission newly granted
                Self.logger.info("Accessibility permissions newly granted - hotkey functionality now available")
                onPermissionGranted?()
            } else if !currentStatus && previousStatus {
                // Permission revoked
                Self.logger.warning("Accessibility permissions revoked - hotkey functionality disabled")
                onPermissionRevoked?()
            }
        } else if currentStatus {
            // Log periodic confirmation that permissions are still active
            Self.logger.debug("Accessibility permissions confirmed active")
        }
    }
    
    /// Set up app activation observer for immediate permission checking
    private func setupAppActivationObserver() {
        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updatePermissionStatus()
            }
        }
    }
}
