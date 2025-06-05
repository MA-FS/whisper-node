import Foundation
import CoreGraphics
import AppKit
import os.log
import Combine

/// Manager for global hotkey detection using CGEventTap
/// 
/// This class provides system-wide hotkey monitoring for press-and-hold voice activation.
/// It handles accessibility permissions, conflict detection with system shortcuts,
/// and provides a delegate-based interface for hotkey events.
///
/// ## Features
/// - Global hotkey capture using CGEventTap
/// - Press-and-hold detection with configurable minimum duration
/// - Conflict detection against common system shortcuts
/// - Accessibility permission management
/// - Customizable hotkey configuration
///
/// ## Usage
/// ```swift
/// let manager = GlobalHotkeyManager()
/// manager.delegate = self
/// manager.startListening()
/// ```
///
/// - Important: Requires accessibility permissions to function properly
/// - Warning: Only one instance should be active at a time
@MainActor
public class GlobalHotkeyManager: ObservableObject {
    public static let shared = GlobalHotkeyManager()
    private static let logger = Logger(subsystem: "com.whispernode.core", category: "hotkey")
    
    // MARK: - Properties
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isListening = false
    
    // Hotkey configuration
    @Published public var currentHotkey: HotkeyConfiguration = .defaultConfiguration
    @Published public var isRecording = false
    
    // Settings integration
    private var settingsManager = SettingsManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Press-and-hold tracking
    private var keyDownTime: CFTimeInterval?
    private let minimumHoldDuration: CFTimeInterval = 0.1 // 100ms minimum hold
    
    // Delegates
    public weak var delegate: GlobalHotkeyManagerDelegate?
    
    // MARK: - Initialization
    public init() {
        // Load hotkey configuration from SettingsManager
        loadHotkeyFromSettings()
        
        // Set up settings synchronization
        setupSettingsObservation()
        
        Self.logger.info("GlobalHotkeyManager initialized")
    }
    
    deinit {
        // Cleanup resources synchronously
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }
    
    // MARK: - Settings Integration
    
    private func loadHotkeyFromSettings() {
        let keyCode = settingsManager.hotkeyKeyCode
        let modifierFlags = CGEventFlags(rawValue: settingsManager.hotkeyModifierFlags)
        let description = formatHotkeyDescription(keyCode: keyCode, modifiers: modifierFlags)
        
        currentHotkey = HotkeyConfiguration(
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            description: description
        )
        
        Self.logger.info("📋 Loaded hotkey from settings: keyCode=\(keyCode), modifiers=\(modifierFlags.rawValue), description='\(description)'")
    }
    
    private func setupSettingsObservation() {
        // Observe hotkey changes in SettingsManager
        Publishers.CombineLatest(
            settingsManager.$hotkeyKeyCode,
            settingsManager.$hotkeyModifierFlags
        )
        .dropFirst() // Skip initial value since we loaded it manually
        .sink { [weak self] _, _ in
            self?.loadHotkeyFromSettings()
        }
        .store(in: &cancellables)
    }
    
    private func saveHotkeyToSettings() {
        settingsManager.hotkeyKeyCode = currentHotkey.keyCode
        settingsManager.hotkeyModifierFlags = currentHotkey.modifierFlags.rawValue
        
        Self.logger.info("💾 Saved hotkey to settings: keyCode=\(self.currentHotkey.keyCode), modifiers=\(self.currentHotkey.modifierFlags.rawValue), description='\(self.currentHotkey.description)'")
    }
    
    private func formatHotkeyDescription(keyCode: UInt16, modifiers: CGEventFlags) -> String {
        var parts: [String] = []
        
        // Add modifier symbols in standard order
        if modifiers.contains(.maskControl) { parts.append("⌃") }
        if modifiers.contains(.maskAlternate) { parts.append("⌥") }
        if modifiers.contains(.maskShift) { parts.append("⇧") }
        if modifiers.contains(.maskCommand) { parts.append("⌘") }
        
        // Handle modifier-only combinations (keyCode = 0)
        if keyCode == 0 {
            return parts.joined() + " (Hold)"
        }
        
        // Add key name for regular key combinations
        parts.append(keyCodeToDisplayString(keyCode))
        
        return parts.joined()
    }
    
