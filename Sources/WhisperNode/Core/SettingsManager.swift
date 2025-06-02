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
    }
    
    // MARK: - Login Item Management
    
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
    
    func saveWindowFrame(_ frame: CGRect) {
        windowPosition = frame.origin
        windowSize = frame.size
    }
    
    func restoreWindowFrame() -> CGRect {
        let frame = CGRect(origin: windowPosition, size: windowSize)
        return validateWindowFrame(frame)
    }
    
    /// Validates and adjusts window frame to ensure it's visible on screen
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
    static func string(for point: CGPoint) -> String {
        return NSStringFromPoint(point)
    }
    
    static func cgPoint(for string: String) -> CGPoint? {
        return NSPointFromString(string)
    }
    
    static func string(for size: CGSize) -> String {
        return NSStringFromSize(size)
    }
    
    static func cgSize(for string: String) -> CGSize? {
        return NSSizeFromString(string)
    }
}