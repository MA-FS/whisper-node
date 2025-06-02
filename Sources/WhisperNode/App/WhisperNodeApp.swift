import SwiftUI
import Sparkle

@main
struct WhisperNodeApp: App {
    @StateObject private var core = WhisperNodeCore.shared
    @StateObject private var updaterManager = UpdaterManager.shared
    
    var body: some Scene {
        Settings {
            PreferencesView(updater: updaterManager.updater)
                .environmentObject(core)
                .onAppear {
                    if core.isInitialized {
                        core.startVoiceActivation()
                    } else {
                        // Handle initialization error
                        print("Error: Core not initialized")
                    }
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterManager.updater)
            }
        }
    }
}