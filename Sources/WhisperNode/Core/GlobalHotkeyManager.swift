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

    // Enhanced modifier release tracking for T29d
    private var modifierReleaseState: [UInt64: Date] = [:]
    private let releaseToleranceInterval: TimeInterval = 0.1 // 100ms tolerance for sequential releases
    private var releaseCheckTimer: Timer?
    
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

        // Clean up release tracking timer
        releaseCheckTimer?.invalidate()
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
        return HotkeyUtilities.formatHotkeyDescription(keyCode: keyCode, modifiers: modifiers)
    }
    
    private func keyCodeToDisplayString(_ keyCode: UInt16) -> String {
        return HotkeyUtilities.keyCodeToDisplayString(keyCode)
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
        Self.logger.debug("startListening() called - current state: isListening=\(self.isListening)")

        guard !isListening else {
            Self.logger.debug("Already listening for hotkeys - ignoring duplicate start request")
            return
        }

        Self.logger.info("Starting global hotkey listening for: \(self.currentHotkey.description)")

        // Check accessibility permissions
        let hasPermissions = checkAccessibilityPermissions()
        Self.logger.debug("Accessibility permissions check result: \(hasPermissions)")

        guard hasPermissions else {
            Self.logger.error("Accessibility permissions not granted - cannot start hotkey listening")
            delegate?.hotkeyManager(self, accessibilityPermissionRequired: true)
            return
        }

        // Create event tap
        Self.logger.debug("Creating event tap for hotkey monitoring")
        guard let tap = createEventTap() else {
            Self.logger.error("Failed to create event tap - this may indicate insufficient permissions or system restrictions")
            delegate?.hotkeyManager(self, didFailWithError: .eventTapCreationFailed)
            return
        }

        eventTap = tap
        Self.logger.debug("Event tap created successfully")

        // Create run loop source
        Self.logger.debug("Creating run loop source")
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        guard let source = runLoopSource else {
            Self.logger.error("Failed to create run loop source")
            eventTap = nil
            delegate?.hotkeyManager(self, didFailWithError: .eventTapCreationFailed)
            return
        }

        // Add to current run loop
        Self.logger.debug("Adding event tap to run loop")
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)

        // Enable the tap
        Self.logger.debug("Enabling event tap")
        CGEvent.tapEnable(tap: tap, enable: true)

        isListening = true
        Self.logger.info("Successfully started listening for global hotkeys - system ready")
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

        // Clean up release tracking state
        modifierReleaseState.removeAll()
        releaseCheckTimer?.invalidate()
        releaseCheckTimer = nil
        
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
        // Use quiet check first to avoid double prompts
        let hasPermissions = PermissionHelper.shared.checkPermissions(showPrompt: false)

        Self.logger.info("Accessibility permissions check: \(hasPermissions ? "granted" : "denied")")

        if !hasPermissions {
            Self.logger.warning("Accessibility permissions required for global hotkey functionality")
            // Show enhanced user-friendly permission guidance
            DispatchQueue.main.async {
                PermissionHelper.shared.showPermissionGuidance()
            }
        }

        return hasPermissions
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
            Self.logger.warning("Event tap disabled - Type: \(type.rawValue), re-enabling...")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                Self.logger.info("Event tap re-enabled successfully")
            }
            return Unmanaged.passRetained(event)
        }

        // Enhanced event validation and logging (T29e)
        EventUtils.logEventDetails(event, context: "HotkeyManager")
        Self.logger.debug("   Current hotkey: keyCode=\(self.currentHotkey.keyCode), flags=\(self.currentHotkey.modifierFlags.rawValue)")
        Self.logger.debug("   Recording state: isRecording=\(self.isRecording), keyDownTime=\(self.keyDownTime != nil)")

        // Validate event for potential issues
        let validationIssues = EventUtils.validateEvent(event)
        if !validationIssues.isEmpty {
            Self.logger.warning("⚠️ Event validation issues: \(validationIssues.joined(separator: ", "))")
        }

        // Validate event type before processing
        guard isValidEventType(type) else {
            Self.logger.debug("   ⚠️ Ignoring unsupported event type: \(type.rawValue)")
            return Unmanaged.passRetained(event)
        }

        // Check if this matches our hotkey with enhanced validation
        let matches = matchesCurrentHotkey(event, eventType: type)
        Self.logger.debug("   Event matches hotkey: \(matches)")

        guard matches else {
            return Unmanaged.passRetained(event)
        }

        Self.logger.info("🎯 Hotkey event matched! Processing type: \(type.rawValue)")

        // Enhanced event routing with error handling and performance monitoring
        do {
            let (_, processingTime) = try EventUtils.measureEventProcessing {
                switch type {
                case .keyDown:
                    try handleKeyDownWithValidation(event)
                case .keyUp:
                    try handleKeyUpWithValidation(event)
                case .flagsChanged:
                    try handleFlagsChangedWithValidation(event)
                default:
                    Self.logger.warning("⚠️ Unexpected event type in matched event: \(type.rawValue)")
                }
            }

            // Log performance if processing is slow
            if processingTime > 0.005 { // 5ms threshold
                Self.logger.warning("⚠️ Slow event processing: \(processingTime * 1000)ms for \(EventUtils.eventTypeName(type))")
            }
        } catch {
            Self.logger.error("❌ Error processing hotkey event: \(error)")
            return Unmanaged.passRetained(event)
        }

        // Consume the event if it matches our hotkey
        Self.logger.debug("   ✅ Event consumed")
        return nil
    }
    
    // MARK: - Enhanced Event Validation (T29e)

    /// Validates if the event type should be processed
    private func isValidEventType(_ type: CGEventType) -> Bool {
        switch type {
        case .keyDown, .keyUp, .flagsChanged:
            return true
        default:
            return false
        }
    }

    /// Enhanced hotkey matching with event type validation
    private func matchesCurrentHotkey(_ event: CGEvent, eventType: CGEventType) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Clean the event flags to remove system flags
        let cleanEventFlags = flags.cleanedModifierFlags()
        let cleanHotkeyFlags = self.currentHotkey.modifierFlags.cleanedModifierFlags()

        Self.logger.debug("🔍 Enhanced hotkey match check:")
        Self.logger.debug("   Event: type=\(eventType.rawValue), keyCode=\(keyCode), flags=\(cleanEventFlags.rawValue)")
        Self.logger.debug("   Hotkey: keyCode=\(self.currentHotkey.keyCode), flags=\(cleanHotkeyFlags.rawValue)")

        // Handle modifier-only combinations (keyCode = UInt16.max)
        if self.currentHotkey.keyCode == UInt16.max {
            Self.logger.debug("   Checking modifier-only combination")
            // For modifier-only hotkeys, we only match flagsChanged events with exact modifiers
            // and no additional key press
            let isModifierOnlyMatch = eventType == .flagsChanged &&
                                    cleanEventFlags == cleanHotkeyFlags &&
                                    cleanEventFlags.rawValue != 0
            Self.logger.debug("   Modifier-only match: \(isModifierOnlyMatch)")
            return isModifierOnlyMatch
        }

        // For regular key combinations, only match keyDown and keyUp events
        guard eventType == .keyDown || eventType == .keyUp else {
            Self.logger.debug("   ❌ Wrong event type for regular hotkey: \(eventType.rawValue)")
            return false
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

    /// Legacy method for backward compatibility
    private func matchesCurrentHotkey(_ event: CGEvent) -> Bool {
        return matchesCurrentHotkey(event, eventType: CGEventType(rawValue: 0) ?? .keyDown)
    }


    // MARK: - Enhanced Event Handlers with Validation (T29e)

    /// Enhanced keyDown handler with double-triggering prevention
    private func handleKeyDownWithValidation(_ event: CGEvent) throws {
        let currentTime = CFAbsoluteTimeGetCurrent()
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        Self.logger.debug("🔽 Processing keyDown event - keyCode: \(keyCode), flags: \(flags.rawValue)")

        // Enhanced double-triggering prevention
        if let lastKeyDown = keyDownTime {
            let timeSinceLastKeyDown = currentTime - lastKeyDown
            if timeSinceLastKeyDown < 0.05 { // 50ms minimum between key events
                Self.logger.debug("   ⚠️ Ignoring rapid keyDown event (time since last: \(timeSinceLastKeyDown)s)")
                return
            }
        }

        // Prevent starting if already recording
        guard !isRecording else {
            Self.logger.debug("   ⚠️ Already recording, ignoring keyDown")
            return
        }

        keyDownTime = currentTime
        Self.logger.info("🎯 Hotkey pressed down - keyCode: \(keyCode), flags: \(flags.rawValue), description: \(self.currentHotkey.description)")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isRecording = true
            Self.logger.info("✅ Recording started via delegate")
            self.delegate?.hotkeyManager(self, didStartRecording: true)
        }
    }

    /// Legacy keyDown handler for backward compatibility
    private func handleKeyDown(_ event: CGEvent) {
        do {
            try handleKeyDownWithValidation(event)
        } catch {
            Self.logger.error("❌ Error in keyDown handler: \(error)")
        }
    }

    /// Enhanced keyUp handler with validation
    private func handleKeyUpWithValidation(_ event: CGEvent) throws {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        Self.logger.debug("🔼 Processing keyUp event - keyCode: \(keyCode), flags: \(flags.rawValue)")

        guard let downTime = keyDownTime else {
            Self.logger.debug("   ⚠️ No corresponding keyDown event found, ignoring keyUp")
            return
        }

        guard isRecording else {
            Self.logger.debug("   ⚠️ Not currently recording, ignoring keyUp")
            return
        }

        let upTime = CFAbsoluteTimeGetCurrent()
        let holdDuration = upTime - downTime

        // Reset state
        keyDownTime = nil

        Self.logger.info("🎯 Hotkey released after \(holdDuration)s")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isRecording = false

            if holdDuration >= self.minimumHoldDuration {
                Self.logger.info("✅ Recording completed (duration: \(holdDuration)s)")
                self.delegate?.hotkeyManager(self, didCompleteRecording: holdDuration)
            } else {
                Self.logger.warning("⚠️ Recording too short (\(holdDuration)s < \(self.minimumHoldDuration)s), cancelling")
                self.delegate?.hotkeyManager(self, didCancelRecording: .tooShort)
            }
        }
    }

    /// Legacy keyUp handler for backward compatibility
    private func handleKeyUp(_ event: CGEvent) {
        do {
            try handleKeyUpWithValidation(event)
        } catch {
            Self.logger.error("❌ Error in keyUp handler: \(error)")
        }
    }

    /// Enhanced flagsChanged handler with validation
    private func handleFlagsChangedWithValidation(_ event: CGEvent) throws {
        // Enhanced modifier-only hotkey logic with sequential release support (T29d)
        // Enhanced with additional validation and error handling (T29e)

        let flags = event.flags
        let cleanFlags = flags.cleanedModifierFlags()
        let timestamp = event.timestamp

        Self.logger.debug("🏳️ Processing flagsChanged event:")
        Self.logger.debug("   Raw flags: \(flags.rawValue), Clean flags: \(cleanFlags.rawValue)")
        Self.logger.debug("   Timestamp: \(timestamp)")
        Self.logger.debug("   Control: \(cleanFlags.contains(.maskControl))")
        Self.logger.debug("   Option: \(cleanFlags.contains(.maskAlternate))")
        Self.logger.debug("   Shift: \(cleanFlags.contains(.maskShift))")
        Self.logger.debug("   Command: \(cleanFlags.contains(.maskCommand))")

        // Check if this is a modifier-only hotkey (keyCode = UInt16.max)
        guard currentHotkey.keyCode == UInt16.max else {
            Self.logger.debug("   Not a modifier-only hotkey, ignoring flags change")
            return
        }

        let cleanHotkeyFlags = self.currentHotkey.modifierFlags.cleanedModifierFlags()
        Self.logger.debug("   Target modifier flags: \(cleanHotkeyFlags.rawValue)")
        Self.logger.debug("   Current recording state: \(self.isRecording)")

        if !self.isRecording {
            // Not recording - check if we should start
            if cleanFlags == cleanHotkeyFlags && cleanFlags.rawValue != 0 {
                Self.logger.debug("   ✅ Modifier combination matches, starting recording")
                startModifierOnlyRecording()
            } else {
                Self.logger.debug("   ❌ Modifier combination doesn't match target")
            }
        } else {
            // Currently recording - handle release logic with enhanced validation
            if KeyEventUtils.isReleasingTargetModifiers(current: cleanFlags, target: cleanHotkeyFlags) {
                Self.logger.debug("   🔓 Target modifiers being released")
                handleModifierRelease(current: cleanFlags, target: cleanHotkeyFlags)
            } else if KeyEventUtils.isAddingUnrelatedModifiers(current: cleanFlags, target: cleanHotkeyFlags) {
                // Only cancel if adding unrelated modifiers, not releasing target ones
                Self.logger.debug("   ❌ Unrelated modifiers added during recording")
                cancelModifierOnlyRecording(reason: "Unrelated modifier pressed during recording")
            } else {
                Self.logger.debug("   ➡️ No significant modifier change detected")
            }
        }
    }

    /// Legacy flagsChanged handler for backward compatibility
    private func handleFlagsChanged(_ event: CGEvent) {
        do {
            try handleFlagsChangedWithValidation(event)
        } catch {
            Self.logger.error("❌ Error in flagsChanged handler: \(error)")
        }
    }

    // MARK: - Enhanced Modifier-Only Hotkey Logic (T29d)

    /// Starts recording for modifier-only hotkeys
    private func startModifierOnlyRecording() {
        guard keyDownTime == nil else { return }

        let currentTime = CFAbsoluteTimeGetCurrent()
        keyDownTime = currentTime

        // Clear any previous release state
        modifierReleaseState.removeAll()
        releaseCheckTimer?.invalidate()
        releaseCheckTimer = nil

        Self.logger.info("🎯 Modifier-only hotkey pressed: \(self.currentHotkey.description)")
        Self.logger.info("🔊 Triggering delegate callback for recording start")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isRecording = true

            if let delegate = self.delegate {
                Self.logger.info("✅ Calling delegate.didStartRecording")
                delegate.hotkeyManager(self, didStartRecording: true)
            } else {
                Self.logger.error("❌ No delegate found - recording will not be triggered!")
            }
        }
    }

    /// Handles the release of modifier keys with tolerance for sequential releases
    private func handleModifierRelease(current: CGEventFlags, target: CGEventFlags) {
        // Track which modifiers have been released
        let releasedModifiers = target.subtracting(current)
        let now = Date()

        // Record release times for newly released modifiers
        for modifier in releasedModifiers.individualFlags {
            if modifierReleaseState[modifier.rawValue] == nil {
                modifierReleaseState[modifier.rawValue] = now
                Self.logger.debug("🔓 Modifier released: \(modifier.rawValue) at \(now)")
            }
        }

        // Check if all target modifiers have been released
        if current.intersection(target).isEmpty {
            // All modifiers released - complete recording immediately
            Self.logger.info("🎯 All modifiers released simultaneously")
            completeModifierOnlyRecording()
        } else {
            // Some modifiers still held - schedule a check for tolerance period
            Self.logger.debug("⏱️ Some modifiers still held, scheduling release check")
            scheduleReleaseCheck()
        }
    }

    /// Schedules a delayed check to see if all modifiers are released within tolerance
    private func scheduleReleaseCheck() {
        // Cancel any existing timer
        releaseCheckTimer?.invalidate()

        releaseCheckTimer = Timer.scheduledTimer(withTimeInterval: releaseToleranceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.checkForCompleteRelease()
            }
        }
    }

    /// Checks if all target modifiers have been released within the tolerance period
    private func checkForCompleteRelease() {
        guard keyDownTime != nil else { return }

        let cleanHotkeyFlags = self.currentHotkey.modifierFlags.cleanedModifierFlags()

        // Check if we should complete recording based on release state
        if KeyEventUtils.shouldCompleteRecording(
            current: CGEventFlags(rawValue: 0), // Assume all released for tolerance check
            target: cleanHotkeyFlags,
            releaseState: modifierReleaseState,
            tolerance: releaseToleranceInterval
        ) {
            Self.logger.info("🎯 All modifiers released within tolerance period")
            completeModifierOnlyRecording()
        } else {
            Self.logger.debug("⚠️ Release tolerance exceeded, continuing to wait")
        }
    }

    /// Completes the modifier-only recording session
    private func completeModifierOnlyRecording() {
        guard let downTime = keyDownTime else { return }

        let upTime = CFAbsoluteTimeGetCurrent()
        let holdDuration = upTime - downTime

        // Clean up state
        keyDownTime = nil
        modifierReleaseState.removeAll()
        releaseCheckTimer?.invalidate()
        releaseCheckTimer = nil

        Self.logger.info("🎯 Modifier-only hotkey released after \(holdDuration)s")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isRecording = false

            if holdDuration >= self.minimumHoldDuration {
                Self.logger.info("✅ Recording duration met minimum threshold, completing recording")
                self.delegate?.hotkeyManager(self, didCompleteRecording: holdDuration)
            } else {
                Self.logger.warning("⚠️ Recording too short (\(holdDuration)s), cancelling")
                self.delegate?.hotkeyManager(self, didCancelRecording: .tooShort)
            }
        }
    }

    /// Cancels the modifier-only recording session
    private func cancelModifierOnlyRecording(reason: String) {
        Self.logger.debug("❌ Cancelling recording: \(reason)")

        // Clean up state
        keyDownTime = nil
        modifierReleaseState.removeAll()
        releaseCheckTimer?.invalidate()
        releaseCheckTimer = nil

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isRecording = false
            self.delegate?.hotkeyManager(self, didCancelRecording: .interrupted)
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

    // MARK: - Enhanced Configuration Validation (T29e)

    /// Validates a hotkey configuration for potential issues
    ///
    /// Performs comprehensive validation of hotkey configurations to identify
    /// potential problems before they cause runtime issues.
    ///
    /// - Parameter configuration: The hotkey configuration to validate
    /// - Returns: Array of validation issues found (empty if valid)
    public func validateHotkeyConfiguration(_ configuration: HotkeyConfiguration) -> [String] {
        var issues: [String] = []

        // Validate key code
        if configuration.keyCode != UInt16.max {
            // Regular key combination validation
            if configuration.keyCode > 127 {
                issues.append("Invalid key code: \(configuration.keyCode) (should be 0-127)")
            }

            // Check for modifier requirements
            let cleanModifiers = configuration.modifierFlags.cleanedModifierFlags()
            if cleanModifiers.rawValue == 0 {
                issues.append("Regular key combinations should include modifier keys")
            }
        } else {
            // Modifier-only combination validation
            let cleanModifiers = configuration.modifierFlags.cleanedModifierFlags()
            if cleanModifiers.rawValue == 0 {
                issues.append("Modifier-only hotkeys must specify at least one modifier")
            }

            // Check for single modifier (usually not recommended)
            let modifierCount = [
                cleanModifiers.contains(.maskCommand),
                cleanModifiers.contains(.maskControl),
                cleanModifiers.contains(.maskAlternate),
                cleanModifiers.contains(.maskShift)
            ].filter { $0 }.count

            if modifierCount < 2 {
                issues.append("Single modifier hotkeys may conflict with system shortcuts")
            }
        }

        // Check for known problematic combinations
        let problematicCombinations: [(keyCode: UInt16, modifiers: CGEventFlags, reason: String)] = [
            (48, .maskCommand, "Cmd+Tab conflicts with app switcher"),
            (49, .maskCommand, "Cmd+Space conflicts with Spotlight"),
            (53, .maskCommand, "Cmd+Esc conflicts with force quit"),
            (36, .maskCommand, "Cmd+Return may conflict with system shortcuts")
        ]

        for combo in problematicCombinations {
            if configuration.keyCode == combo.keyCode &&
               configuration.modifierFlags.contains(combo.modifiers) {
                issues.append(combo.reason)
            }
        }

        return issues
    }

    /// Performs comprehensive diagnostics on the current hotkey system
    ///
    /// Provides detailed information about the current state of the hotkey system
    /// for debugging and troubleshooting purposes.
    ///
    /// - Returns: Dictionary containing diagnostic information
    public func performHotkeyDiagnostics() -> [String: Any] {
        var diagnostics: [String: Any] = [:]

        // System state
        diagnostics["isListening"] = isListening
        diagnostics["isRecording"] = isRecording
        diagnostics["hasEventTap"] = eventTap != nil
        diagnostics["hasRunLoopSource"] = runLoopSource != nil

        // Current configuration
        diagnostics["currentHotkey"] = [
            "keyCode": currentHotkey.keyCode,
            "modifierFlags": currentHotkey.modifierFlags.rawValue,
            "description": currentHotkey.description
        ]

        // Configuration validation
        let validationIssues = validateHotkeyConfiguration(currentHotkey)
        diagnostics["configurationIssues"] = validationIssues

        // Permissions
        diagnostics["hasAccessibilityPermissions"] = checkAccessibilityPermissions()

        // Timing information
        diagnostics["keyDownTime"] = keyDownTime
        diagnostics["minimumHoldDuration"] = minimumHoldDuration

        // Modifier-only specific state
        if currentHotkey.keyCode == UInt16.max {
            diagnostics["modifierReleaseState"] = modifierReleaseState.mapValues { $0.timeIntervalSinceNow }
            diagnostics["releaseToleranceInterval"] = releaseToleranceInterval
            diagnostics["hasReleaseTimer"] = releaseCheckTimer != nil
        }

        return diagnostics
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