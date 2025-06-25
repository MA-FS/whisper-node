import SwiftUI
import AppKit

/// Manages floating window for recording indicator overlay
///
/// Creates and manages a transparent, non-interactive window that displays
/// the recording indicator as a floating overlay above all other windows.
///
/// ## Features
/// - Transparent floating window above all content
/// - Non-interactive overlay (clicks pass through)
/// - Automatic screen positioning and updates
/// - Memory efficient window lifecycle management
///
/// ## Usage
/// ```swift
/// let manager = RecordingIndicatorWindowManager()
/// manager.showIndicator(state: .recording, progress: 0.0)
/// manager.hideIndicator()
/// ```
@MainActor
public class RecordingIndicatorWindowManager: ObservableObject {
    private var indicatorWindow: NSWindow?
    private var hostingController: NSHostingController<RecordingIndicatorView>?
    private var screenChangeObserver: NSObjectProtocol?
    
    @Published public var isVisible: Bool = false
    @Published public var currentState: RecordingState = .idle
    @Published public var currentProgress: Double = 0.0
    
    public init() {}
    
    deinit {
        // Close window immediately in deinit
        if let window = indicatorWindow {
            window.close()
        }
    }
    
    // MARK: - Public Interface
    
    /// Show the recording indicator with specified state
    ///
    /// Creates and displays the floating indicator window if not already visible.
    /// Updates the indicator state and begins appropriate animations.
    ///
    /// - Parameters:
    ///   - state: The recording state to display
    ///   - progress: Progress value for processing state (0.0-1.0)
    ///
    /// ## Window Behavior
    /// - Window appears above all other content
    /// - Positioned at bottom-right of main screen
    /// - Automatically updates on screen changes
    /// - Clicks pass through to underlying windows
    ///
    /// - Important: Safe to call multiple times - reuses existing window
    /// - Note: Window creation is performed on main thread
    public func showIndicator(state: RecordingState, progress: Double = 0.0) {
        currentState = state
        currentProgress = progress
        
        if indicatorWindow == nil {
            setupIndicatorWindow()
        }
        
        updateIndicatorVisibility(true)
    }
    
    /// Hide the recording indicator
    ///
    /// Smoothly hides the indicator window with fade-out animation.
    /// Window is kept in memory for quick re-display.
    ///
    /// ## Performance
    /// - Window remains in memory for performance
    /// - Use `cleanup()` for full memory deallocation
    /// - Animation respects accessibility settings
    ///
    /// - Note: Safe to call when indicator is already hidden
    public func hideIndicator() {
        updateIndicatorVisibility(false)
    }
    
    /// Update indicator state without changing visibility
    ///
    /// Updates the visual state and progress of the currently displayed indicator.
    /// No effect if indicator is not currently visible.
    ///
    /// - Parameters:
    ///   - state: New recording state
    ///   - progress: New progress value (0.0-1.0)
    ///
    /// ## State Transitions
    /// - Smooth animated transitions between states
    /// - Progress updates trigger ring animation
    /// - Color and opacity changes respect theme
    ///
    /// - Important: Only affects visible indicators
    /// - Note: Progress is only relevant for `.processing` state
    public func updateState(_ state: RecordingState, progress: Double = 0.0) {
        guard isVisible else { return }
        
        currentState = state
        currentProgress = progress
    }
    
    /// Force cleanup and window disposal
    ///
    /// Immediately closes and deallocates the indicator window.
    /// Use when indicator will not be needed for extended periods.
    ///
    /// ## Memory Management
    /// - Releases all window resources
    /// - Stops all animations and timers
    /// - Next show() call will recreate window
    ///
    /// ## When to Use
    /// - App entering background for extended time
    /// - Memory pressure situations
    /// - User explicitly disables indicator
    ///
    /// - Note: Window will be recreated on next showIndicator() call
    /// - Important: Safe to call multiple times
    public func cleanup() {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            screenChangeObserver = nil
        }
        
        if let window = indicatorWindow {
            window.close()
            indicatorWindow = nil
            hostingController = nil
        }
        isVisible = false
    }
    
    // MARK: - Private Implementation
    
    private func setupIndicatorWindow() {
        guard let screen = NSScreen.main else {
            print("Warning: No main screen available for indicator window")
            return
        }
        
        // Create transparent window covering full screen
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // Configure window properties
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        window.isReleasedWhenClosed = false
        
        // Create SwiftUI view with bindings
        let indicatorView = RecordingIndicatorView(
            isVisible: Binding(
                get: { self.isVisible },
                set: { self.isVisible = $0 }
            ),
            state: Binding(
                get: { self.currentState },
                set: { self.currentState = $0 }
            ),
            progress: Binding(
                get: { self.currentProgress },
                set: { self.currentProgress = $0 }
            )
        )
        
        // Create hosting controller
        let hostingController = NSHostingController(rootView: indicatorView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        
        // Set window content
        window.contentViewController = hostingController
        
        // Store references
        self.indicatorWindow = window
        self.hostingController = hostingController
        
        // Position on screen (will be handled by GeometryReader in view)
        window.setFrameOrigin(screen.frame.origin)
        
        // Listen for screen changes
        setupScreenChangeNotifications()
    }
    
    private func updateIndicatorVisibility(_ visible: Bool) {
        guard let window = indicatorWindow else {
            if visible {
                // Create window if needed
                setupIndicatorWindow()
                updateIndicatorVisibility(visible)
            }
            return
        }
        
        isVisible = visible
        
        if visible {
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        } else {
            // Hide window but keep it allocated for performance
            window.orderOut(nil)
        }
    }
    
    private func setupScreenChangeNotifications() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenChange()
            }
        }
    }
    
    private func handleScreenChange() {
        guard let window = indicatorWindow,
              let screen = NSScreen.main else { return }
        
        // Update window frame for new screen configuration
        window.setFrame(screen.frame, display: true)
    }
}

// MARK: - Convenience Extensions

extension RecordingIndicatorWindowManager {
    /// Show indicator for idle state
    public func showIdle() {
        showIndicator(state: .idle)
    }
    
    /// Show indicator for recording state
    public func showRecording() {
        showIndicator(state: .recording)
    }
    
    /// Show indicator for processing state with progress
    /// - Parameter progress: Processing progress (0.0-1.0)
    public func showProcessing(progress: Double) {
        showIndicator(state: .processing, progress: max(0.0, min(1.0, progress)))
    }

    /// Show indicator for completion state
    public func showCompletion() {
        showIndicator(state: .completed)
    }

    /// Show indicator for error state
    public func showError() {
        showIndicator(state: .error)
    }
}

// MARK: - Notification Extensions

extension NSNotification.Name {
    static let recordingIndicatorStateChanged = NSNotification.Name("recordingIndicatorStateChanged")
}