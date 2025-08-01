import SwiftUI
import Carbon

/// Preferences tab for configuring global hotkey shortcuts
struct ShortcutTab: View {
    @ObservedObject private var hotkeyManager = GlobalHotkeyManager.shared
    @ObservedObject private var permissionHelper = PermissionHelper.shared
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
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 6) {
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
                .padding(.top, 16)

                Divider()

                // Permission Status Banner
                if !permissionHelper.hasAccessibilityPermission {
                    PermissionBanner()
                        .padding(.horizontal, 20)

                    Divider()
                }

                // Current Hotkey Section
                VStack(spacing: 12) {
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
                VStack(spacing: 10) {
                    HStack {
                        Text("Instructions")
                            .font(.headline)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 6) {
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
                .padding(.bottom, 16)
            }
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
            Text("This will reset the hotkey to Control+Option+Space. Are you sure?")
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
            modifierFlags: [.maskControl, .maskAlternate], // Control+Option
            description: "⌃⌥Space"
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
        
        // Allow modifier-only shortcuts (like Control+Option)
        // These are valid hotkey combinations for WhisperNode
        
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
        return HotkeyUtilities.formatTextHotkeyDescription(keyCode: keyCode, modifiers: modifiers)
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        return HotkeyUtilities.keyCodeToString(keyCode)
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

private struct PermissionBanner: View {
    @ObservedObject private var permissionHelper = PermissionHelper.shared

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundColor(.orange)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility Permissions Required")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text("WhisperNode needs accessibility permissions to capture global hotkeys")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                Button("Grant Permissions") {
                    permissionHelper.showPermissionGuidance()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Check Again") {
                    permissionHelper.refreshPermissionStatus()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Help") {
                    permissionHelper.showPermissionHelp()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
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