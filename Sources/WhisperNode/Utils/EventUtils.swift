import Foundation
import CoreGraphics
import os.log

/// Utility functions for event analysis, debugging, and validation
///
/// This utility class provides comprehensive tools for analyzing CGEvent objects,
/// debugging event flows, and validating event processing in the hotkey system.
/// Created as part of T29e - Key Event Capture Verification.
public class EventUtils {
    private static let logger = Logger(subsystem: "com.whispernode.utils", category: "events")
    
    // MARK: - Event Analysis
    
    /// Analyzes a CGEvent and returns detailed information
    ///
    /// Provides comprehensive analysis of an event including type, timing,
    /// key codes, modifier flags, and other relevant properties.
    ///
    /// - Parameter event: The CGEvent to analyze
    /// - Returns: Dictionary containing detailed event information
    public static func analyzeEvent(_ event: CGEvent) -> [String: Any] {
        let type = event.type
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let timestamp = event.timestamp
        let location = event.location
        
        var analysis: [String: Any] = [
            "type": type.rawValue,
            "typeName": eventTypeName(type),
            "keyCode": keyCode,
            "flags": flags.rawValue,
            "timestamp": timestamp,
            "location": ["x": location.x, "y": location.y]
        ]
        
        // Add modifier flag breakdown
        let cleanFlags = flags.cleanedModifierFlags()
        analysis["cleanFlags"] = cleanFlags.rawValue
        analysis["modifiers"] = analyzeModifierFlags(cleanFlags)
        
        // Add key code interpretation
        if keyCode != 0 {
            analysis["keyName"] = keyCodeToName(UInt16(keyCode))
        }
        
        return analysis
    }
    
    /// Returns human-readable name for event type
    public static func eventTypeName(_ type: CGEventType) -> String {
        switch type {
        case .keyDown: return "keyDown"
        case .keyUp: return "keyUp"
        case .flagsChanged: return "flagsChanged"
        case .leftMouseDown: return "leftMouseDown"
        case .leftMouseUp: return "leftMouseUp"
        case .rightMouseDown: return "rightMouseDown"
        case .rightMouseUp: return "rightMouseUp"
        case .mouseMoved: return "mouseMoved"
        case .leftMouseDragged: return "leftMouseDragged"
        case .rightMouseDragged: return "rightMouseDragged"
        case .scrollWheel: return "scrollWheel"
        case .tabletPointer: return "tabletPointer"
        case .tabletProximity: return "tabletProximity"
        case .otherMouseDown: return "otherMouseDown"
        case .otherMouseUp: return "otherMouseUp"
        case .otherMouseDragged: return "otherMouseDragged"
        case .tapDisabledByTimeout: return "tapDisabledByTimeout"
        case .tapDisabledByUserInput: return "tapDisabledByUserInput"
        default: return "unknown(\(type.rawValue))"
        }
    }
    
    /// Analyzes modifier flags and returns breakdown
    public static func analyzeModifierFlags(_ flags: CGEventFlags) -> [String: Bool] {
        return [
            "command": flags.contains(.maskCommand),
            "control": flags.contains(.maskControl),
            "option": flags.contains(.maskAlternate),
            "shift": flags.contains(.maskShift),
            "capsLock": flags.contains(.maskAlphaShift),
            "numericPad": flags.contains(.maskNumericPad),
            "help": flags.contains(.maskHelp),
            "function": flags.contains(.maskSecondaryFn)
        ]
    }
    
