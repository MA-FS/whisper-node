import SwiftUI
import Sparkle

@main
struct WhisperNodeApp: App {
    @StateObject private var core = WhisperNodeCore.shared
    @StateObject private var updaterManager = UpdaterManager.shared
    @StateObject private var onboardingManager = OnboardingWindowManager.shared
    
    var body: some Scene {
        Settings {
            PreferencesView(updater: updaterManager.updater)
                .environmentObject(core)
                .onAppear {
                    // Check if onboarding is needed before starting core functionality
                    onboardingManager.showOnboardingIfNeeded()
                    
                    // Only start voice activation if onboarding is complete
                    if SettingsManager.shared.hasCompletedOnboarding {
                        if core.isInitialized {
                            core.startVoiceActivation()
                        } else {
                            // Handle initialization error
                            print("Error: Core not initialized")
                            // Show user-facing error notification
                            DispatchQueue.main.async {
                                let alert = NSAlert()
                                alert.messageText = "Whisper Node Failed to Initialize"
                                alert.informativeText = "The application failed to initialize properly. Please restart Whisper Node. If the problem persists, check your system permissions and try again."
                                alert.alertStyle = .critical
                                alert.addButton(withTitle: "OK")
                                alert.runModal()
                            }
                        }
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