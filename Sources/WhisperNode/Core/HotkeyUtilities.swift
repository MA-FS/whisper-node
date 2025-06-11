import Foundation
import CoreGraphics

/// Shared utilities for hotkey formatting and display
struct HotkeyUtilities {
    
    /// Formats a hotkey description with modifier symbols and key name
    ///
    /// Creates a user-friendly string representation of a hotkey combination using
    /// standard macOS modifier symbols (⌃⌥⇧⌘) and key names.
    ///
    /// ## Examples
    /// ```swift
    /// // Regular key combination
    /// let description = HotkeyUtilities.formatHotkeyDescription(
    ///     keyCode: 49, 
    ///     modifiers: [.maskControl, .maskAlternate]
    /// )
    /// // Result: "⌃⌥Space"
    ///
    /// // Modifier-only combination
    /// let description = HotkeyUtilities.formatHotkeyDescription(
    ///     keyCode: 0, 
    ///     modifiers: [.maskControl, .maskAlternate]
    /// )
    /// // Result: "⌃⌥ (Hold)"
    /// ```
    ///
    /// - Parameters:
    ///   - keyCode: The key code (0 for modifier-only combinations)
    ///   - modifiers: The modifier flags
    /// - Returns: Formatted hotkey description string
    static func formatHotkeyDescription(keyCode: UInt16, modifiers: CGEventFlags) -> String {
        var parts: [String] = []
        
        // Add modifier symbols in standard order
        if modifiers.contains(.maskControl) { parts.append("⌃") }
        if modifiers.contains(.maskAlternate) { parts.append("⌥") }
        if modifiers.contains(.maskShift) { parts.append("⇧") }
        if modifiers.contains(.maskCommand) { parts.append("⌘") }
        
        // Handle modifier-only combinations (keyCode = 0 or UInt16.max)
        if keyCode == 0 || keyCode == UInt16.max {
            return parts.joined() + " (Hold)"
        }
        
        // Add key name for regular key combinations
        parts.append(keyCodeToDisplayString(keyCode))
        
        return parts.joined()
    }
    
    /// Formats a text-based hotkey description for accessibility and settings
    ///
    /// Creates a text-based representation using full modifier names instead of symbols.
    /// Useful for accessibility, settings storage, and debugging.
    ///
    /// ## Examples
    /// ```swift
    /// let description = HotkeyUtilities.formatTextHotkeyDescription(
    ///     keyCode: 49, 
    ///     modifiers: [.maskControl, .maskAlternate]
    /// )
    /// // Result: "Control+Option+Space"
    /// ```
    ///
    /// - Parameters:
    ///   - keyCode: The key code
    ///   - modifiers: The modifier flags
    /// - Returns: Text-based hotkey description
    static func formatTextHotkeyDescription(keyCode: UInt16, modifiers: CGEventFlags) -> String {
        var parts: [String] = []
        
        if modifiers.contains(.maskControl) { parts.append("Control") }
        if modifiers.contains(.maskAlternate) { parts.append("Option") }
        if modifiers.contains(.maskShift) { parts.append("Shift") }
        if modifiers.contains(.maskCommand) { parts.append("Command") }
        
        // Handle modifier-only combinations (keyCode = 0 or UInt16.max)
        if keyCode == 0 || keyCode == UInt16.max {
            return parts.joined(separator: "+") + " (Hold)"
        }
        
        // Convert keyCode to character name
        let keyName = keyCodeToString(keyCode)
        parts.append(keyName)
        
        return parts.joined(separator: "+")
    }
    
    /// Converts a key code to its display string representation
    ///
    /// Maps macOS virtual key codes to their corresponding display strings.
    /// Uses Unicode symbols for special keys when appropriate.
    ///
    /// - Parameter keyCode: The virtual key code
    /// - Returns: Display string for the key
    static func keyCodeToDisplayString(_ keyCode: UInt16) -> String {
        switch keyCode {
        // Letters (QWERTY keyboard layout order)
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        
        // Numbers
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 25: return "9"
        case 26: return "7"
        case 28: return "8"
        case 29: return "0"
        
        // Special keys with symbols
        case 49: return "Space"
        case 36: return "↩"    // Return
        case 48: return "⇥"    // Tab
        case 51: return "⌫"    // Delete
        case 53: return "⎋"    // Escape
        case 76: return "⌤"    // Enter
        
        // Punctuation
        case 24: return "="
        case 27: return "-"
        case 30: return "]"
        case 33: return "["
        case 39: return "'"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 47: return "."
        case 50: return "`"
        
        // Function keys
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
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        case 78: return "F16"
        case 64: return "F17"
        case 79: return "F18"
        case 80: return "F19"
        case 90: return "F20"
        
        // Arrow keys
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        
        // Sentinel value for modifier-only combinations
        case UInt16.max: return "(Modifiers)"
        
        default: return "Key\(keyCode)"
        }
    }
    
    /// Converts a key code to a simple string name (for text-based descriptions)
    ///
    /// Similar to keyCodeToDisplayString but returns plain text names instead of symbols.
    /// Used for accessibility and text-based formats.
    ///
    /// - Parameter keyCode: The virtual key code
    /// - Returns: Plain text name for the key
    static func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        // Common keys with plain text names
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 53: return "Escape"
        case 76: return "Enter"
        
        // Letters (a-z mapping for common range)
        case 0: return "A"
        case 1: return "S" 
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        
        // Numbers
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 25: return "9"
        case 26: return "7"
        case 28: return "8"
        case 29: return "0"
        
        // Function keys
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
        
        default: return "Key \(keyCode)"
        }
    }
}