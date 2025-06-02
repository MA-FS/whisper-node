import Foundation
import CoreGraphics
import AppKit
import os.log

/// Text insertion engine using CGEvent keyboard simulation
///
/// Provides system-level text insertion at the current cursor position with smart formatting
/// and compatibility across macOS applications including text editors, browsers, and chat apps.
///
/// ## Features
/// - Character-by-character CGEvent keyboard simulation
/// - Smart capitalization for sentence starts
/// - Punctuation formatting (quotes, apostrophes)
/// - Unicode character support via pasteboard fallback
/// - Comprehensive application compatibility
///
/// ## Usage
/// ```swift
/// let engine = TextInsertionEngine()
/// await engine.insertText("Hello, this is transcribed speech.")
/// ```
///
/// - Important: Requires accessibility permissions for CGEvent posting
/// - Note: Uses pasteboard fallback for complex Unicode characters
public actor TextInsertionEngine {
    private static let logger = Logger(subsystem: "com.whispernode.core", category: "text-insertion")
    
    /// Key code mapping for common characters
    private let keyCodeMap: [Character: CGKeyCode] = [
        // Letters
        "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E, "f": 0x03, "g": 0x05,
        "h": 0x04, "i": 0x22, "j": 0x26, "k": 0x28, "l": 0x25, "m": 0x2E, "n": 0x2D,
        "o": 0x1F, "p": 0x23, "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11, "u": 0x20,
        "v": 0x09, "w": 0x0D, "x": 0x07, "y": 0x10, "z": 0x06,
        
        // Numbers
        "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17,
        "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19,
        
        // Common punctuation
        " ": 0x31, // Space
        ".": 0x2F, ",": 0x2B, "?": 0x2C, "!": 0x1E,
        ";": 0x29, ":": 0x29, // : requires shift
        "'": 0x27, "\"": 0x27, // " requires shift
        "-": 0x1B, "=": 0x18,
        "[": 0x21, "]": 0x1E, // ] requires shift
        "\\": 0x2A, "/": 0x2C,
        "`": 0x32, "~": 0x32, // ~ requires shift
        
        // Return/Enter
        "\n": 0x24, "\r": 0x24
    ]
    
    /// Characters that require the shift key
    private let shiftRequiredChars: Set<Character> = [
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
        "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
        "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+",
        "{", "}", "|", ":", "\"", "<", ">", "?", "~"
    ]
    
    public init() {}
    
    /// Insert text at the current cursor position
    /// - Parameter text: The text to insert
    public func insertText(_ text: String) async {
        Self.logger.info("Inserting text: \(text.prefix(50))...")
        
        let formattedText = applySmartFormatting(text)
        
        // Attempt character-by-character insertion first
        let success = await insertCharacterByCharacter(formattedText)
        
        if !success {
            // Fallback to pasteboard method for complex characters
            Self.logger.warning("Character insertion failed, using pasteboard fallback")
            await insertViaPasteboard(formattedText)
        }
        
        Self.logger.info("Text insertion completed")
    }
    
    /// Insert text character by character using CGEvents
    private func insertCharacterByCharacter(_ text: String) async -> Bool {
        var insertedCount = 0
        
        for character in text {
            if await insertCharacter(character) {
                insertedCount += 1
                // Small delay between characters to ensure proper registration
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            } else {
                Self.logger.warning("Failed to insert character: '\(character)'")
                return false
            }
        }
        
        Self.logger.debug("Successfully inserted \(insertedCount) characters")
        return true
    }
    
    /// Insert a single character using CGEvent
    private func insertCharacter(_ character: Character) async -> Bool {
        let lowercaseChar = Character(character.lowercased())
        
        guard let keyCode = keyCodeMap[lowercaseChar] else {
            Self.logger.debug("No key code mapping for character: '\(character)'")
            return false
        }
        
        let needsShift = shiftRequiredChars.contains(character)
        
        return await MainActor.run {
            // Create key events
            guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
                  let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
                Self.logger.error("Failed to create CGEvent for character: '\(character)'")
                return false
            }
            
            // Add shift modifier if needed
            if needsShift {
                keyDownEvent.flags = .maskShift
                keyUpEvent.flags = .maskShift
            }
            
            // Post events
            keyDownEvent.post(tap: .cghidEventTap)
            keyUpEvent.post(tap: .cghidEventTap)
            
            return true
        }
    }
    
    /// Fallback method using pasteboard for complex Unicode characters
    private func insertViaPasteboard(_ text: String) async {
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            let previousContents = pasteboard.string(forType: .string)
            
            // Set text to pasteboard
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            
            // Simulate Cmd+V
            let cmdVKeyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true) // V key
            let cmdVKeyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
            
            cmdVKeyDown?.flags = .maskCommand
            cmdVKeyUp?.flags = .maskCommand
            
            cmdVKeyDown?.post(tap: .cghidEventTap)
            cmdVKeyUp?.post(tap: .cghidEventTap)
            
            // Restore previous clipboard contents after a delay
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                if let previous = previousContents {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
    }
    
    /// Apply smart formatting to text
    private func applySmartFormatting(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Skip formatting if text is too short
        guard !result.isEmpty else { return result }
        
        // Capitalize first letter
        result = result.prefix(1).capitalized + result.dropFirst()
        
        // Smart punctuation
        result = applySentenceCapitalization(result)
        result = applySmartPunctuation(result)
        
        return result
    }
    
    /// Capitalize letters after sentence-ending punctuation
    private func applySentenceCapitalization(_ text: String) -> String {
        let sentenceEnders: Set<Character> = [".", "!", "?"]
        var result = ""
        var capitalizeNext = false
        
        for character in text {
            if sentenceEnders.contains(character) {
                result.append(character)
                capitalizeNext = true
            } else if character.isWhitespace {
                result.append(character)
                // Keep capitalizeNext flag
            } else if capitalizeNext && character.isLetter {
                result.append(character.uppercased())
                capitalizeNext = false
            } else {
                result.append(character)
                capitalizeNext = false
            }
        }
        
        return result
    }
    
    /// Apply smart punctuation rules
    private func applySmartPunctuation(_ text: String) -> String {
        var result = text
        
        // Convert straight quotes to smart quotes (basic implementation)
        // Note: This is a simplified implementation - full smart quotes require context analysis
        result = result.replacingOccurrences(of: " '", with: " '")
        result = result.replacingOccurrences(of: "' ", with: "' ")
        
        // Ensure proper spacing around punctuation
        result = result.replacingOccurrences(of: " ,", with: ",")
        result = result.replacingOccurrences(of: " .", with: ".")
        result = result.replacingOccurrences(of: " !", with: "!")
        result = result.replacingOccurrences(of: " ?", with: "?")
        
        // Add space after punctuation if missing
        result = result.replacingOccurrences(of: ",([^ ])", with: ", $1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\.([^ ])", with: ". $1", options: .regularExpression)
        result = result.replacingOccurrences(of: "!([^ ])", with: "! $1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\?([^ ])", with: "? $1", options: .regularExpression)
        
        return result
    }
}