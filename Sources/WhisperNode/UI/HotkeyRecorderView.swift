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
        let keyCode = recordedKeyCode ?? 0
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
        guard let keyCode = recordedKeyCode, keyCode != 0 else { return false }
        
        // Require at least one modifier key
        return !recordedModifiers.isEmpty
    }
    
    private func startRecording() {
        isRecording = true
        recordedKeyCode = nil
        recordedModifiers = []
        recordingStartTime = Date()

        // Start monitoring key events - use both local and global monitors for better capture
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            self.handleKeyEvent(event)
            return nil // Consume the event
        }

        // Also add global monitor as fallback (requires accessibility permissions)
        globalKeyEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            self.handleKeyEvent(event)
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
        guard let keyCode = recordedKeyCode, isValidHotkey else { return }
        
        let newHotkey = HotkeyConfiguration(
            keyCode: keyCode,
            modifierFlags: recordedModifiers,
            description: formatHotkeyDescription(keyCode: keyCode, modifiers: recordedModifiers)
        )
        
        stopRecording()
        onHotkeyChange(newHotkey)
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        guard isRecording else { return }

        switch event.type {
        case .flagsChanged:
            // Update modifier flags - clean them to only include essential modifiers
            let rawModifiers = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
            recordedModifiers = cleanModifierFlags(rawModifiers)

        case .keyDown:
            // Record the key code
            recordedKeyCode = UInt16(event.keyCode)

            // Update modifiers from the key event as well (in case flagsChanged wasn't captured)
            let rawModifiers = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
            recordedModifiers = cleanModifierFlags(rawModifiers)

            // If we have both key and modifiers, we can save
            if !recordedModifiers.isEmpty {
                // Cancel any previous auto-save work item
                autoSaveWorkItem?.cancel()

                // Auto-save after a delay to allow user to see the combination
                let capturedKeyCode = UInt16(event.keyCode)
                let capturedModifiers = recordedModifiers
                let workItem = DispatchWorkItem {
                    guard self.isRecording,
                          self.recordedKeyCode == capturedKeyCode,
                          self.recordedModifiers == capturedModifiers else { return }
                    self.saveRecordedHotkey()
                }
                autoSaveWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
            }

        default:
            break
        }
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
        case 36: return "↩"
        case 48: return "⇥"
        case 51: return "⌫"
        case 53: return "⎋"
        case 76: return "⌤"
        
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