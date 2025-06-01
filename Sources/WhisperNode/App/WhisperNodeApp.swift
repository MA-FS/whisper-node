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
        
        // Start voice activation when app launches
        DispatchQueue.main.async {
            if WhisperNodeCore.shared.isInitialized {
                WhisperNodeCore.shared.startVoiceActivation()
            }
        }
    }
    
    var body: some Scene {
        Settings {
            PreferencesView()
                .environmentObject(core)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}