import Cocoa
import SwiftUI
import OSLog

/// Manages the preferences window for Whisper Node
@MainActor
class PreferencesWindowManager: ObservableObject {
    
    // MARK: - Logger
    
    static let logger = Logger(subsystem: "com.whispernode.app", category: "PreferencesWindowManager")
    
    // MARK: - Properties
    
    private var preferencesWindow: NSWindow?
    private var windowDelegate: WindowDelegate?
    let settings = SettingsManager.shared
    
    // MARK: - Singleton
    
    static let shared = PreferencesWindowManager()
    
    private init() {}
    
    // MARK: - Public Interface
    
    /// Show the preferences window, creating it if necessary
    func showPreferences() {
        if let window = preferencesWindow {
            // Window exists, bring it to front
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // Create new window
            createPreferencesWindow()
        }
        
        Self.logger.info("Preferences window shown")
    }
    
    /// Close the preferences window
    func closePreferences() {
        preferencesWindow?.close()
        Self.logger.info("Preferences window closed")
    }
    
    /// Clean up window references (called by window delegate)
    func windowWillClose() {
        preferencesWindow = nil
        windowDelegate = nil
    }
    
    // MARK: - Private Methods
    
    private func createPreferencesWindow() {
        // Create the SwiftUI content view
        let contentView = PreferencesView()
            .environmentObject(settings)
        
        // Create the window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        // Configure window properties
        window.title = "Whisper Node Preferences"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.setFrameAutosaveName("PreferencesWindow")
        window.isReleasedWhenClosed = false
        window.level = .floating
        
        // Restore window frame if available
        let savedFrame = settings.restoreWindowFrame()
        if savedFrame.size.width > 0 && savedFrame.size.height > 0 {
            window.setFrame(savedFrame, display: true)
        }
        
        // Set delegate for window events
        windowDelegate = WindowDelegate(manager: self)
        window.delegate = windowDelegate
        
        // Store reference and show
        preferencesWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        Self.logger.info("Preferences window created and shown")
    }
}

// MARK: - Window Delegate

private class WindowDelegate: NSObject, NSWindowDelegate {
    private weak var manager: PreferencesWindowManager?
    
    init(manager: PreferencesWindowManager) {
        self.manager = manager
        super.init()
    }
    
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        // Save window frame
        manager?.settings.saveWindowFrame(window.frame)
        
        // Clear the window references
        manager?.windowWillClose()
        
        PreferencesWindowManager.logger.debug("Preferences window will close")
    }
    
    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        // Save window frame on resize
        manager?.settings.saveWindowFrame(window.frame)
    }
    
    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        // Save window frame on move
        manager?.settings.saveWindowFrame(window.frame)
    }
}