    private func keyCodeToDisplayString(_ keyCode: UInt16) -> String {
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
        
        // Special keys
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 53: return "Escape"
        case 76: return "Enter"
        
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
        
        // Arrow keys
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        
        default: return "Key\(keyCode)"
        }
    }
    
    // MARK: - Public Methods
    
    /// Request accessibility permissions and start listening for global hotkeys
    ///
    /// This method sets up a global event tap to monitor keyboard events.
    /// It will automatically request accessibility permissions if not already granted.
    ///
    /// - Important: Accessibility permissions are required for this to work
    /// - Throws: No exceptions, but failures are reported through delegate callbacks
    @MainActor public func startListening() {
        guard !isListening else {
            Self.logger.warning("Already listening for hotkeys")
            return
        }

        Self.logger.info("Starting global hotkey listening for: \(self.currentHotkey.description)")

        // Check accessibility permissions
        guard checkAccessibilityPermissions() else {
            Self.logger.error("Accessibility permissions not granted - cannot start hotkey listening")
            delegate?.hotkeyManager(self, accessibilityPermissionRequired: true)
            return
        }
        
        // Create event tap
        guard let tap = createEventTap() else {
            Self.logger.error("Failed to create event tap - this may indicate insufficient permissions or system restrictions")
            delegate?.hotkeyManager(self, didFailWithError: .eventTapCreationFailed)
            return
        }

        eventTap = tap
        Self.logger.info("Event tap created successfully")
        
        // Create run loop source
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        guard let source = runLoopSource else {
            Self.logger.error("Failed to create run loop source")
            eventTap = nil
            delegate?.hotkeyManager(self, didFailWithError: .eventTapCreationFailed)
            return
        }
        
        // Add to current run loop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        
        // Enable the tap
        CGEvent.tapEnable(tap: tap, enable: true)
        
        isListening = true
        Self.logger.info("Started listening for global hotkeys")
        delegate?.hotkeyManager(self, didStartListening: true)
    }
    
    /// Stop listening for global hotkeys
    ///
    /// Cleanly removes the event tap and cleans up resources.
    /// Safe to call multiple times or when not currently listening.
    @MainActor public func stopListening() {
        cleanup()
        delegate?.hotkeyManager(self, didStartListening: false)
    }
    
    private func cleanup() {
        guard isListening else { return }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        
        isListening = false
        keyDownTime = nil
        
        Self.logger.info("Stopped listening for global hotkeys")
    }
    
    /// Update the current hotkey configuration
    ///
    /// Changes the hotkey that triggers voice recording. The new configuration
    /// is validated against known system shortcuts to prevent conflicts.
    ///
    /// - Parameter configuration: The new hotkey configuration to use
    /// - Note: If a conflict is detected, the change is rejected and alternatives are suggested via delegate
    @MainActor public func updateHotkey(_ configuration: HotkeyConfiguration) {
        let wasListening = isListening
        
        if wasListening {
            stopListening()
        }
        
        // Validate hotkey for conflicts
        if let conflict = detectHotkeyConflicts(configuration) {
            Self.logger.warning("Hotkey conflict detected: \(conflict.description)")
            delegate?.hotkeyManager(self, didDetectConflict: conflict, suggestedAlternatives: generateAlternatives(for: configuration))
            return
        }
        
        currentHotkey = configuration
        
        // Save to persistent settings
        saveHotkeyToSettings()
        
        Self.logger.info("Updated hotkey configuration: \(configuration.description)")
        
        if wasListening {
            startListening()
        }
    }
    
    // MARK: - Private Methods
    
    private func checkAccessibilityPermissions() -> Bool {
        let trusted = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [trusted: true] as CFDictionary
        let hasPermissions = AXIsProcessTrustedWithOptions(options)

        Self.logger.info("Accessibility permissions check: \(hasPermissions ? "granted" : "denied")")

        if !hasPermissions {
            Self.logger.warning("Accessibility permissions required for global hotkey functionality")
            // Show user-friendly permission guidance
            DispatchQueue.main.async { [weak self] in
                self?.showAccessibilityPermissionGuidance()
            }
        }

        return hasPermissions
    }

    private func showAccessibilityPermissionGuidance() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permissions Required"
        alert.informativeText = """
        WhisperNode needs accessibility permissions to capture global hotkeys.

        To enable:
        1. Open System Preferences
        2. Go to Security & Privacy
        3. Click the Privacy tab
        4. Select Accessibility from the list
        5. Click the lock to make changes
        6. Add WhisperNode to the list and check the box

        After granting permissions, please restart WhisperNode.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open System Preferences to Accessibility section
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private func createEventTap() -> CFMachPort? {
        // Create event mask for key events including modifier changes
        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                       (1 << CGEventType.keyUp.rawValue) |
                       (1 << CGEventType.flagsChanged.rawValue)
        
        let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        return eventTap
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Handle event tap disable/enable
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Add comprehensive logging for debugging
        Self.logger.debug("Event received: keyCode=\(keyCode), flags=\(flags.rawValue)")
        Self.logger.debug("Current hotkey: keyCode=\(self.currentHotkey.keyCode), flags=\(self.currentHotkey.modifierFlags.rawValue)")

        // Check if this matches our hotkey
        let matches = matchesCurrentHotkey(event)
        Self.logger.debug("Event matches hotkey: \(matches)")

        guard matches else {
            return Unmanaged.passRetained(event)
        }

        Self.logger.info("🎯 Hotkey event matched! Processing...")

        switch type {
        case .keyDown:
            handleKeyDown(event)
        case .keyUp:
            handleKeyUp(event)
        case .flagsChanged:
            handleFlagsChanged(event)
        default:
            break
        }

        // Consume the event if it matches our hotkey
        return nil
    }
    
    private func matchesCurrentHotkey(_ event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Clean the event flags to remove system flags
        let cleanEventFlags = cleanModifierFlags(flags)
        let cleanHotkeyFlags = cleanModifierFlags(self.currentHotkey.modifierFlags)

        Self.logger.debug("🔍 Checking hotkey match:")
        Self.logger.debug("   Event: keyCode=\(keyCode), flags=\(cleanEventFlags.rawValue)")
        Self.logger.debug("   Hotkey: keyCode=\(self.currentHotkey.keyCode), flags=\(cleanHotkeyFlags.rawValue)")

        // Handle modifier-only combinations (keyCode = 0)
        if self.currentHotkey.keyCode == 0 {
            Self.logger.debug("   Checking modifier-only combination")
            // For modifier-only hotkeys, we only match flagsChanged events with exact modifiers
            // and no additional key press
            return cleanEventFlags == cleanHotkeyFlags && cleanEventFlags.rawValue != 0
        }

        // Check if key code matches for regular key combinations
        guard keyCode == Int64(self.currentHotkey.keyCode) else { 
            Self.logger.debug("   ❌ Key code mismatch: \(keyCode) != \(self.currentHotkey.keyCode)")
            return false 
        }

        // For exact matching, all required modifiers must be present and no extra ones
        let matches = cleanEventFlags == cleanHotkeyFlags
        Self.logger.debug("   \(matches ? "✅" : "❌") Modifier flags match: \(matches)")
        return matches
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
    
    private func handleKeyDown(_ event: CGEvent) {
        let currentTime = CFAbsoluteTimeGetCurrent()

        // Thread-safe check and update
        guard keyDownTime == nil else { return } // Already pressed
        keyDownTime = currentTime

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        Self.logger.info("Hotkey pressed down - keyCode: \(keyCode), flags: \(flags.rawValue), description: \(self.currentHotkey.description)")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isRecording = true
            self.delegate?.hotkeyManager(self, didStartRecording: true)
        }
    }
    
    private func handleKeyUp(_ event: CGEvent) {
        guard let downTime = keyDownTime else { return }

        let upTime = CFAbsoluteTimeGetCurrent()
        let holdDuration = upTime - downTime

        // Reset state
        keyDownTime = nil

        Self.logger.debug("Hotkey released after \(holdDuration)s")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isRecording = false

            if holdDuration >= self.minimumHoldDuration {
                self.delegate?.hotkeyManager(self, didCompleteRecording: holdDuration)
            } else {
                self.delegate?.hotkeyManager(self, didCancelRecording: .tooShort)
            }
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        // For modifier-only combinations, we need to detect when the exact modifier combination is pressed
        // This is primarily for hotkeys like Control+Option without any other key

        let flags = event.flags
        let cleanFlags = cleanModifierFlags(flags)

        Self.logger.debug("🏳️ Flags changed: raw=\(flags.rawValue), clean=\(cleanFlags.rawValue)")
        Self.logger.debug("   Control: \(cleanFlags.contains(.maskControl))")
        Self.logger.debug("   Option: \(cleanFlags.contains(.maskAlternate))")
        Self.logger.debug("   Shift: \(cleanFlags.contains(.maskShift))")
        Self.logger.debug("   Command: \(cleanFlags.contains(.maskCommand))")

        // Check if this is a modifier-only hotkey (keyCode = 0)
        guard currentHotkey.keyCode == 0 else { 
            Self.logger.debug("   Not a modifier-only hotkey, ignoring flags change")
            return 
        }

        let cleanHotkeyFlags = cleanModifierFlags(self.currentHotkey.modifierFlags)
        Self.logger.debug("   Target modifier flags: \(cleanHotkeyFlags.rawValue)")

        // Check if the current flags match our modifier-only hotkey
        if cleanFlags == cleanHotkeyFlags && cleanFlags.rawValue != 0 {
            // Modifiers pressed - start recording
            if keyDownTime == nil {
                let currentTime = CFAbsoluteTimeGetCurrent()
                keyDownTime = currentTime

                Self.logger.info("🎯 Modifier-only hotkey pressed: \(self.currentHotkey.description)")

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.isRecording = true
                    self.delegate?.hotkeyManager(self, didStartRecording: true)
                }
            }
        } else if cleanFlags.rawValue == 0 && keyDownTime != nil {
            // All modifiers released - stop recording
            let downTime = keyDownTime!
            let upTime = CFAbsoluteTimeGetCurrent()
            let holdDuration = upTime - downTime

            keyDownTime = nil

            Self.logger.info("🎯 Modifier-only hotkey released after \(holdDuration)s")

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isRecording = false

                if holdDuration >= self.minimumHoldDuration {
                    self.delegate?.hotkeyManager(self, didCompleteRecording: holdDuration)
                } else {
                    self.delegate?.hotkeyManager(self, didCancelRecording: .tooShort)
                }
            }
        } else if cleanFlags != cleanHotkeyFlags && keyDownTime != nil {
            // Modifier combination changed while recording - cancel
            Self.logger.debug("   Modifier combination changed during recording, cancelling")
            keyDownTime = nil

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isRecording = false
                self.delegate?.hotkeyManager(self, didCancelRecording: .interrupted)
            }
        }
    }
    
    private func detectHotkeyConflicts(_ configuration: HotkeyConfiguration) -> HotkeyConflict? {
        // Check against common system shortcuts
        let systemShortcuts: [(keyCode: UInt16, modifiers: CGEventFlags, description: String)] = [
            (48, .maskCommand, "Cmd+Tab (App Switcher)"),
            (53, .maskCommand, "Cmd+Esc (Force Quit)"),
            (49, .maskCommand, "Cmd+Space (Spotlight)"),
            (49, [.maskControl, .maskCommand], "Ctrl+Cmd+Space (Character Viewer)")
        ]
        
        for shortcut in systemShortcuts {
            if (configuration.keyCode == shortcut.keyCode &&
                configuration.modifierFlags == shortcut.modifiers) {
                return HotkeyConflict(description: shortcut.description, type: .system)
            }
        }
        
        return nil
    }
    
    private func generateAlternatives(for configuration: HotkeyConfiguration) -> [HotkeyConfiguration] {
        // Generate safe alternatives including Control+Option combinations
        let alternatives: [HotkeyConfiguration] = [
            HotkeyConfiguration(keyCode: 49, modifierFlags: [.maskControl, .maskAlternate], description: "⌃⌥Space"),
            HotkeyConfiguration(keyCode: 9, modifierFlags: [.maskControl, .maskAlternate], description: "⌃⌥V"),
            HotkeyConfiguration(keyCode: 49, modifierFlags: [.maskAlternate, .maskShift], description: "⌥⇧Space"),
            HotkeyConfiguration(keyCode: 49, modifierFlags: [.maskControl, .maskShift], description: "⌃⇧Space"),
            HotkeyConfiguration(keyCode: 3, modifierFlags: [.maskCommand, .maskShift], description: "⌘⇧F")
        ]

        return alternatives.filter { $0.keyCode != configuration.keyCode || $0.modifierFlags != configuration.modifierFlags }
    }
}

// MARK: - Supporting Types

/// Configuration for a global hotkey
///
/// Represents a keyboard shortcut that can trigger voice recording.
/// Consists of a key code and modifier flags (Command, Option, etc.)
public struct HotkeyConfiguration: Equatable {
    public let keyCode: UInt16
    public let modifierFlags: CGEventFlags
    public let description: String
    
    public init(keyCode: UInt16, modifierFlags: CGEventFlags, description: String) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.description = description
    }
    
    public static let defaultConfiguration = HotkeyConfiguration(
        keyCode: 49, // Space bar
        modifierFlags: [.maskControl, .maskAlternate], // Control+Option keys
        description: "⌃⌥Space"
    )
}

/// Represents a detected hotkey conflict
///
/// Contains information about a conflict between the desired hotkey
/// and an existing system or application shortcut.
public struct HotkeyConflict {
    public let description: String
    public let type: ConflictType
    
    public enum ConflictType {
        case system
        case application(String)
    }
}

/// Errors that can occur during hotkey management
public enum HotkeyError: Error, LocalizedError {
    case eventTapCreationFailed
    case accessibilityPermissionDenied
    case hotkeyConflict(String)
    
    public var errorDescription: String? {
        switch self {
        case .eventTapCreationFailed:
            return "Failed to create global event tap"
        case .accessibilityPermissionDenied:
            return "Accessibility permissions required"
        case .hotkeyConflict(let description):
            return "Hotkey conflicts with: \(description)"
        }
    }
}

/// Reasons why a recording session was cancelled
public enum RecordingCancelReason {
    case tooShort
    case interrupted
}

// MARK: - Delegate Protocol

/// Delegate protocol for hotkey manager events
///
/// Implement this protocol to receive notifications about hotkey events,
/// recording sessions, errors, and permission requirements.
@MainActor
public protocol GlobalHotkeyManagerDelegate: AnyObject {
    func hotkeyManager(_ manager: GlobalHotkeyManager, didStartListening isListening: Bool)
    func hotkeyManager(_ manager: GlobalHotkeyManager, didStartRecording isRecording: Bool)
    func hotkeyManager(_ manager: GlobalHotkeyManager, didCompleteRecording duration: CFTimeInterval)
    func hotkeyManager(_ manager: GlobalHotkeyManager, didCancelRecording reason: RecordingCancelReason)
    func hotkeyManager(_ manager: GlobalHotkeyManager, didFailWithError error: HotkeyError)
    func hotkeyManager(_ manager: GlobalHotkeyManager, accessibilityPermissionRequired: Bool)
    func hotkeyManager(_ manager: GlobalHotkeyManager, didDetectConflict conflict: HotkeyConflict, suggestedAlternatives: [HotkeyConfiguration])
}