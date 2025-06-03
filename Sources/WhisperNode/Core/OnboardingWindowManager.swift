import SwiftUI
import Cocoa
import OSLog

/// Manages the onboarding window lifecycle
///
/// Handles presentation and dismissal of the first-run onboarding flow window.
/// Ensures the onboarding window is presented when needed and properly cleaned up.
@MainActor
class OnboardingWindowManager: ObservableObject {
    static let shared = OnboardingWindowManager()
    
    private static let logger = Logger(subsystem: "com.whispernode.onboarding", category: "window")
    
    @Published private(set) var isOnboardingPresented = false
    private var onboardingWindow: NSWindow?
    private var windowDelegate: OnboardingWindowDelegate?
    
    private init() {}
    
    /// Shows the onboarding window if onboarding hasn't been completed
    func showOnboardingIfNeeded() {
        let settings = SettingsManager.shared
        
        if !settings.hasCompletedOnboarding {
            showOnboarding()
        }
    }
    
    /// Forces the onboarding window to be shown (useful for testing or re-onboarding)
    func showOnboarding() {
        guard onboardingWindow == nil else {
            // Window is already shown, bring it to front
            if let window = onboardingWindow {
                window.makeKeyAndOrderFront(nil)
            }
            return
        }
        
        let onboardingView = OnboardingFlow()
            .environmentObject(SettingsManager.shared)
            .environmentObject(WhisperNodeCore.shared)
        
        let hostingController = NSHostingController(rootView: onboardingView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.contentViewController = hostingController
        window.title = "Welcome to Whisper Node"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("OnboardingWindow")
        
        // Allow window to be closed (users can cancel onboarding)
        window.standardWindowButton(.closeButton)?.isHidden = false
        
        // Set up window delegate to handle cleanup
        windowDelegate = OnboardingWindowDelegate { [weak self] in
            self?.hideOnboarding()
        }
        window.delegate = windowDelegate
        
        onboardingWindow = window
        isOnboardingPresented = true
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        Self.logger.info("Onboarding window presented")
    }
    
    /// Hides the onboarding window
    func hideOnboarding() {
        guard let window = onboardingWindow else {
            Self.logger.warning("Attempted to hide onboarding window that was already nil")
            return
        }
        
        window.close()
        onboardingWindow = nil
        windowDelegate = nil
        isOnboardingPresented = false
        
        // Now that onboarding is complete, start the core functionality
        let core = WhisperNodeCore.shared
        if core.isInitialized {
            core.startVoiceActivation()
        }
        
        Self.logger.info("Onboarding window dismissed")
    }
}

// MARK: - Window Delegate

private class OnboardingWindowDelegate: NSObject, NSWindowDelegate {
    private let onWindowClosed: () -> Void
    
    init(onWindowClosed: @escaping () -> Void) {
        self.onWindowClosed = onWindowClosed
        super.init()
    }
    
    func windowWillClose(_ notification: Notification) {
        onWindowClosed()
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Allow users to close the window even if onboarding isn't complete
        // This respects user choice and follows macOS HIG guidelines
        return true
    }
}