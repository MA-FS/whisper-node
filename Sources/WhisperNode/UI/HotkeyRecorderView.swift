import SwiftUI
import Carbon

/// A view that allows users to record new hotkey combinations
struct HotkeyRecorderView: View {
    let currentHotkey: HotkeyConfiguration
    @Binding var isRecording: Bool
    let onHotkeyChange: (HotkeyConfiguration) -> Void
    
    @State private var recordedKeyCode: UInt16?
    @State private var recordedModifiers: CGEventFlags = []
    @State private var keyEventMonitor: Any?
    @State private var globalKeyEventMonitor: Any?
    @State private var recordingStartTime: Date?
    @State private var autoSaveWorkItem: DispatchWorkItem?
    
    private let recordingTimeout: TimeInterval = 10.0 // 10 seconds
    
    var body: some View {
        VStack(spacing: 16) {
            // Current hotkey display
            HStack {
                Text("Current Hotkey:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                
                HotkeyDisplayView(
                    hotkey: currentHotkey,
                    isHighlighted: false
                )
                .accessibilityLabel("Current hotkey: \(currentHotkey.description.isEmpty ? "None" : currentHotkey.description)")
                .accessibilityHint("Shows the currently configured activation hotkey")
            }
            
            // Recording interface
            if isRecording {
                VStack(spacing: 12) {
                    HotkeyDisplayView(
                        hotkey: recordedHotkey,
                        isHighlighted: true,
                        showPlaceholder: recordedKeyCode == nil
                    )
                    .accessibilityLabel(recordedKeyCode == nil ? "Recording new hotkey" : "New hotkey: \(recordedHotkey.description)")
                    .accessibilityValue(recordedKeyCode == nil ? "Waiting for key combination" : recordedHotkey.description)
                    .accessibilityHint("Shows the new hotkey combination being recorded")
                    .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HotkeyRecorderDebug"))) { _ in
                        print("🎨 HotkeyDisplayView updated: recordedKeyCode=\(recordedKeyCode ?? 999), description='\(recordedHotkey.description)'")
                    }
                    
                    HStack(spacing: 12) {
                        Button("Cancel") {
                            stopRecording()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Cancel hotkey recording")
                        .accessibilityHint("Stops recording and returns to the previous hotkey")
                        
                        if recordedKeyCode != nil {
                            Button("Save") {
                                saveRecordedHotkey()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!isValidHotkey)
                            .accessibilityLabel("Save new hotkey")
                            .accessibilityHint("Saves the recorded key combination as the new activation hotkey")
                        }
                    }
                    
                    Text("Press your desired key combination...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 2)
                )
            } else {
                Button("Record New Hotkey") {
                    startRecording()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Record new hotkey")
                .accessibilityHint("Start recording a new key combination for voice activation")
            }
        }
        .onAppear {
            // Ensure we're not recording when view appears
            if isRecording {
                stopRecording()
            }
        }
        .onDisappear {
            // Clean up any active recording
            stopRecording()
        }
    }
    
    private var recordedHotkey: HotkeyConfiguration {
        let keyCode = recordedKeyCode ?? UInt16.max
        let description = formatHotkeyDescription(
            keyCode: keyCode,
            modifiers: recordedModifiers
        )
        
        return HotkeyConfiguration(
            keyCode: keyCode,
            modifierFlags: recordedModifiers,
            description: description
        )
    }
    
    private var isValidHotkey: Bool {
        // Handle modifier-only combinations (keyCode = UInt16.max)
        if let keyCode = recordedKeyCode, keyCode == UInt16.max {
            // For modifier-only combinations, require at least 2 modifiers
            let modifierCount = [
                recordedModifiers.contains(.maskControl),
                recordedModifiers.contains(.maskAlternate),
                recordedModifiers.contains(.maskShift),
                recordedModifiers.contains(.maskCommand)
            ].filter { $0 }.count

            return modifierCount >= 2
        }

        guard let keyCode = recordedKeyCode, keyCode != UInt16.max else { return false }

        // Don't allow certain problematic keys
        let problematicKeys: [UInt16] = [53] // Escape key
        if problematicKeys.contains(keyCode) {
            return false
        }

        // Don't allow dangerous system shortcuts
        if keyCode == 12 && recordedModifiers.contains(.maskCommand) { // Cmd+Q
            return false
        }
        if keyCode == 13 && recordedModifiers.contains(.maskCommand) { // Cmd+W
            return false
        }
        if keyCode == 48 && recordedModifiers.contains(.maskCommand) { // Cmd+Tab
            return false
        }

        // Allow Control+Option combinations (our preferred hotkey type)
        if recordedModifiers.contains(.maskControl) && recordedModifiers.contains(.maskAlternate) {
            print("✅ Valid Control+Option combination detected")
            return true
        }

        // Allow other modifier combinations
        if !recordedModifiers.isEmpty {
            return true
        }

        // Allow function keys without modifiers
        if isFunctionKey(keyCode) {
            return true
        }

        // Allow space key without modifiers (for testing)
        if keyCode == 49 { // Space
            return true
        }

        return false
    }

    private func isFunctionKey(_ keyCode: UInt16) -> Bool {
        // Function key codes (F1-F20) - actual key codes from macOS
        let functionKeyCodes: Set<UInt16> = [
            // F1-F12 (standard function keys)
            122, // F1
            120, // F2
            99,  // F3
            118, // F4
            96,  // F5
            97,  // F6
            98,  // F7
            100, // F8
            101, // F9
            109, // F10
            103, // F11
            111, // F12
            // F13-F20 (extended function keys)
            105, // F13
            107, // F14
            113, // F15
            78,  // F16
            64,  // F17
            79,  // F18
            80,  // F19
            90   // F20
        ]
        return functionKeyCodes.contains(keyCode)
    }
    
    private func startRecording() {
        isRecording = true
        recordedKeyCode = nil
        recordedModifiers = []
        recordingStartTime = Date()

        // Check accessibility permissions first - prompt user if needed since they're actively configuring hotkeys
        let trusted = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [trusted: true] as CFDictionary // Prompt for permissions during hotkey configuration
        let hasAccessibilityPermissions = AXIsProcessTrustedWithOptions(options)

        print("🔍 HotkeyRecorderView: Starting recording, accessibility permissions: \(hasAccessibilityPermissions)")

        // Start monitoring key events - prioritize global monitor for modifier-only combinations
        if hasAccessibilityPermissions {
            // Use global monitor for reliable modifier-only capture
            globalKeyEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
                print("🌐 Global event: type=\(event.type), keyCode=\(event.keyCode), modifiers=\(event.modifierFlags.rawValue)")
                self.handleKeyEvent(event)
            }
            print("✅ Using global event monitor for reliable modifier capture")
        } else {
            print("⚠️ No accessibility permissions - modifier-only combinations may not work reliably")
        }
        
        // Always add local monitor as backup
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            print("🔑 Local event: type=\(event.type), keyCode=\(event.keyCode), modifiers=\(event.modifierFlags.rawValue)")
            self.handleKeyEvent(event)
            return nil // Consume the event
        }

        // Set timeout for recording
        DispatchQueue.main.asyncAfter(deadline: .now() + recordingTimeout) {
            if self.isRecording {
                self.stopRecording()
            }
        }
    }
    
    private func stopRecording() {
        isRecording = false
        recordedKeyCode = nil
        recordedModifiers = []
        recordingStartTime = nil

        // Cancel any pending auto-save
        autoSaveWorkItem?.cancel()
        autoSaveWorkItem = nil

        // Remove local event monitor
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }

        // Remove global event monitor
        if let globalMonitor = globalKeyEventMonitor {
            NSEvent.removeMonitor(globalMonitor)
            globalKeyEventMonitor = nil
        }
    }
    
