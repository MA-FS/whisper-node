import Foundation
import Carbon
import os.log



/// Validation extensions for HotkeyConfiguration
///
/// Provides comprehensive validation, error checking, and utility methods
/// for hotkey configurations to ensure robust persistence and runtime behavior.
extension HotkeyConfiguration {

    /// Configurable list of system shortcuts that should be avoided
    ///
    /// This list can be modified to add or remove system shortcuts based on
    /// user preferences or system requirements.
    static var systemShortcuts: [(keyCode: UInt16, modifiers: CGEventFlags, reason: String)] = [
        (12, .maskCommand, "Cmd+Q may quit applications unexpectedly"),
        (13, .maskCommand, "Cmd+W may close windows unexpectedly"),
        (48, .maskCommand, "Cmd+Tab conflicts with app switcher"),
        (36, .maskCommand, "Cmd+Return may conflict with system shortcuts"),
        (6, .maskCommand, "Cmd+Z conflicts with undo"),
        (7, .maskCommand, "Cmd+X conflicts with cut"),
        (8, .maskCommand, "Cmd+C conflicts with copy"),
        (9, .maskCommand, "Cmd+V conflicts with paste"),
        (0, .maskCommand, "Cmd+A conflicts with select all"),
        (1, .maskCommand, "Cmd+S conflicts with save"),
        (15, .maskCommand, "Cmd+R conflicts with refresh"),
        (17, .maskCommand, "Cmd+T conflicts with new tab"),
        (31, .maskCommand, "Cmd+O conflicts with open"),
        (45, .maskCommand, "Cmd+N conflicts with new"),
        (3, .maskCommand, "Cmd+F conflicts with find"),
        (5, .maskCommand, "Cmd+G conflicts with find next")
    ]
    
    private static let logger = Logger(subsystem: "com.whispernode.core", category: "hotkey-validation")
    
    // MARK: - Validation Properties
    
    /// Indicates if this is a modifier-only hotkey combination
    public var isModifierOnly: Bool {
        return keyCode == UInt16.max
    }
    
    /// Comprehensive validation of the hotkey configuration
    public var isValid: Bool {
        return validationIssues.isEmpty
    }
    
    /// Detailed validation issues found in the configuration
    public var validationIssues: [String] {
        var issues: [String] = []
        
        // Validate modifier-only combinations
        if isModifierOnly {
            issues.append(contentsOf: validateModifierOnlyConfiguration())
        } else {
            issues.append(contentsOf: validateRegularKeyConfiguration())
        }
        
        // Check for system conflicts
        if let conflict = systemConflictDescription {
            issues.append("System conflict: \(conflict)")
        }
        
        // Check for problematic combinations
        issues.append(contentsOf: validateProblematicCombinations())
        
        return issues
    }
    
    /// Description of any system conflict, if present
    public var systemConflictDescription: String? {
        let systemShortcuts = Self.loadSystemShortcuts()
        
        for shortcut in systemShortcuts {
            if keyCode == shortcut.keyCode && modifierFlags == shortcut.modifiers {
                return shortcut.description
            }
        }
        
        return nil
    }
    
    // MARK: - Validation Methods
    
    private func validateModifierOnlyConfiguration() -> [String] {
        var issues: [String] = []
        
        // Must have at least one modifier
        let cleanModifiers = modifierFlags.cleanedModifierFlags()
        if cleanModifiers.rawValue == 0 {
            issues.append("Modifier-only hotkeys must specify at least one modifier.")
            return issues
        }

        // Count active modifiers
        let modifierCount = [
            cleanModifiers.contains(.maskCommand),
            cleanModifiers.contains(.maskControl),
            cleanModifiers.contains(.maskAlternate),
            cleanModifiers.contains(.maskShift)
        ].filter { $0 }.count

        // Recommend at least 2 modifiers to avoid conflicts
        if modifierCount < 2 {
            issues.append("Single modifier hotkeys may conflict with system shortcuts (recommended: 2+ modifiers).")
        }

        // Warn about potentially problematic single modifiers
        if modifierCount == 1 {
            if cleanModifiers.contains(.maskCommand) {
                issues.append("Command-only modifier may interfere with system shortcuts.")
            }
            if cleanModifiers.contains(.maskControl) {
                issues.append("Control-only modifier may interfere with text editing shortcuts.")
            }
        }
        
        return issues
    }
    
    private func validateRegularKeyConfiguration() -> [String] {
        var issues: [String] = []
        
        // Validate key code range
        if keyCode > 127 {
            issues.append("Invalid key code: \(keyCode) (should be 0-127).")
        }

        // Check for modifier requirements
        let cleanModifiers = modifierFlags.cleanedModifierFlags()
        if cleanModifiers.rawValue == 0 && !isFunctionKey(keyCode) && !isSpecialKey(keyCode) {
            issues.append("Regular key combinations should include modifier keys.")
        }
        
        return issues
    }
    
    private func validateProblematicCombinations() -> [String] {
        var issues: [String] = []
        
        // Check for escape key
        if keyCode == 53 { // Escape key
            issues.append("Escape key is not recommended for hotkeys.")
        }
        
        // Check for dangerous system shortcuts using configurable list
        let dangerousCombinations = Self.systemShortcuts
        
        for combination in dangerousCombinations {
            if keyCode == combination.keyCode && modifierFlags.contains(combination.modifiers) {
                issues.append(combination.reason)
            }
        }
        
        return issues
    }
    
