import SwiftUI
import Carbon

/// Preferences tab for configuring global hotkey shortcuts
struct ShortcutTab: View {
    @ObservedObject private var hotkeyManager = GlobalHotkeyManager.shared
    @State private var isRecording = false
    @State private var conflictAlert: ConflictAlert?
    @State private var showingResetConfirmation = false
    
    private struct ConflictAlert {
        let title: String
        let message: String
        let suggestions: [HotkeyConfiguration]
        let originalConfig: HotkeyConfiguration
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "command")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    Text("Hotkey Settings")
                        .font(.title2)
                        .fontWeight(.medium)
                    Spacer()
                }
                
                Text("Configure the global hotkey for voice recording activation")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            Divider()
            
            // Current Hotkey Section
            VStack(spacing: 16) {
                HStack {
                    Text("Current Hotkey")
                        .font(.headline)
                    Spacer()
                }
                
                HotkeyRecorderView(
                    currentHotkey: hotkeyManager.currentHotkey,
                    isRecording: $isRecording,
                    onHotkeyChange: { newHotkey in
                        updateHotkey(newHotkey)
                    }
                )
            }
            .padding(.horizontal, 20)
            
            Divider()
            
            // Instructions Section
            VStack(spacing: 12) {
                HStack {
                    Text("Instructions")
                        .font(.headline)
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    InstructionRow(
                        icon: "1.circle.fill",
                        text: "Click \"Record New Hotkey\" to start recording"
                    )
                    InstructionRow(
                        icon: "2.circle.fill", 
                        text: "Press your desired key combination"
                    )
                    InstructionRow(
                        icon: "3.circle.fill",
                        text: "The hotkey will be automatically validated"
                    )
                    InstructionRow(
                        icon: "exclamationmark.triangle.fill",
                        text: "Use modifier keys (⌘⌥⌃⇧) for best compatibility",
                        color: .orange
                    )
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
            
            // Reset Button
            HStack {
                Spacer()
                Button("Reset to Default") {
                    showingResetConfirmation = true
                }
                .buttonStyle(.bordered)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .alert("Hotkey Conflict", isPresented: .constant(conflictAlert != nil)) {
            if let alert = conflictAlert {
                Button("Cancel") {
                    conflictAlert = nil
                }
                
                if !alert.suggestions.isEmpty {
                    Button("Use \(alert.suggestions.first?.description ?? "")") {
                        if let suggestion = alert.suggestions.first {
                            hotkeyManager.updateHotkey(suggestion)
                        }
                        conflictAlert = nil
                    }
                }
                
                Button("Use Anyway") {
                    hotkeyManager.updateHotkey(alert.originalConfig)
                    conflictAlert = nil
                }
            }
        } message: {
            if let alert = conflictAlert {
                Text(alert.message)
            }
        }
        .confirmationDialog(
            "Reset Hotkey",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset to Default", role: .destructive) {
                resetToDefault()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will reset the hotkey to Option+Space. Are you sure?")
        }
    }
    
    private func updateHotkey(_ newHotkey: HotkeyConfiguration) {
        // Check for conflicts
        let conflicts = validateHotkey(newHotkey)
        
        if !conflicts.isEmpty {
            // Generate suggestions
            let suggestions = generateAlternatives(for: newHotkey)
            
            conflictAlert = ConflictAlert(
                title: "Hotkey Conflict",
                message: "The hotkey \(newHotkey.description) conflicts with existing system shortcuts. Choose an alternative or use anyway.",
                suggestions: suggestions,
                originalConfig: newHotkey
            )
        } else {
            hotkeyManager.updateHotkey(newHotkey)
        }
    }
    
    private func resetToDefault() {
        let defaultHotkey = HotkeyConfiguration(
            keyCode: 49, // Space
            modifierFlags: .maskAlternate, // Option
            description: "Option+Space"
        )
        hotkeyManager.updateHotkey(defaultHotkey)
    }
    
    private func validateHotkey(_ hotkey: HotkeyConfiguration) -> [String] {
        var conflicts: [String] = []
        
        // Check for common system shortcuts
        let systemShortcuts: [(keyCode: UInt16, modifiers: CGEventFlags, description: String)] = [
            (49, .maskCommand, "Command+Space (Spotlight)"),
            (49, [.maskCommand, .maskShift], "Command+Shift+Space (Character Viewer)"),
            (48, .maskCommand, "Command+Tab (App Switcher)"),
            (48, [.maskCommand, .maskShift], "Command+Shift+Tab (App Switcher Reverse)"),
            (12, .maskCommand, "Command+Q (Quit App)"),
            (13, .maskCommand, "Command+W (Close Window)"),
            (35, .maskCommand, "Command+P (Print)"),
            (1, .maskCommand, "Command+S (Save)"),
            (99, .maskCommand, "Command+F3 (Show Desktop)"),
            (96, .maskCommand, "Command+F5 (VoiceOver)"),
            (0, .maskCommand, "Command+A (Select All)"),
            (8, .maskCommand, "Command+C (Copy)"),
            (9, .maskCommand, "Command+V (Paste)"),
            (7, .maskCommand, "Command+X (Cut)"),
            (6, .maskCommand, "Command+Z (Undo)"),
        ]
        
        for systemShortcut in systemShortcuts {
            if hotkey.keyCode == systemShortcut.keyCode && 
               hotkey.modifierFlags == systemShortcut.modifiers {
                conflicts.append(systemShortcut.description)
            }
        }
        
        // Check for modifier-only shortcuts (not allowed)
        if hotkey.keyCode == 0 {
            conflicts.append("Modifier-only shortcuts are not allowed")
        }
        
        return conflicts
    }
    
    private func generateAlternatives(for hotkey: HotkeyConfiguration) -> [HotkeyConfiguration] {
        var alternatives: [HotkeyConfiguration] = []
        
        // Common alternative modifier combinations
        let alternativeModifiers: [CGEventFlags] = [
            .maskAlternate, // Option
            [.maskCommand, .maskAlternate], // Command + Option
            [.maskShift, .maskAlternate], // Shift + Option
            [.maskControl, .maskAlternate], // Control + Option
        ]
        
        for modifiers in alternativeModifiers where modifiers != hotkey.modifierFlags {
            let alternative = HotkeyConfiguration(
                keyCode: hotkey.keyCode,
                modifierFlags: modifiers,
                description: formatHotkeyDescription(keyCode: hotkey.keyCode, modifiers: modifiers)
            )
            
            // Only add if it doesn't have conflicts
            if validateHotkey(alternative).isEmpty {
                alternatives.append(alternative)
            }
        }
        
        return Array(alternatives.prefix(3)) // Limit to 3 suggestions
    }
    
    private func formatHotkeyDescription(keyCode: UInt16, modifiers: CGEventFlags) -> String {
        var parts: [String] = []
        
        if modifiers.contains(.maskControl) { parts.append("Control") }
        if modifiers.contains(.maskAlternate) { parts.append("Option") }
        if modifiers.contains(.maskShift) { parts.append("Shift") }
        if modifiers.contains(.maskCommand) { parts.append("Command") }
        
        // Convert keyCode to character name
        let keyName = keyCodeToString(keyCode)
        parts.append(keyName)
        
        return parts.joined(separator: "+")
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 53: return "Escape"
        case 0...25: return String(Character(UnicodeScalar(keyCode + 97)!)) // a-z
        default: return "Key \(keyCode)"
        }
    }
}

private struct InstructionRow: View {
    let icon: String
    let text: String
    var color: Color = .accentColor
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20, height: 20)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
        }
    }
}

#if DEBUG
struct ShortcutTab_Previews: PreviewProvider {
    static var previews: some View {
        ShortcutTab()
            .frame(width: 600, height: 500)
    }
}
#endif