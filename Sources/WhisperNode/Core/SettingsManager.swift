import Foundation
import ServiceManagement
import Cocoa
import Carbon
import os.log

/// Manages application settings and preferences using UserDefaults
@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private static let logger = Logger(subsystem: "com.whispernode.core", category: "settings")

    // Performance optimization: Cache validation results to prevent repeated validation
    private let validationCache = NSCache<NSString, NSNumber>()
    private let cacheQueue = DispatchQueue(label: "com.whispernode.settings.cache", attributes: .concurrent)
    
    // MARK: - UserDefaults Keys
    
    private enum UserDefaultsKeys {
        static let launchAtLogin = "launchAtLogin"
        static let showDockIcon = "showDockIcon"
        static let windowPosition = "windowPosition"
        static let windowSize = "windowSize"
        
        // Voice Settings
        static let preferredInputDevice = "preferredInputDevice"
        static let vadThreshold = "vadThreshold"
        static let enableTestRecording = "enableTestRecording"
        
        // Hotkey Settings
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifierFlags = "hotkeyModifierFlags"
        
        // Model Settings
        static let activeModelName = "activeModelName"
        static let autoDownloadUpdates = "autoDownloadUpdates"
        
        // Onboarding Settings
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let onboardingStep = "onboardingStep"
    }
    
    // MARK: - Published Properties
    
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: UserDefaultsKeys.launchAtLogin)
            updateLoginItem()
        }
    }
    
    @Published var showDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: UserDefaultsKeys.showDockIcon)
            updateDockIconVisibility()
        }
    }
    
    @Published var windowPosition: CGPoint {
        didSet {
            UserDefaults.standard.set(NSCoder.string(for: windowPosition), forKey: UserDefaultsKeys.windowPosition)
        }
    }
    
    @Published var windowSize: CGSize {
        didSet {
            UserDefaults.standard.set(NSCoder.string(for: windowSize), forKey: UserDefaultsKeys.windowSize)
        }
    }
    
    @Published var preferredInputDevice: UInt32? {
        didSet {
            if let deviceID = preferredInputDevice {
                // Note: 0 is treated as invalid/default device in Core Audio
                UserDefaults.standard.set(deviceID, forKey: UserDefaultsKeys.preferredInputDevice)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.preferredInputDevice)
            }
        }
    }
    
    @Published var vadThreshold: Float {
        didSet {
            UserDefaults.standard.set(vadThreshold, forKey: UserDefaultsKeys.vadThreshold)
        }
    }
    
    @Published var enableTestRecording: Bool {
        didSet {
            UserDefaults.standard.set(enableTestRecording, forKey: UserDefaultsKeys.enableTestRecording)
        }
    }
    
    @Published var hotkeyKeyCode: UInt16 {
        didSet {
            UserDefaults.standard.set(hotkeyKeyCode, forKey: UserDefaultsKeys.hotkeyKeyCode)
        }
    }
    
    @Published var hotkeyModifierFlags: UInt64 {
        didSet {
            UserDefaults.standard.set(hotkeyModifierFlags, forKey: UserDefaultsKeys.hotkeyModifierFlags)
        }
    }
    
    @Published var activeModelName: String {
        didSet {
            UserDefaults.standard.set(activeModelName, forKey: UserDefaultsKeys.activeModelName)
        }
    }
    
    @Published var autoDownloadUpdates: Bool {
        didSet {
            UserDefaults.standard.set(autoDownloadUpdates, forKey: UserDefaultsKeys.autoDownloadUpdates)
        }
    }
    
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: UserDefaultsKeys.hasCompletedOnboarding)
        }
    }
    
    @Published var onboardingStep: Int {
        didSet {
            UserDefaults.standard.set(onboardingStep, forKey: UserDefaultsKeys.onboardingStep)
        }
    }
    
    // MARK: - Private Properties
    
    private let defaults = UserDefaults.standard
    
    // MARK: - Initialization
    
    private init() {
        // Load settings from UserDefaults
        self.launchAtLogin = defaults.bool(forKey: UserDefaultsKeys.launchAtLogin)
        self.showDockIcon = defaults.bool(forKey: UserDefaultsKeys.showDockIcon)
        
        // Load window position, default to center if not set
        if let positionString = defaults.string(forKey: UserDefaultsKeys.windowPosition),
           let position = NSCoder.cgPoint(for: positionString) {
            self.windowPosition = position
        } else {
            self.windowPosition = CGPoint(x: 100, y: 100)
        }
        
        // Load window size, default to preferences size if not set
        if let sizeString = defaults.string(forKey: UserDefaultsKeys.windowSize),
           let size = NSCoder.cgSize(for: sizeString) {
            self.windowSize = size
        } else {
            self.windowSize = CGSize(width: 480, height: 320)
        }
        
        // Load voice settings
        let storedDeviceID = defaults.object(forKey: UserDefaultsKeys.preferredInputDevice) as? UInt32
        self.preferredInputDevice = storedDeviceID == 0 ? nil : storedDeviceID
        
        self.vadThreshold = defaults.object(forKey: UserDefaultsKeys.vadThreshold) as? Float ?? -40.0
        self.enableTestRecording = defaults.bool(forKey: UserDefaultsKeys.enableTestRecording)
        
        // Load hotkey settings with defaults (Control+Option+Space)
        // Note: keyCode=0 is valid for modifier-only combinations, so check if key exists rather than value
        let hasStoredKeyCode = defaults.object(forKey: UserDefaultsKeys.hotkeyKeyCode) != nil
        let storedKeyCode = UInt16(defaults.integer(forKey: UserDefaultsKeys.hotkeyKeyCode))
        let defaultKeyCode: UInt16 = 49 // Space key
        self.hotkeyKeyCode = hasStoredKeyCode ? storedKeyCode : defaultKeyCode

        let hasStoredModifierFlags = defaults.object(forKey: UserDefaultsKeys.hotkeyModifierFlags) != nil
        let storedModifierFlags = UInt64(defaults.integer(forKey: UserDefaultsKeys.hotkeyModifierFlags))
        let defaultModifierFlags = CGEventFlags([.maskControl, .maskAlternate]).rawValue // Default to Control+Option
        self.hotkeyModifierFlags = hasStoredModifierFlags ? storedModifierFlags : defaultModifierFlags

        // Save defaults to UserDefaults if they weren't already set
        if !hasStoredKeyCode {
            defaults.set(defaultKeyCode, forKey: UserDefaultsKeys.hotkeyKeyCode)
        }
        if !hasStoredModifierFlags {
            defaults.set(defaultModifierFlags, forKey: UserDefaultsKeys.hotkeyModifierFlags)
        }
        
        // Load model settings
        self.activeModelName = defaults.string(forKey: UserDefaultsKeys.activeModelName) ?? "tiny.en"
        self.autoDownloadUpdates = defaults.bool(forKey: UserDefaultsKeys.autoDownloadUpdates)
        
        // Load onboarding settings
        self.hasCompletedOnboarding = defaults.bool(forKey: UserDefaultsKeys.hasCompletedOnboarding)
        self.onboardingStep = defaults.integer(forKey: UserDefaultsKeys.onboardingStep)
    }
    
    // MARK: - Login Item Management
    
    /// Registers or unregisters the app as a login item based on the current `launchAtLogin` setting.
    ///
    /// If registration or unregistration fails, resets the `launchAtLogin` property to reflect the actual system state and posts a `"LoginItemUpdateFailed"` notification with error details.
    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Reset UI state on failure to ensure consistency
            DispatchQueue.main.async {
                self.launchAtLogin = SMAppService.mainApp.status == .enabled
            }
            
            // Post notification for error handling by UI
            NotificationCenter.default.post(
                name: Notification.Name("LoginItemUpdateFailed"),
                object: nil,
                userInfo: ["error": error.localizedDescription]
            )
            
            print("Failed to update login item: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Dock Icon Management
    
    /// Updates the application's dock icon visibility based on the current setting.
    ///
    /// Sets the app's activation policy to show or hide the dock icon and posts a `"DockIconVisibilityChanged"` notification with the updated visibility state.
    private func updateDockIconVisibility() {
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
        
        // Post notification so MenuBarManager can update if needed
        NotificationCenter.default.post(
            name: Notification.Name("DockIconVisibilityChanged"),
            object: nil,
            userInfo: ["showDockIcon": showDockIcon]
        )
    }
    
    // MARK: - Window Management
    
    /// Saves the specified window frame's origin and size to persistent settings.
    ///
    /// - Parameter frame: The window frame whose position and size should be stored.
    func saveWindowFrame(_ frame: CGRect) {
        windowPosition = frame.origin
        windowSize = frame.size
    }
    
    /// Returns a validated window frame using the stored window position and size.
    ///
    /// The returned frame is adjusted to ensure it fits within the visible area of the main screen and adheres to minimum and maximum size constraints.
    ///
    /// - Returns: A CGRect representing the validated window frame.
    func restoreWindowFrame() -> CGRect {
        let frame = CGRect(origin: windowPosition, size: windowSize)
        return validateWindowFrame(frame)
    }
    
    /// Resets onboarding state to allow re-running the onboarding flow
    ///
    /// This method clears the onboarding completion flag and resets the step counter,
    /// which will cause the onboarding flow to be presented again on next app launch.
    /// Useful for testing or when users want to reconfigure their setup.
    func resetOnboarding() {
        hasCompletedOnboarding = false
        onboardingStep = 0
    }
    
    /// Validates and adjusts a window frame to ensure it fits within the main screen's visible area.
    ///
    /// The returned frame is constrained to a minimum size of 320x240 points, a maximum size of 90% of the screen's visible area, and is repositioned if necessary to prevent it from being off-screen.
    ///
    /// - Parameter frame: The window frame to validate.
    /// - Returns: A frame adjusted to fit within the visible bounds of the main screen.
    private func validateWindowFrame(_ frame: CGRect) -> CGRect {
        guard let screen = NSScreen.main else {
            return frame
        }
        
        var validatedFrame = frame
        let screenFrame = screen.visibleFrame
        
        // Ensure minimum window size
        let minSize = CGSize(width: 320, height: 240)
        if validatedFrame.size.width < minSize.width {
            validatedFrame.size.width = minSize.width
        }
        if validatedFrame.size.height < minSize.height {
            validatedFrame.size.height = minSize.height
        }
        
        // Ensure window is not larger than screen
        if validatedFrame.size.width > screenFrame.size.width {
            validatedFrame.size.width = screenFrame.size.width * 0.9
        }
        if validatedFrame.size.height > screenFrame.size.height {
            validatedFrame.size.height = screenFrame.size.height * 0.9
        }
        
        // Ensure window is not positioned off-screen
        if validatedFrame.origin.x < screenFrame.origin.x {
            validatedFrame.origin.x = screenFrame.origin.x + 20
        }
        if validatedFrame.origin.y < screenFrame.origin.y {
            validatedFrame.origin.y = screenFrame.origin.y + 20
        }
        
        // Ensure window is not positioned too far right or bottom
        let maxX = screenFrame.maxX - validatedFrame.size.width - 20
        let maxY = screenFrame.maxY - validatedFrame.size.height - 20
        
        if validatedFrame.origin.x > maxX {
            validatedFrame.origin.x = max(screenFrame.origin.x + 20, maxX)
        }
        if validatedFrame.origin.y > maxY {
            validatedFrame.origin.y = max(screenFrame.origin.y + 20, maxY)
        }
        
        return validatedFrame
    }

    // MARK: - Enhanced Hotkey Persistence (T29h)

    /// Loads hotkey configuration with comprehensive validation and error handling
    ///
    /// Provides robust loading of hotkey settings with validation, fallback mechanisms,
    /// and detailed logging for debugging persistence issues.
    ///
    /// - Returns: A validated hotkey configuration, or default if loading fails
    func loadHotkeyConfiguration() -> HotkeyConfiguration {
        Self.logger.info("🔄 Loading hotkey configuration from UserDefaults")

        let defaults = UserDefaults.standard

        // Check if settings exist
        let hasStoredKeyCode = defaults.object(forKey: UserDefaultsKeys.hotkeyKeyCode) != nil
        let hasStoredModifierFlags = defaults.object(forKey: UserDefaultsKeys.hotkeyModifierFlags) != nil

        if !hasStoredKeyCode || !hasStoredModifierFlags {
            Self.logger.info("📋 No stored hotkey configuration found, using default")
            let defaultConfig = HotkeyConfiguration.defaultConfiguration
            saveHotkeyConfiguration(defaultConfig)
            return defaultConfig
        }

        // Load stored values
        let storedKeyCode = UInt16(defaults.integer(forKey: UserDefaultsKeys.hotkeyKeyCode))
        let storedModifierFlags = CGEventFlags(rawValue: UInt64(defaults.integer(forKey: UserDefaultsKeys.hotkeyModifierFlags)))

        // Create configuration from stored values and sanitize for consistency
        let loadedConfig = HotkeyConfiguration(
            keyCode: storedKeyCode,
            modifierFlags: storedModifierFlags,
            description: "" // Will be regenerated by sanitizedForPersistence
        ).sanitizedForPersistence

        // Validate loaded configuration with caching
        loadedConfig.logValidationResults()

        if !isConfigurationValid(loadedConfig) {
            Self.logger.warning("⚠️ Loaded hotkey configuration is invalid, using default")
            let defaultConfig = HotkeyConfiguration.defaultConfiguration
            saveHotkeyConfiguration(defaultConfig)
            return defaultConfig
        }

        // Check if configuration can be persisted (data integrity)
        if !loadedConfig.canBePersisted {
            Self.logger.warning("⚠️ Loaded hotkey configuration has persistence issues, using sanitized version")
            let sanitizedConfig = loadedConfig.sanitizedForPersistence
            saveHotkeyConfiguration(sanitizedConfig)
            return sanitizedConfig
        }

        Self.logger.info("✅ Successfully loaded hotkey configuration: \(loadedConfig.description)")
        return loadedConfig
    }

    /// Saves hotkey configuration with validation and integrity checks
    ///
    /// Provides safe saving of hotkey settings with validation, error handling,
    /// and rollback capabilities for failed saves.
    ///
    /// - Parameter configuration: The hotkey configuration to save
    /// - Returns: True if save was successful, false otherwise
    @discardableResult
    func saveHotkeyConfiguration(_ configuration: HotkeyConfiguration) -> Bool {
        Self.logger.info("💾 Saving hotkey configuration: \(configuration.description)")

        // Validate configuration before saving
        configuration.logValidationResults()

        if !configuration.canBePersisted {
            Self.logger.error("❌ Cannot save hotkey configuration: persistence validation failed")
            return false
        }

        // Use sanitized version for persistence
        let configToSave = configuration.sanitizedForPersistence

        let defaults = UserDefaults.standard

        // Store the configuration
        defaults.set(configToSave.keyCode, forKey: UserDefaultsKeys.hotkeyKeyCode)
        defaults.set(configToSave.modifierFlags.rawValue, forKey: UserDefaultsKeys.hotkeyModifierFlags)

        // Store additional metadata for validation and debugging
        defaults.set(configToSave.isModifierOnly, forKey: "hotkeyIsModifierOnly")
        defaults.set(configToSave.description, forKey: "hotkeyDescription")
        defaults.set(Date().timeIntervalSince1970, forKey: "hotkeyLastSaved")

        // Force synchronization
        defaults.synchronize()

        // Verify the save by reading back
        let verificationKeyCode = UInt16(defaults.integer(forKey: UserDefaultsKeys.hotkeyKeyCode))
        let verificationModifierFlags = UInt64(defaults.integer(forKey: UserDefaultsKeys.hotkeyModifierFlags))

        if verificationKeyCode != configToSave.keyCode || verificationModifierFlags != configToSave.modifierFlags.rawValue {
            Self.logger.error("❌ Hotkey configuration save verification failed")
            return false
        }

        Self.logger.info("✅ Successfully saved hotkey configuration")
        return true
    }

    /// Validates the integrity of stored hotkey settings
    ///
    /// Checks for data corruption, inconsistencies, or invalid values in stored settings.
    ///
    /// - Returns: True if stored settings are valid, false if issues are detected
    func validateStoredHotkeySettings() -> Bool {
        Self.logger.info("🔍 Validating stored hotkey settings integrity")

        let defaults = UserDefaults.standard

        // Check if required keys exist
        guard defaults.object(forKey: UserDefaultsKeys.hotkeyKeyCode) != nil,
              defaults.object(forKey: UserDefaultsKeys.hotkeyModifierFlags) != nil else {
            Self.logger.warning("⚠️ Missing required hotkey settings keys")
            return false
        }

        // Load and validate configuration
        let storedKeyCode = UInt16(defaults.integer(forKey: UserDefaultsKeys.hotkeyKeyCode))
        let storedModifierFlags = CGEventFlags(rawValue: UInt64(defaults.integer(forKey: UserDefaultsKeys.hotkeyModifierFlags)))

        // Check for obviously invalid values
        if storedKeyCode > 127 && storedKeyCode != UInt16.max {
            Self.logger.warning("⚠️ Invalid key code in stored settings: \(storedKeyCode)")
            return false
        }

        // Validate modifier flags
        if storedModifierFlags.rawValue == 0 && storedKeyCode == UInt16.max {
            Self.logger.warning("⚠️ Modifier-only hotkey with no modifiers")
            return false
        }

        // Cross-validate with metadata if available
        if let storedIsModifierOnly = defaults.object(forKey: "hotkeyIsModifierOnly") as? Bool {
            let actualIsModifierOnly = (storedKeyCode == UInt16.max)
            if storedIsModifierOnly != actualIsModifierOnly {
                Self.logger.warning("⚠️ Hotkey metadata inconsistency detected")
                return false
            }
        }

        Self.logger.info("✅ Stored hotkey settings validation passed")
        return true
    }

    /// Migrates hotkey settings to current format if needed
    ///
    /// Handles migration from older settings formats to ensure compatibility
    /// across application updates.
    func migrateHotkeySettingsIfNeeded() {
        Self.logger.info("🔄 Checking for hotkey settings migration needs")

        let defaults = UserDefaults.standard
        let currentVersion = 1 // Current settings format version
        let storedVersion = defaults.integer(forKey: "hotkeySettingsVersion")

        if storedVersion == 0 {
            // First time setup or very old version
            Self.logger.info("📦 Performing initial hotkey settings setup")

            // Ensure default configuration is saved
            if !validateStoredHotkeySettings() {
                let defaultConfig = HotkeyConfiguration.defaultConfiguration
                saveHotkeyConfiguration(defaultConfig)
            }

            defaults.set(currentVersion, forKey: "hotkeySettingsVersion")
            Self.logger.info("✅ Hotkey settings migration completed")
        } else if storedVersion < currentVersion {
            Self.logger.info("📦 Migrating hotkey settings from version \(storedVersion) to \(currentVersion)")

            // Future migration logic would go here

            defaults.set(currentVersion, forKey: "hotkeySettingsVersion")
            Self.logger.info("✅ Hotkey settings migration completed")
        } else {
            Self.logger.info("✅ Hotkey settings are up to date (version \(storedVersion))")
        }
    }

    // MARK: - Performance Optimization Helpers

    /// Checks if a configuration is valid using caching for performance
    private func isConfigurationValid(_ configuration: HotkeyConfiguration) -> Bool {
        let cacheKey = NSString(string: "\(configuration.keyCode)-\(configuration.modifierFlags.rawValue)")

        if let cachedResult = validationCache.object(forKey: cacheKey) {
            return cachedResult.boolValue
        }

        let isValid = configuration.isValid
        validationCache.setObject(NSNumber(value: isValid), forKey: cacheKey)

        return isValid
    }

    /// Clears the validation cache (useful for testing or memory management)
    func clearValidationCache() {
        validationCache.removeAllObjects()
    }


}

// MARK: - NSCoder Extensions

private extension NSCoder {
    /// Converts a `CGPoint` to its string representation suitable for storage or serialization.
    ///
    /// - Parameter point: The point to convert.
    /// - Returns: A string representation of the given point.
    static func string(for point: CGPoint) -> String {
        return NSStringFromPoint(point)
    }
    
    /// Converts a string representation to a `CGPoint`.
    ///
    /// - Parameter string: The string to convert, typically produced by `NSStringFromPoint`.
    /// - Returns: A `CGPoint` if the string is valid; otherwise, `nil`.
    static func cgPoint(for string: String) -> CGPoint? {
        return NSPointFromString(string)
    }
    
    /// Converts a `CGSize` value to its string representation.
    ///
    /// - Parameter size: The size to convert.
    /// - Returns: A string representation of the given size.
    static func string(for size: CGSize) -> String {
        return NSStringFromSize(size)
    }
    
    /// Converts a string representation to a `CGSize` value.
    ///
    /// - Parameter string: The string to convert, typically produced by `NSStringFromSize`.
    /// - Returns: A `CGSize` if the string is valid; otherwise, `nil`.
    static func cgSize(for string: String) -> CGSize? {
        return NSSizeFromString(string)
    }
}