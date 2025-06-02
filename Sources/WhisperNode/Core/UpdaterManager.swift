import Foundation
import Sparkle

/// Manages the Sparkle updater instance across the application
@MainActor
class UpdaterManager: ObservableObject {
    static let shared = UpdaterManager()
    
    private let updaterController: SPUStandardUpdaterController
    
    /// The main Sparkle updater instance
    var updater: SPUUpdater {
        return updaterController.updater
    }
    
    private init() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
}