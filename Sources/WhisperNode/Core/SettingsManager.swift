import Foundation
import ServiceManagement
import Cocoa

/// Manages application settings and preferences using UserDefaults
@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
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