    private func saveRecordedHotkey() {
        guard let keyCode = recordedKeyCode, isValidHotkey else { 
            print("❌ Save failed: keyCode=\(recordedKeyCode ?? 999), isValid=\(isValidHotkey)")
            return 
        }
        
        let description = formatHotkeyDescription(keyCode: keyCode, modifiers: recordedModifiers)
        print("✅ Saving hotkey: keyCode=\(keyCode), modifiers=\(recordedModifiers.rawValue), description=\(description)")
        
        let newHotkey = HotkeyConfiguration(
            keyCode: keyCode,
            modifierFlags: recordedModifiers,
            description: description
        )
        
        stopRecording()
        onHotkeyChange(newHotkey)
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        // Capture isRecording state on the current thread first
        let currentlyRecording = isRecording
        guard currentlyRecording else { return }

        // Capture event data on the current thread before dispatching to main thread
        let eventType = event.type
        let eventKeyCode = event.keyCode
        let eventModifierFlags = event.modifierFlags

        // All SwiftUI state updates must happen on the main thread
        DispatchQueue.main.async {
            // Double-check we're still recording after thread dispatch
            guard self.isRecording else { return }
            
            switch eventType {
            case .flagsChanged:
                // Update modifier flags - clean them to only include essential modifiers
                let rawModifiers = CGEventFlags(rawValue: UInt64(eventModifierFlags.rawValue))
                let cleanedModifiers = rawModifiers.cleanedModifierFlags()
                
                print("🏳️ Flags changed: raw=\(rawModifiers.rawValue), cleaned=\(cleanedModifiers.rawValue)")
                print("   Control: \(cleanedModifiers.contains(.maskControl))")
                print("   Option: \(cleanedModifiers.contains(.maskAlternate))")
                print("   Shift: \(cleanedModifiers.contains(.maskShift))")
                print("   Command: \(cleanedModifiers.contains(.maskCommand))")

                // If modifiers changed from a previous valid combination, reset to allow new combination
                if self.recordedKeyCode == UInt16.max && cleanedModifiers != self.recordedModifiers {
                    print("   🔄 Modifier combination changed, resetting for new input")
                    self.recordedKeyCode = nil
                    self.autoSaveWorkItem?.cancel()
                }
                
                self.recordedModifiers = cleanedModifiers

                // Check if we have a valid modifier-only combination (like Control+Option)
                if !cleanedModifiers.isEmpty && self.recordedKeyCode == nil {
                    // For modifier-only combinations, we'll use a special key code (UInt16.max) to indicate "modifiers only"
                    // But we need at least 2 modifiers for a valid combination
                    let modifierCount = [
                        cleanedModifiers.contains(.maskControl),
                        cleanedModifiers.contains(.maskAlternate),
                        cleanedModifiers.contains(.maskShift),
                        cleanedModifiers.contains(.maskCommand)
                    ].filter { $0 }.count

                    // Special check for Control+Option combination (our preferred hotkey)
                    let isControlOption = cleanedModifiers.contains(.maskControl) && 
                                         cleanedModifiers.contains(.maskAlternate) && 
                                         modifierCount == 2

                    if modifierCount >= 2 {
                        print("   🎯 Valid modifier-only combination detected: \(modifierCount) modifiers")
                        if isControlOption {
                            print("   ✨ Control+Option combination detected - preferred hotkey!")
                        }

                        // Immediately set keyCode=UInt16.max to update UI
                        self.recordedKeyCode = UInt16.max
                        print("   🎨 UI updated to show modifier combination")
                        
                        // Post debug notification to help track UI updates
                        NotificationCenter.default.post(name: NSNotification.Name("HotkeyRecorderDebug"), object: nil)

                        // Cancel any previous auto-save work item
                        self.autoSaveWorkItem?.cancel()

                        // Create more robust auto-save with stable state check
                        let capturedModifiers = cleanedModifiers
                        let workItem = DispatchWorkItem {
                            guard self.isRecording,
                                  self.recordedKeyCode == UInt16.max,
                                  !capturedModifiers.isEmpty else { 
                                print("   ❌ Auto-save skipped: recording=\(self.isRecording), keyCode=\(self.recordedKeyCode ?? 999), modifiers=\(capturedModifiers.rawValue)")
                                return 
                            }
                            print("💾 Auto-saving modifier-only hotkey: \(self.formatModifierOnlyDescription(modifiers: capturedModifiers))")
                            self.saveRecordedHotkey()
                        }
                        self.autoSaveWorkItem = workItem
                        // Shorter delay for Control+Option since it's preferred
                        let delay = isControlOption ? 1.0 : 1.5
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
                    }
                }

            case .keyDown:
                // Update modifiers from the key event as well (in case flagsChanged wasn't captured)
                let rawModifiers = CGEventFlags(rawValue: UInt64(eventModifierFlags.rawValue))
                let cleanedModifiers = rawModifiers.cleanedModifierFlags()

                print("⌨️ Key down: code=\(eventKeyCode), modifiers=\(cleanedModifiers.rawValue)")

                // Record the key code
                self.recordedKeyCode = UInt16(eventKeyCode)
                self.recordedModifiers = cleanedModifiers

                // Check if we have a valid combination
                let hasValidModifiers = !self.recordedModifiers.isEmpty
                let hasValidKey = self.recordedKeyCode != nil

                print("   Valid combination: key=\(hasValidKey), modifiers=\(hasValidModifiers)")

                if hasValidKey && hasValidModifiers {
                    // Cancel any previous auto-save work item
                    self.autoSaveWorkItem?.cancel()

                    // Auto-save after a delay to allow user to see the combination
                    let capturedKeyCode = UInt16(eventKeyCode)
                    let capturedModifiers = self.recordedModifiers
                    let workItem = DispatchWorkItem {
                        guard self.isRecording,
                              self.recordedKeyCode == capturedKeyCode,
                              self.recordedModifiers == capturedModifiers else { return }
                        print("💾 Auto-saving hotkey: \(self.formatHotkeyDescription(keyCode: capturedKeyCode, modifiers: capturedModifiers))")
                        self.saveRecordedHotkey()
                    }
                    self.autoSaveWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
                } else if hasValidKey && self.recordedModifiers.isEmpty {
                    // Allow single key combinations (like just Space) for some use cases
                    print("   Single key combination detected")
                    self.autoSaveWorkItem?.cancel()
                    let workItem = DispatchWorkItem {
                        guard self.isRecording else { return }
                        print("💾 Auto-saving single key: \(self.keyCodeToDisplayString(UInt16(eventKeyCode)))")
                        self.saveRecordedHotkey()
                    }
                    self.autoSaveWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
                }

            default:
                break
            }
        }
    }

    
    private func formatHotkeyDescription(keyCode: UInt16, modifiers: CGEventFlags) -> String {
        return HotkeyUtilities.formatHotkeyDescription(keyCode: keyCode, modifiers: modifiers)
    }

