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
        return AXIsProcessTrustedWithOptions(options)
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
    /// - Parameter interval: Monitoring interval in seconds (default: 3.0)
    /// - Note: Safe to call multiple times - will not create duplicate monitors
    public func startMonitoring(interval: TimeInterval = 3.0) {
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
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Help")
        
        // Show alert (parentWindow support can be added later if needed)
        let response = alert.runModal()
        
        // Handle response
        switch response {
        case .alertFirstButtonReturn:
            openSystemPreferences()
        case .alertThirdButtonReturn:
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
    
    /// Show additional help for accessibility permissions
    ///
    /// Displays detailed troubleshooting information for users who need additional
    /// guidance with granting accessibility permissions.
    public func showPermissionHelp() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Help"
        alert.informativeText = """
        If you're having trouble granting accessibility permissions:
        
        1. Make sure WhisperNode is running when you check System Preferences
        2. If WhisperNode doesn't appear in the list, try:
           • Quit and restart WhisperNode
           • Click the "+" button to manually add WhisperNode
        3. If the checkbox is grayed out, click the lock icon first
        4. After enabling, return to WhisperNode - it will work immediately
        
        No restart is required! WhisperNode automatically detects permission changes.
        """
        
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    // MARK: - Private Methods
    
    /// Update current permission status and notify observers of changes
    private func updatePermissionStatus() {
        let currentStatus = checkPermissionsQuietly()
        let previousStatus = hasAccessibilityPermission
        
        // Update published property
        hasAccessibilityPermission = currentStatus
        
        // Check for status changes
        if previousStatus != currentStatus {
            Self.logger.info("Accessibility permission status changed: \(previousStatus) -> \(currentStatus)")
            
            // Notify observers
            onPermissionChanged?(currentStatus)
            
            if currentStatus && !previousStatus {
                // Permission newly granted
                Self.logger.info("Accessibility permissions newly granted")
                onPermissionGranted?()
            } else if !currentStatus && previousStatus {
                // Permission revoked
                Self.logger.warning("Accessibility permissions revoked")
                onPermissionRevoked?()
            }
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
