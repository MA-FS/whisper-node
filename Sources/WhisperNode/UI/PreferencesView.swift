import SwiftUI

struct PreferencesView: View {
    
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
            
            VStack {
                Text("Models")
                    .font(.title2)
                Text("Coming soon...")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.windowBackgroundColor))
            .tabItem {
                Label("Models", systemImage: "brain.head.profile")
            }
            .tag("models")
            
            ShortcutTab()
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
                }
                .tag("shortcuts")
            
            VStack {
                Text("About")
                    .font(.title2)
                Text("Coming soon...")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.windowBackgroundColor))
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
    PreferencesView()
}