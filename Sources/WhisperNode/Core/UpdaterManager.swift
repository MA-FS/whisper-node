import Foundation
import Sparkle

/// Manages the Sparkle updater instance across the application
///
/// This singleton provides centralized access to the Sparkle updater controller,
/// ensuring consistent update functionality throughout the app. The updater is
/// configured for automatic weekly checks with EdDSA signature verification.
@MainActor
class UpdaterManager: ObservableObject {
    static var shared = UpdaterManager()
    
    private let updaterController: SPUStandardUpdaterController
    
    /// The main Sparkle updater instance
    /// 
    /// This provides access to the underlying SPUUpdater for performing update checks
    /// and managing update-related UI interactions. The updater is automatically
    /// configured based on the app's Info.plist settings.
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
    
    #if DEBUG
    /// Allow dependency injection for testing scenarios
    /// 
    /// This method is only available in debug builds to enable testing
    /// with mock updater instances without affecting release builds.
    ///
    /// - Parameter manager: The UpdaterManager instance to use for testing
    static func setSharedForTesting(_ manager: UpdaterManager) {
        shared = manager
    }
    #endif
}