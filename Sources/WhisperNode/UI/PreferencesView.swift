import SwiftUI

struct PreferencesView: View {
    @StateObject private var settings = SettingsManager.shared
    
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag("general")
            
            // Placeholder tabs for future implementation
            VStack {
                Text("Voice Settings")
                    .font(.title2)
                Text("Coming soon...")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.windowBackgroundColor))
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
            
            VStack {
                Text("Shortcuts")
                    .font(.title2)
                Text("Coming soon...")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.windowBackgroundColor))
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