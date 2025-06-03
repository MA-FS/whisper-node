import SwiftUI
import Sparkle

struct PreferencesView: View {
    let updater: SPUUpdater?
    @State private var selectedTab: String = "general"
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
    }
    
    // MARK: - Dynamic Text Support
    
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
            return min(800, 600)
        @unknown default:
            return 480
        }
    }
    
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
            return min(600, 480)
        @unknown default:
            return 320
        }
    }
    
    // MARK: - Keyboard Navigation
    
    private func setupKeyboardNavigation() {
        // Note: TabView in SwiftUI already provides built-in keyboard navigation:
        // - Cmd+1-5 to switch between tabs
        // - Tab/Shift+Tab to navigate through controls within tabs
        // - Space/Enter to activate buttons
        // - Arrow keys for navigation in lists/pickers
        
        // Additional accessibility announcement for screen readers
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSAccessibility.post(
                element: NSApp.mainWindow as Any,
                notification: .announcementRequested,
                userInfo: [.announcement: "Preferences window opened. Use Command+1 through Command+5 to switch between tabs."]
            )
        }
    }
}

#Preview {
    PreferencesView(updater: nil)
}