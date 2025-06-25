import Cocoa
import ApplicationServices
import OSLog

/// Utilities for target application detection and text input validation
///
/// Provides comprehensive functionality for verifying target applications,
/// checking text field availability, and ensuring optimal conditions for
/// text insertion across different macOS applications.
///
/// ## Features
/// - Frontmost application detection and validation
/// - Text field focus verification using Accessibility API
/// - Application readiness checks for text input
/// - Focus management and activation utilities
/// - Application-specific insertion optimizations
///
/// ## Usage
/// ```swift
/// // Check if target application is ready for text input
/// if let app = ApplicationUtils.getFrontmostApplication(),
///    ApplicationUtils.isTextFieldActive() {
///     // Safe to insert text
///     ApplicationUtils.ensureApplicationFocus(app)
/// }
/// ```
@MainActor
public class ApplicationUtils {
    private static let logger = Logger(subsystem: "com.whispernode.utils", category: "application")
    
    // MARK: - Application Detection
    
    /// Get the currently frontmost (active) application
    ///
    /// Returns the application that currently has focus and is receiving
    /// user input. This is the target for text insertion operations.
    ///
    /// - Returns: The frontmost NSRunningApplication, or nil if none found
    /// - Note: This method is safe to call frequently as it uses cached system state
    public static func getFrontmostApplication() -> NSRunningApplication? {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        
        if let app = frontmostApp {
            logger.debug("Frontmost application: \(app.localizedName ?? "Unknown") (\(app.bundleIdentifier ?? "Unknown"))")
        } else {
            logger.warning("No frontmost application found")
        }
        
        return frontmostApp
    }
    
    /// Check if a text field or text area is currently focused and ready for input
    ///
    /// Uses the Accessibility API to determine if the currently focused UI element
    /// can receive text input. This helps prevent text insertion into non-text elements.
    ///
    /// - Returns: `true` if a text input field is focused, `false` otherwise
    /// - Note: Requires accessibility permissions to function properly
    public static func isTextFieldActive() -> Bool {
        logger.debug("Checking for active text field")
        
        // Get the system-wide focused element
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        
        guard result == .success,
              let focusedRef = focusedElement,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            logger.debug("No focused UI element found or accessibility error: \(result.rawValue)")
            return false
        }

        let element = focusedRef as! AXUIElement
        
        // Check if the focused element is a text input type
        var role: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        
        guard roleResult == .success, let roleString = role as? String else {
            logger.debug("Could not determine UI element role")
            return false
        }
        
        let isTextInput = roleString == kAXTextFieldRole || 
                         roleString == kAXTextAreaRole ||
                         roleString == kAXComboBoxRole
        
        logger.debug("Focused element role: \(roleString), is text input: \(isTextInput)")
        return isTextInput
    }
    
    /// Ensure the specified application has focus and is ready to receive input
    ///
    /// Activates the application if it's not currently active and provides
    /// a small delay to allow the activation to complete.
    ///
    /// - Parameter app: The application to ensure focus for
    /// - Note: This method includes a brief delay to allow activation to complete
    public static func ensureApplicationFocus(_ app: NSRunningApplication) {
        logger.info("Ensuring focus for application: \(app.localizedName ?? "Unknown")")
        
        if !app.isActive {
            logger.debug("Application not active, activating...")
            app.activate(options: [])
            
            // Small delay to allow activation to complete
            // This is critical for reliable text insertion
            Thread.sleep(forTimeInterval: 0.05)
            
            logger.debug("Application activation completed")
        } else {
            logger.debug("Application already active")
        }
    }
    
    // MARK: - Text Input Validation
    
    /// Comprehensive check if the current state is suitable for text insertion
    ///
    /// Performs multiple validation checks to ensure text insertion will succeed:
    /// - Frontmost application is available
    /// - Text field is focused and ready
    /// - Application is responsive
    ///
    /// - Returns: `true` if conditions are optimal for text insertion
    public static func isReadyForTextInsertion() -> Bool {
        logger.debug("Performing comprehensive text insertion readiness check")
        
        // Check if we have a frontmost application
        guard let frontmostApp = getFrontmostApplication() else {
            logger.warning("No frontmost application - not ready for text insertion")
            return false
        }
        
        // Ensure the application is active
        guard frontmostApp.isActive else {
            logger.warning("Frontmost application is not active - not ready for text insertion")
            return false
        }
        
        // Check if a text field is focused
        guard isTextFieldActive() else {
            logger.warning("No active text field - not ready for text insertion")
            return false
        }
        
        logger.info("System is ready for text insertion")
        return true
    }
    
    /// Get information about the current text insertion target
    ///
    /// Provides detailed information about the target application and
    /// text field for logging and debugging purposes.
    ///
    /// - Returns: Dictionary with target information, or nil if no valid target
    public static func getTextInsertionTargetInfo() -> [String: String]? {
        guard let app = getFrontmostApplication() else {
            return nil
        }
        
        var info: [String: String] = [:]
        info["applicationName"] = app.localizedName ?? "Unknown"
        info["bundleIdentifier"] = app.bundleIdentifier ?? "Unknown"
        info["isActive"] = String(app.isActive)
        info["hasTextFieldFocus"] = String(isTextFieldActive())
        info["isReadyForInsertion"] = String(isReadyForTextInsertion())
        
        return info
    }
    
    // MARK: - Application-Specific Optimizations
    
    /// Get recommended insertion delay for the specified application
    ///
    /// Some applications require longer delays to properly receive text input.
    /// This method provides application-specific timing recommendations.
    ///
    /// - Parameter app: The target application
    /// - Returns: Recommended delay in seconds before text insertion
    public static func getRecommendedInsertionDelay(for app: NSRunningApplication) -> TimeInterval {
        guard let bundleId = app.bundleIdentifier else {
            return 0.1 // Default delay
        }
        
        // Application-specific delays based on testing
        switch bundleId {
        case "com.microsoft.Word":
            return 0.15 // Word needs extra time for focus
        case "com.adobe.Photoshop":
            return 0.2  // Photoshop text tools are slow to activate
        case "com.apple.Terminal":
            return 0.05 // Terminal is very responsive
        case "com.google.Chrome", "com.apple.Safari":
            return 0.1  // Browsers are generally responsive
        default:
            return 0.1  // Safe default for most applications
        }
    }
    
    /// Check if the application supports reliable text insertion
    ///
    /// Some applications have known issues with programmatic text insertion.
    /// This method identifies applications that may require special handling.
    ///
    /// - Parameter app: The application to check
    /// - Returns: `true` if the application reliably supports text insertion
    public static func supportsReliableTextInsertion(_ app: NSRunningApplication) -> Bool {
        guard let bundleId = app.bundleIdentifier else {
            return true // Assume support for unknown apps
        }
        
        // Known problematic applications
        let problematicApps = [
            "com.1password.1password7",     // Password manager blocks insertion
            "com.apple.keychainaccess",     // Keychain blocks insertion
            "com.vmware.fusion",            // VM apps can be unreliable
            "com.parallels.desktop"         // VM apps can be unreliable
        ]
        
        return !problematicApps.contains(bundleId)
    }
}
