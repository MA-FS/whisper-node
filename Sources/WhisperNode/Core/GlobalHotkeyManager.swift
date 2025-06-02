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
        // Cleanup in deinit - note this is called when object is deallocated
        // We'll handle cleanup synchronously here for resource cleanup
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
    }
    
    private func setupSettingsObservation() {
        // Observe hotkey changes in SettingsManager
        Publishers.CombineLatest(
            settingsManager.$hotkeyKeyCode,
            settingsManager.$hotkeyModifierFlags
        )
        .dropFirst() // Skip initial value since we loaded it manually
        .sink { [weak self] keyCode, modifierFlags in
            self?.loadHotkeyFromSettings()
        }
        .store(in: &cancellables)
    }
    
    private func saveHotkeyToSettings() {
        settingsManager.hotkeyKeyCode = currentHotkey.keyCode
        settingsManager.hotkeyModifierFlags = currentHotkey.modifierFlags.rawValue
    }
    
    private func formatHotkeyDescription(keyCode: UInt16, modifiers: CGEventFlags) -> String {
        var parts: [String] = []
        
        // Add modifier symbols in standard order
        if modifiers.contains(.maskControl) { parts.append("⌃") }
        if modifiers.contains(.maskAlternate) { parts.append("⌥") }
        if modifiers.contains(.maskShift) { parts.append("⇧") }
        if modifiers.contains(.maskCommand) { parts.append("⌘") }
        
        // Add key name
        parts.append(keyCodeToDisplayString(keyCode))
        
        return parts.joined()
    }
    
    private func keyCodeToDisplayString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 53: return "Escape"
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
        
        // Check accessibility permissions
        guard checkAccessibilityPermissions() else {
            Self.logger.error("Accessibility permissions not granted")
            delegate?.hotkeyManager(self, accessibilityPermissionRequired: true)
            return
        }
        
        // Create event tap
        guard let tap = createEventTap() else {
            Self.logger.error("Failed to create event tap")
            delegate?.hotkeyManager(self, didFailWithError: .eventTapCreationFailed)
            return
        }
        
        eventTap = tap
        
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
        return AXIsProcessTrustedWithOptions(options)
    }
    
    private func createEventTap() -> CFMachPort? {
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        
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
        
        // Check if this matches our hotkey
        guard matchesCurrentHotkey(event) else {
            return Unmanaged.passRetained(event)
        }
        
        switch type {
        case .keyDown:
            handleKeyDown(event)
        case .keyUp:
            handleKeyUp(event)
        default:
            break
        }
        
        // Consume the event if it matches our hotkey
        return nil
    }
    
    private func matchesCurrentHotkey(_ event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        return keyCode == Int64(currentHotkey.keyCode) &&
               flags.contains(currentHotkey.modifierFlags)
    }
    
    private func handleKeyDown(_ event: CGEvent) {
        let currentTime = CFAbsoluteTimeGetCurrent()
        
        // Thread-safe check and update
        guard keyDownTime == nil else { return } // Already pressed
        keyDownTime = currentTime
        
        Self.logger.debug("Hotkey pressed down")
        
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
        // Generate safe alternatives
        let alternatives: [HotkeyConfiguration] = [
            HotkeyConfiguration(keyCode: 49, modifierFlags: [.maskAlternate, .maskShift], description: "Option+Shift+Space"),
            HotkeyConfiguration(keyCode: 49, modifierFlags: [.maskControl, .maskShift], description: "Control+Shift+Space"),
            HotkeyConfiguration(keyCode: 3, modifierFlags: [.maskCommand, .maskShift], description: "Cmd+Shift+F")
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
        modifierFlags: .maskAlternate, // Option key
        description: "Option+Space"
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