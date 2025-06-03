import Foundation
import AppKit
import CoreGraphics
import os.log

/// Utility class for recording hotkey combinations during onboarding
///
/// This class provides a temporary hotkey recording interface that captures
/// key combinations for configuration purposes. It's designed to be used
/// during the onboarding flow to allow users to set custom hotkeys.
///
/// ## Usage
/// ```swift
/// HotkeyRecorder.shared.startRecording { keyCode, modifierFlags in
///     // Handle captured hotkey
/// }
/// ```
///
/// - Important: This is separate from GlobalHotkeyManager and only used for recording
/// - Note: Recording automatically stops after the first valid key combination
@MainActor
public class HotkeyRecorder: ObservableObject {
    private static let logger = Logger(subsystem: "com.whispernode.core", category: "HotkeyRecorder")
    
    public static let shared = HotkeyRecorder()
    
    // Recording state
    @Published public private(set) var isRecording = false
    private var recordingCallback: ((UInt16, CGEventFlags) -> Void)?
    
    // Event monitoring
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var modifierMonitor: Any?
    
    // Key combination tracking
    private var pressedKeys: Set<UInt16> = []
    private var currentModifiers: CGEventFlags = []
    private var isAwaitingKeyRelease = false
    
    private init() {
        Self.logger.info("HotkeyRecorder initialized")
    }
    
    deinit {
        // Cannot call @MainActor methods from deinit
        // Event monitors will be cleaned up automatically
    }
    
    // MARK: - Public Interface
    
    /// Start recording hotkey combinations
    /// - Parameter callback: Called when a valid hotkey combination is captured
    public func startRecording(callback: @escaping (UInt16, CGEventFlags) -> Void) {
        guard !isRecording else {
            Self.logger.warning("Already recording hotkeys")
            return
        }
        
        Self.logger.info("Starting hotkey recording")
        
        isRecording = true
        recordingCallback = callback
        pressedKeys.removeAll()
        currentModifiers = []
        isAwaitingKeyRelease = false
        
        setupEventMonitors()
    }
    
    /// Stop recording hotkeys
    public func stopRecording() {
        guard isRecording else { return }
        
        Self.logger.info("Stopping hotkey recording")
        
        isRecording = false
        recordingCallback = nil
        pressedKeys.removeAll()
        currentModifiers = []
        isAwaitingKeyRelease = false
        
        removeEventMonitors()
    }
    
    // MARK: - Event Monitoring
    
    private func setupEventMonitors() {
        removeEventMonitors()
        
        // Monitor key down events
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
            return nil // Consume the event to prevent normal processing
        }
        
        // Monitor key up events
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleKeyUp(event)
            return nil // Consume the event to prevent normal processing
        }
        
        // Monitor modifier key changes
        modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierChange(event)
            return nil // Consume the event to prevent normal processing
        }
    }
    
    private func removeEventMonitors() {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        
        if let monitor = keyUpMonitor {
            NSEvent.removeMonitor(monitor)
            keyUpMonitor = nil
        }
        
        if let monitor = modifierMonitor {
            NSEvent.removeMonitor(monitor)
            modifierMonitor = nil
        }
    }
    
    // MARK: - Event Handlers
    
    private func handleKeyDown(_ event: NSEvent) {
        guard isRecording else { return }
        
        let keyCode = UInt16(event.keyCode)
        
        // Ignore modifier-only keys (they're handled separately)
        if isModifierKey(keyCode) {
            return
        }
        
        // Add key to pressed keys set
        pressedKeys.insert(keyCode)
        
        // Update current modifiers from the event
        currentModifiers = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        
        Self.logger.debug("Key down: \(keyCode), modifiers: \(self.currentModifiers.rawValue)")
        
        // If we have both a regular key and modifiers, we have a valid combination
        if !currentModifiers.isEmpty && !pressedKeys.isEmpty {
            captureHotkey(keyCode: keyCode, modifiers: currentModifiers)
        } else if pressedKeys.count == 1 && currentModifiers.isEmpty {
            // Single key press (like just Space) - still valid for some use cases
            captureHotkey(keyCode: keyCode, modifiers: currentModifiers)
        }
    }
    
    private func handleKeyUp(_ event: NSEvent) {
        guard isRecording else { return }
        
        let keyCode = UInt16(event.keyCode)
        pressedKeys.remove(keyCode)
        
        Self.logger.debug("Key up: \(keyCode)")
    }
    
    private func handleModifierChange(_ event: NSEvent) {
        guard isRecording else { return }
        
        currentModifiers = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        
        Self.logger.debug("Modifier change: \(self.currentModifiers.rawValue)")
    }
    
    // MARK: - Hotkey Capture
    
    private func captureHotkey(keyCode: UInt16, modifiers: CGEventFlags) {
        guard isRecording else { return }
        
        // Validate the hotkey combination
        guard isValidHotkeyCombo(keyCode: keyCode, modifiers: modifiers) else {
            Self.logger.debug("Invalid hotkey combination: \(keyCode) with modifiers \(modifiers.rawValue)")
            return
        }
        
        Self.logger.info("Captured hotkey: \(keyCode) with modifiers \(modifiers.rawValue)")
        
        // Clean up the modifiers to remove system flags
        let cleanModifiers = cleanModifierFlags(modifiers)
        
        // Call the callback with the captured hotkey
        recordingCallback?(keyCode, cleanModifiers)
        
        // Stop recording after successful capture
        stopRecording()
    }
    
    private func isValidHotkeyCombo(keyCode: UInt16, modifiers: CGEventFlags) -> Bool {
        // Reject certain problematic key combinations
        
        // Don't allow Escape key as a hotkey
        if keyCode == 53 { // Escape key
            return false
        }
        
        // Don't allow Command+Q (quit shortcut)
        if keyCode == 12 && modifiers.contains(.maskCommand) { // Q key with Command
            return false
        }
        
        // Don't allow Command+W (close window)
        if keyCode == 13 && modifiers.contains(.maskCommand) { // W key with Command
            return false
        }
        
        // Don't allow Command+Tab (app switcher)
        if keyCode == 48 && modifiers.contains(.maskCommand) { // Tab key with Command
            return false
        }
        
        // Require at least one modifier for most keys (except function keys)
        if modifiers.isEmpty && !isFunctionKey(keyCode) && !isSpecialKey(keyCode) {
            return false
        }
        
        return true
    }
    
    private func isModifierKey(_ keyCode: UInt16) -> Bool {
        // Modifier key codes
        return [54, 55, 56, 57, 58, 59, 60, 61, 62].contains(keyCode)
    }
    
    private func isFunctionKey(_ keyCode: UInt16) -> Bool {
        // Function key codes (F1-F12)
        return (122...133).contains(keyCode)
    }
    
    private func isSpecialKey(_ keyCode: UInt16) -> Bool {
        // Special keys that might be acceptable without modifiers
        return [49].contains(keyCode) // Space bar
    }
    
    private func cleanModifierFlags(_ flags: CGEventFlags) -> CGEventFlags {
        // Keep only the essential modifier flags, remove system/internal flags
        var cleanFlags = CGEventFlags()
        
        if flags.contains(.maskCommand) {
            cleanFlags.insert(.maskCommand)
        }
        if flags.contains(.maskAlternate) {
            cleanFlags.insert(.maskAlternate)
        }
        if flags.contains(.maskShift) {
            cleanFlags.insert(.maskShift)
        }
        if flags.contains(.maskControl) {
            cleanFlags.insert(.maskControl)
        }
        
        return cleanFlags
    }
}