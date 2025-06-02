import SwiftUI
import Sparkle

@main
struct WhisperNodeApp: App {
    private let updaterController: SPUStandardUpdaterController
    @StateObject private var core = WhisperNodeCore.shared
    
    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
    
    var body: some Scene {
        Settings {
            PreferencesView()
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
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}