    // MARK: - Utility Methods
    
    private func isFunctionKey(_ keyCode: UInt16) -> Bool {
        // Function keys F1-F12 (key codes 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111)
        let functionKeys: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        return functionKeys.contains(keyCode)
    }
    
    private func isSpecialKey(_ keyCode: UInt16) -> Bool {
        // Special keys that might not require modifiers
        let specialKeys: [UInt16] = [
            116, // Page Up
            121, // Page Down
            115, // Home
            119, // End
            123, // Left Arrow
            124, // Right Arrow
            125, // Down Arrow
            126  // Up Arrow
        ]
        return specialKeys.contains(keyCode)
    }
    
    // MARK: - Persistence Validation
    
    /// Validates that the configuration can be safely persisted
    public var canBePersisted: Bool {
        // Check for values that would cause persistence issues
        if keyCode == 0 && !isModifierOnly {
            return false
        }
        

        
        return true
    }
    
    /// Creates a sanitized version of the configuration for persistence
    public var sanitizedForPersistence: HotkeyConfiguration {
        var sanitizedKeyCode = keyCode
        var sanitizedModifiers = modifierFlags
        
        // Clean up modifier flags
        sanitizedModifiers = sanitizedModifiers.cleanedModifierFlags()
        
        // Ensure modifier-only configurations use the correct key code
        if isModifierOnly && sanitizedKeyCode != UInt16.max {
            sanitizedKeyCode = UInt16.max
        }
        
        // Regenerate description to ensure consistency
        let description = formatHotkeyDescription(keyCode: sanitizedKeyCode, modifiers: sanitizedModifiers)
        
        return HotkeyConfiguration(
            keyCode: sanitizedKeyCode,
            modifierFlags: sanitizedModifiers,
            description: description
        )
    }
    
    // MARK: - Logging Support

    /// Logs validation results for debugging
    public func logValidationResults() {
        if isValid {
            Self.logger.info("✅ Hotkey configuration is valid: \(description)")
        } else {
            Self.logger.warning("❌ Hotkey configuration has issues: \(description)")
            for issue in validationIssues {
                Self.logger.warning("  - \(issue)")
            }
        }
    }

    // MARK: - System Shortcuts Management

    /// Loads system shortcuts with future extensibility for configuration
    private static func loadSystemShortcuts() -> [(keyCode: UInt16, modifiers: CGEventFlags, description: String)] {
        // Current hardcoded shortcuts - future versions could load from system APIs or configuration
        return [
            (48, .maskCommand, "Cmd+Tab (App Switcher)"),
            (53, .maskCommand, "Cmd+Esc (Force Quit)"),
            (49, .maskCommand, "Cmd+Space (Spotlight)"),
            (49, [.maskControl, .maskCommand], "Ctrl+Cmd+Space (Character Viewer)"),
            (12, .maskCommand, "Cmd+Q (Quit Application)"),
            (13, .maskCommand, "Cmd+W (Close Window)")
        ]
    }
}

// MARK: - Helper Functions

private func formatHotkeyDescription(keyCode: UInt16, modifiers: CGEventFlags) -> String {
    var parts: [String] = []
    
    // Add modifier symbols
    if modifiers.contains(.maskControl) { parts.append("⌃") }
    if modifiers.contains(.maskAlternate) { parts.append("⌥") }
    if modifiers.contains(.maskShift) { parts.append("⇧") }
    if modifiers.contains(.maskCommand) { parts.append("⌘") }
    
    // Add key name (if not modifier-only)
    if keyCode != UInt16.max {
        let keyName = keyCodeToString(keyCode)
        parts.append(keyName)
    }
    
    return parts.joined()
}

private func keyCodeToString(_ keyCode: UInt16) -> String {
    switch keyCode {
    case 49: return "Space"
    case 36: return "Return"
    case 48: return "Tab"
    case 53: return "Escape"
    case 51: return "Delete"
    case 117: return "Forward Delete"
    case 122: return "F1"
    case 120: return "F2"
    case 99: return "F3"
    case 118: return "F4"
    case 96: return "F5"
    case 97: return "F6"
    case 98: return "F7"
    case 100: return "F8"
    case 101: return "F9"
    case 109: return "F10"
    case 103: return "F11"
    case 111: return "F12"
    default:
        // For letter keys, try to convert to character with proper memory management
        if keyCode >= 0 && keyCode <= 127 {
            let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()

            guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
                return "Key\(keyCode)"
            }

            let keyboardLayout = layoutData.bindMemory(to: UCKeyboardLayout.self, capacity: 1)
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)

            let error = UCKeyTranslate(
                keyboardLayout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                4,
                &length,
                &chars
            )

            // Enhanced error handling for Carbon API
            guard error == noErr else {
                // Log the specific error for debugging
                os_log("UCKeyTranslate failed with error: %d", log: OSLog.default, type: .error, error)
                return "Key\(keyCode)"
            }

            guard length > 0 && length <= chars.count else {
                // Log invalid length for debugging
                os_log("UCKeyTranslate returned invalid length: %d", log: OSLog.default, type: .default, length)
                return "Key\(keyCode)"
            }

            // Safely create string from characters
            let result = String(utf16CodeUnits: chars, count: length).uppercased()
            return result.isEmpty ? "Key\(keyCode)" : result
        }
        return "Key\(keyCode)"
    }
}
