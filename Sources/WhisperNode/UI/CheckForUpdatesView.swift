import SwiftUI
import Sparkle

struct CheckForUpdatesView: View {
    private let updater: SPUUpdater
    
    init(updater: SPUUpdater) {
        self.updater = updater
    }
    
    var body: some View {
        Button("Check for Updates...") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
        .accessibilityLabel("Check for application updates")
        .accessibilityHint("Downloads and installs any available updates for Whisper Node")
    }
}