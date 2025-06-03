import SwiftUI
import Sparkle

struct PreferencesView: View {
    let updater: SPUUpdater?
    @State private var selectedTab: String = "general"
    @State private var keyEventMonitor: Any?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag("general")
                .accessibilityLabel("General preferences")
                .accessibilityHint("Configure general application settings")
            
            VoiceTab()
                .tabItem {
                    Label("Voice", systemImage: "mic")
                }
                .tag("voice")
                .accessibilityLabel("Voice preferences")
                .accessibilityHint("Configure voice recognition and audio settings")
            
            ModelsTab()
                .tabItem {
                    Label("Models", systemImage: "brain.head.profile")
                }
                .tag("models")
                .accessibilityLabel("Models preferences")
                .accessibilityHint("Manage and download transcription models")
            
            ShortcutTab()
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
                }
                .tag("shortcuts")
                .accessibilityLabel("Shortcuts preferences")
                .accessibilityHint("Configure keyboard shortcuts and hotkeys")
            
            AboutTab(updater: updater)
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag("about")
                .accessibilityLabel("About")
                .accessibilityHint("View application information and check for updates")
        }
        .frame(width: dynamicFrameWidth, height: dynamicFrameHeight)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            setupKeyboardNavigation()
        }
        .onDisappear {
            // Clean up key event monitor to prevent memory leaks
            if let monitor = keyEventMonitor {
                NSEvent.removeMonitor(monitor)
                keyEventMonitor = nil
            }
        }
    }
    
    // MARK: - Dynamic Text Support
    
    /// Calculates adaptive frame width based on the user's dynamic text size preference.
    /// 
    /// Ensures the preferences window provides adequate space for larger text sizes and
    /// accessibility text categories, preventing content from being truncated or cramped.
    /// 
    /// - Returns: CGFloat width value ranging from 480pt (standard) to 640pt (accessibility)
    private var dynamicFrameWidth: CGFloat {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium:
            return 480
        case .large, .xLarge:
            return 520
        case .xxLarge:
            return 560
        case .xxxLarge:
            return 600
        case .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5:
            return 640  // Maximum reasonable width for accessibility
        @unknown default:
            return 480
        }
    }
    
    /// Calculates adaptive frame height based on the user's dynamic text size preference.
    /// 
    /// Adjusts the preferences window height to accommodate larger text and ensure all
    /// controls remain visible and accessible for users with accessibility text sizes.
    /// 
    /// - Returns: CGFloat height value ranging from 320pt (standard) to 480pt (accessibility)
    private var dynamicFrameHeight: CGFloat {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium:
            return 320
        case .large, .xLarge:
            return 360
        case .xxLarge:
            return 400
        case .xxxLarge:
            return 440
        case .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5:
            return 480  // Maximum reasonable height for accessibility
        @unknown default:
            return 320
        }
    }
    
    // MARK: - Keyboard Navigation
    
    /// Sets up comprehensive keyboard navigation for the preferences window.
    /// 
    /// Implements accessibility-compliant keyboard shortcuts and navigation patterns:
    /// - Command+1-5: Quick tab switching for all preference categories
    /// - Escape: Closes the preferences window
    /// - VoiceOver announcements: Informs screen reader users of available shortcuts
    /// 
    /// This implementation follows macOS Human Interface Guidelines for keyboard navigation
    /// and ensures users who rely on keyboard-only interaction can fully use the preferences.
    private func setupKeyboardNavigation() {
        // Remove existing monitor if present
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        // Set up key event monitoring for enhanced navigation
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 53: // Escape key
                NSApp.mainWindow?.close()
                return nil
            case 18...22: // Number keys 1-5 for tab switching
                if event.modifierFlags.contains(.command) {
                    let tabIndex = event.keyCode - 18
                    let tabs = ["general", "voice", "models", "shortcuts", "about"]
                    if tabIndex < tabs.count {
                        selectedTab = tabs[Int(tabIndex)]
                    }
                    return nil
                }
            default:
                break
            }
            return event
        }
        
        // Additional accessibility announcement for screen readers
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSAccessibility.post(
                element: NSApp.mainWindow as Any,
                notification: .announcementRequested,
                userInfo: [.announcement: "Preferences window opened. Use Command+1 through Command+5 to switch between tabs, or press Escape to close."]
            )
        }
    }
}

#Preview {
    PreferencesView(updater: nil)
}