    private func formatModifierOnlyDescription(modifiers: CGEventFlags) -> String {
        return HotkeyUtilities.formatHotkeyDescription(keyCode: UInt16.max, modifiers: modifiers)
    }
    
    private func keyCodeToDisplayString(_ keyCode: UInt16) -> String {
        return HotkeyUtilities.keyCodeToDisplayString(keyCode)
    }
}

/// A view that displays a hotkey combination with styling
private struct HotkeyDisplayView: View {
    let hotkey: HotkeyConfiguration
    var isHighlighted: Bool = false
    var showPlaceholder: Bool = false
    
    var body: some View {
        HStack(spacing: 4) {
            if showPlaceholder {
                Text("Press a key combination...")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                Text(hotkey.description.isEmpty ? "None" : hotkey.description)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(isHighlighted ? .white : .primary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted ? Color.accentColor : Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
    }
}

#if DEBUG
struct HotkeyRecorderView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            HotkeyRecorderView(
                currentHotkey: HotkeyConfiguration(
                    keyCode: 49,
                    modifierFlags: [.maskControl, .maskAlternate],
                    description: "⌃⌥Space"
                ),
                isRecording: .constant(false),
                onHotkeyChange: { _ in }
            )

            HotkeyRecorderView(
                currentHotkey: HotkeyConfiguration(
                    keyCode: 49,
                    modifierFlags: [.maskControl, .maskAlternate],
                    description: "⌃⌥Space"
                ),
                isRecording: .constant(true),
                onHotkeyChange: { _ in }
            )
        }
        .padding()
    }
}
#endif