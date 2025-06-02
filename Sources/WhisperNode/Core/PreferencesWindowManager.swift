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
    
    /// Displays the preferences window, creating it if necessary.
    ///
    /// If the preferences window already exists, it is brought to the front and the application is activated. Otherwise, a new preferences window is created and shown.
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
    
    /// Closes the preferences window if it is currently open.
    func closePreferences() {
        preferencesWindow?.close()
        Self.logger.info("Preferences window closed")
    }
    
    /// Cleans up references to the preferences window and its delegate when the window is closing.
    func windowWillClose() {
        preferencesWindow = nil
        windowDelegate = nil
    }
    
    // MARK: - Private Methods
    
    /// Creates and displays the preferences window with the appropriate content and configuration.
    ///
    /// Initializes a new preferences window containing the SwiftUI `PreferencesView`, restores its previous size and position if available, sets window properties, assigns a delegate for window events, and brings the window to the front.
    private func createPreferencesWindow() {
        // Create the SwiftUI content view
        let contentView = PreferencesView(updater: UpdaterManager.shared.updater)
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
    
    /// Handles the preferences window closing event by saving its frame and notifying the manager to clear references.
    ///
    /// - Parameter notification: The notification containing the window that is closing.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        // Save window frame
        manager?.settings.saveWindowFrame(window.frame)
        
        // Clear the window references
        manager?.windowWillClose()
        
        PreferencesWindowManager.logger.debug("Preferences window will close")
    }
    
    /// Saves the window frame to settings when the preferences window is resized.
    ///
    /// - Parameter notification: The notification containing the window that was resized.
    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        // Save window frame on resize
        manager?.settings.saveWindowFrame(window.frame)
    }
    
    /// Saves the window frame to settings when the preferences window is moved.
    ///
    /// - Parameter notification: The notification containing the window that was moved.
    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        // Save window frame on move
        manager?.settings.saveWindowFrame(window.frame)
    }
}