    /// Converts key code to human-readable name
    public static func keyCodeToName(_ keyCode: UInt16) -> String {
        // Common key codes mapping
        switch keyCode {
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
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "Return"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "Delete"
        case 53: return "Escape"
        case 55: return "Command"
        case 56: return "Shift"
        case 57: return "CapsLock"
        case 58: return "Option"
        case 59: return "Control"
        case 60: return "RightShift"
        case 61: return "RightOption"
        case 62: return "RightControl"
        case 63: return "Function"
        case 64: return "F17"
        case 65: return "KeypadDecimal"
        case 67: return "KeypadMultiply"
        case 69: return "KeypadPlus"
        case 71: return "KeypadClear"
        case 75: return "KeypadDivide"
        case 76: return "KeypadEnter"
        case 78: return "KeypadMinus"
        case 79: return "F18"
        case 80: return "F19"
        case 81: return "KeypadEquals"
        case 82: return "Keypad0"
        case 83: return "Keypad1"
        case 84: return "Keypad2"
        case 85: return "Keypad3"
        case 86: return "Keypad4"
        case 87: return "Keypad5"
        case 88: return "Keypad6"
        case 89: return "Keypad7"
        case 90: return "F20"
        case 91: return "Keypad8"
        case 92: return "Keypad9"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 106: return "F16"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 114: return "Help"
        case 115: return "Home"
        case 116: return "PageUp"
        case 117: return "ForwardDelete"
        case 118: return "F4"
        case 119: return "End"
        case 120: return "F2"
        case 121: return "PageDown"
        case 122: return "F1"
        case 123: return "LeftArrow"
        case 124: return "RightArrow"
        case 125: return "DownArrow"
        case 126: return "UpArrow"
        case UInt16.max: return "ModifierOnly"
        default: return "Unknown(\(keyCode))"
        }
    }
    
    // MARK: - Event Debugging
    
    /// Logs comprehensive event information for debugging
    public static func logEventDetails(_ event: CGEvent, context: String = "") {
        let analysis = analyzeEvent(event)
        let contextPrefix = context.isEmpty ? "" : "[\(context)] "
        
        logger.debug("\(contextPrefix)Event Analysis:")
        logger.debug("  Type: \(analysis["typeName"] as? String ?? "unknown") (\(analysis["type"] as? UInt32 ?? 0))")
        logger.debug("  KeyCode: \(analysis["keyCode"] as? Int64 ?? 0) (\(analysis["keyName"] as? String ?? "unknown"))")
        logger.debug("  Flags: \(analysis["flags"] as? UInt64 ?? 0) (clean: \(analysis["cleanFlags"] as? UInt64 ?? 0))")
        logger.debug("  Timestamp: \(analysis["timestamp"] as? UInt64 ?? 0)")
        
        if let modifiers = analysis["modifiers"] as? [String: Bool] {
            let activeModifiers = modifiers.compactMap { $0.value ? $0.key : nil }
            logger.debug("  Active Modifiers: \(activeModifiers.joined(separator: ", "))")
        }
    }
    
    /// Validates event consistency and reports issues
    public static func validateEvent(_ event: CGEvent) -> [String] {
        var issues: [String] = []
        
        let type = event.type
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        // Check for invalid key codes
        if type == .keyDown || type == .keyUp {
            if keyCode < 0 || keyCode > 127 {
                issues.append("Invalid key code: \(keyCode)")
            }
        }
        
        // Check for suspicious flag combinations
        let cleanFlags = flags.cleanedModifierFlags()
        if cleanFlags.rawValue == 0 && (type == .flagsChanged) {
            issues.append("FlagsChanged event with no modifier flags")
        }
        
        // Check timestamp validity
        let timestamp = event.timestamp
        if timestamp == 0 {
            issues.append("Invalid timestamp: 0")
        }
        
        return issues
    }
    
    // MARK: - Performance Monitoring
    
    /// Measures event processing time
    public static func measureEventProcessing<T>(
        _ operation: () throws -> T,
        context: String = ""
    ) rethrows -> (result: T, duration: TimeInterval) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try operation()
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = endTime - startTime
        
        if duration > 0.001 { // Log if processing takes more than 1ms
            logger.warning("Slow event processing [\(context)]: \(duration * 1000)ms")
        }
        
        return (result, duration)
    }
}
