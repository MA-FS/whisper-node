import SwiftUI
import Sparkle

struct PreferencesView: View {
    let updater: SPUUpdater?
    
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag("general")
            
            VoiceTab()
                .tabItem {
                    Label("Voice", systemImage: "mic")
                }
                .tag("voice")
            
            ModelsTab()
                .tabItem {
                    Label("Models", systemImage: "brain.head.profile")
                }
                .tag("models")
            
            ShortcutTab()
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
                }
                .tag("shortcuts")
            
            AboutTab(updater: updater)
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag("about")
        }
        .frame(width: 480, height: 320)
        .background(Color(.windowBackgroundColor))
    }
}

#Preview {
    PreferencesView(updater: nil)
}