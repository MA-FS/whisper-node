import Foundation
import CoreGraphics
import AppKit
import os.log

/// Manager for global hotkey detection using CGEventTap
/// Handles press-and-hold voice activation with accessibility permissions
public class GlobalHotkeyManager: ObservableObject {
    private static let logger = Logger(subsystem: "com.whispernode.core", category: "hotkey")
    
    // MARK: - Properties
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isListening = false
    
    // Hotkey configuration
    @Published public var currentHotkey: HotkeyConfiguration = .defaultConfiguration
    @Published public var isRecording = false
    
    // Press-and-hold tracking
    private var keyDownTime: CFTimeInterval?
    private let minimumHoldDuration: CFTimeInterval = 0.1 // 100ms minimum hold
    
    // Delegates
    public weak var delegate: GlobalHotkeyManagerDelegate?
    
    // MARK: - Initialization
    public init() {
        Self.logger.info("GlobalHotkeyManager initialized")
    }
    
    deinit {
        stopListening()
    }
    
    // MARK: - Public Methods
    
    /// Request accessibility permissions and start listening for global hotkeys
    public func startListening() {
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
    public func stopListening() {
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
        delegate?.hotkeyManager(self, didStartListening: false)
    }
    
    /// Update the current hotkey configuration
    public func updateHotkey(_ configuration: HotkeyConfiguration) {
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
        guard keyDownTime == nil else { return } // Already pressed
        
        keyDownTime = CFAbsoluteTimeGetCurrent()
        Self.logger.debug("Hotkey pressed down")
        
        DispatchQueue.main.async {
            self.isRecording = true
            self.delegate?.hotkeyManager(self, didStartRecording: true)
        }
    }
    
    private func handleKeyUp(_ event: CGEvent) {
        guard let downTime = keyDownTime else { return }
        
        let upTime = CFAbsoluteTimeGetCurrent()
        let holdDuration = upTime - downTime
        
        keyDownTime = nil
        
        Self.logger.debug("Hotkey released after \(holdDuration)s")
        
        DispatchQueue.main.async {
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
            (49, .maskAlternate, "Option+Space (Character Viewer)")
        ]
        
        for shortcut in systemShortcuts {
            if configuration.keyCode == shortcut.keyCode && 
               configuration.modifierFlags == shortcut.modifiers {
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

public struct HotkeyConflict {
    public let description: String
    public let type: ConflictType
    
    public enum ConflictType {
        case system
        case application(String)
    }
}

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

public enum RecordingCancelReason {
    case tooShort
    case interrupted
}

// MARK: - Delegate Protocol

public protocol GlobalHotkeyManagerDelegate: AnyObject {
    func hotkeyManager(_ manager: GlobalHotkeyManager, didStartListening: Bool)
    func hotkeyManager(_ manager: GlobalHotkeyManager, didStartRecording: Bool)
    func hotkeyManager(_ manager: GlobalHotkeyManager, didCompleteRecording duration: CFTimeInterval)
    func hotkeyManager(_ manager: GlobalHotkeyManager, didCancelRecording reason: RecordingCancelReason)
    func hotkeyManager(_ manager: GlobalHotkeyManager, didFailWithError error: HotkeyError)
    func hotkeyManager(_ manager: GlobalHotkeyManager, accessibilityPermissionRequired: Bool)
    func hotkeyManager(_ manager: GlobalHotkeyManager, didDetectConflict conflict: HotkeyConflict, suggestedAlternatives: [HotkeyConfiguration])
}