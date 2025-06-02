import Foundation
import ServiceManagement
import Cocoa

/// Manages application settings and preferences using UserDefaults
@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    // MARK: - Published Properties
    
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLoginItem()
        }
    }
    
    @Published var showDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon")
            updateDockIconVisibility()
        }
    }
    
    @Published var windowPosition: CGPoint {
        didSet {
            UserDefaults.standard.set(NSCoder.string(for: windowPosition), forKey: "windowPosition")
        }
    }
    
    @Published var windowSize: CGSize {
        didSet {
            UserDefaults.standard.set(NSCoder.string(for: windowSize), forKey: "windowSize")
        }
    }
    
    // MARK: - Private Properties
    
    private let defaults = UserDefaults.standard
    
    // MARK: - Initialization
    
    private init() {
        // Load settings from UserDefaults
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.showDockIcon = defaults.bool(forKey: "showDockIcon")
        
        // Load window position, default to center if not set
        if let positionString = defaults.string(forKey: "windowPosition"),
           let position = NSCoder.cgPoint(for: positionString) {
            self.windowPosition = position
        } else {
            self.windowPosition = CGPoint(x: 100, y: 100)
        }
        
        // Load window size, default to preferences size if not set
        if let sizeString = defaults.string(forKey: "windowSize"),
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
            print("Failed to update login item: \(error)")
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
        return CGRect(origin: windowPosition, size: windowSize)
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