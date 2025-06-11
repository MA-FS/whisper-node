import Cocoa
import SwiftUI
import OSLog

/// Manages the menu bar interface for Whisper Node
///
/// Provides a menu bar icon with state indication and dropdown menu access.
/// Handles headless operation by default with optional Dock icon toggle.
@MainActor
public class MenuBarManager: ObservableObject {
    
    // MARK: - Logger
    
    private static let logger = Logger(subsystem: "com.whispernode.app", category: "MenuBarManager")
    
    // MARK: - State
    
    /// Current application state for visual indication
    public enum AppState {
        case normal
        case recording
        case error
    }
    
    /// Errors that can occur during menu bar setup
    public enum MenuBarError: Error, LocalizedError {
        case statusItemCreationFailed
        case popoverSetupFailed
        
        public var errorDescription: String? {
            switch self {
            case .statusItemCreationFailed:
                return "Failed to create menu bar status item"
            case .popoverSetupFailed:
                return "Failed to setup menu bar dropdown"
            }
        }
    }
    
    @Published public var currentState: AppState = .normal
    @Published public var showDockIcon: Bool = false
    @Published public var initializationError: MenuBarError?
    
    // MARK: - Menu Bar Components
    
    private let statusBar = NSStatusBar.system
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    
    // MARK: - Configuration
    
    private static let iconSize: CGFloat = 16.0
    public static let dropdownWidth: CGFloat = 240.0
    private static let initialDropdownHeight: CGFloat = 200.0
    
    // MARK: - Initialization
    
    public init() {
        do {
            try setupMenuBar()
            try setupPopover()
            configureAppBehavior()
            Self.logger.info("MenuBarManager initialized successfully")
        } catch {
            Self.logger.error("MenuBarManager initialization failed: \(error.localizedDescription)")
            if let menuBarError = error as? MenuBarError {
                initializationError = menuBarError
            }
        }
    }
    
    // MARK: - Public Interface
    
    /// Update the menu bar icon state
    /// - Parameter state: The new application state
    public func updateState(_ state: AppState) {
        currentState = state
        updateMenuBarIcon()
        Self.logger.debug("Menu bar state updated to: \(String(describing: state))")
    }
    
    /// Toggle visibility of the Dock icon
    /// - Parameter visible: Whether the Dock icon should be visible
    public func setDockIconVisible(_ visible: Bool) {
        showDockIcon = visible
        updateAppBehavior()
        Self.logger.info("Dock icon visibility changed to: \(visible)")
    }
    
    /// Show the dropdown menu
    public func showDropdown() {
        guard let statusItem = statusItem,
              let button = statusItem.button,
              let popover = popover else {
            Self.logger.error("Cannot show dropdown - missing components")
            return
        }
        
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            Self.logger.debug("Dropdown menu shown")
        }
    }
    
    /// Hide the dropdown menu
    public func hideDropdown() {
        popover?.performClose(nil)
        Self.logger.debug("Dropdown menu hidden")
    }
    
    // MARK: - Private Setup Methods
    
    private func setupMenuBar() throws {
        statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        
        guard let statusItem = statusItem,
              let button = statusItem.button else {
            Self.logger.error("Failed to create status item")
            throw MenuBarError.statusItemCreationFailed
        }
        
        // Configure button
        button.image = createMenuBarIcon(for: .normal)
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
        // Accessibility
        button.toolTip = "Whisper Node - Voice to Text (Click for menu)"
        
        // Enhanced accessibility support
        button.setAccessibilityRole(.menuButton)
        button.setAccessibilityLabel("Whisper Node menu")
        button.setAccessibilityHelp("Opens the Whisper Node menu with preferences and status information")
        
        Self.logger.info("Menu bar item configured")
    }
    
    private func setupPopover() throws {
        popover = NSPopover()
        guard let popover = popover else {
            Self.logger.error("Failed to create popover")
            throw MenuBarError.popoverSetupFailed
        }
        
        popover.contentSize = NSSize(width: Self.dropdownWidth, height: Self.initialDropdownHeight)
        popover.behavior = .transient
        popover.animates = true
        
        // Set SwiftUI content
        let contentView = MenuBarDropdownView()
            .environmentObject(self)
        
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        Self.logger.info("Popover configured")
    }
    
    private func configureAppBehavior() {
        updateAppBehavior()
    }
    
    private func updateAppBehavior() {
        let activationPolicy: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        NSApp.setActivationPolicy(activationPolicy)
        
        Self.logger.debug("App activation policy set to: \(activationPolicy == .regular ? "regular" : "accessory")")
    }
    
    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        button.image = createMenuBarIcon(for: currentState)
    }
    
    private func createMenuBarIcon(for state: AppState) -> NSImage? {
        guard let baseImage = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Whisper Node") else {
            Self.logger.error("Failed to create mic.fill SF Symbol")
            return nil
        }
        
        // Configure image for menu bar
        let image = baseImage.copy() as! NSImage
        image.size = NSSize(width: Self.iconSize, height: Self.iconSize)
        image.isTemplate = state == .normal // Template images automatically adapt to light/dark mode
        
        // Apply state-specific tinting
        switch state {
        case .normal:
            // Template image handles this automatically
            break
        case .recording:
            image.isTemplate = false
            if let tintedImage = tintImage(image, with: .systemBlue) {
                return tintedImage
            }
        case .error:
            image.isTemplate = false
            if let tintedImage = tintImage(image, with: .systemRed) {
                return tintedImage
            }
        }
        
        return image
    }
    
    private func tintImage(_ image: NSImage, with color: NSColor) -> NSImage? {
        let tintedImage = NSImage(size: image.size)
        tintedImage.lockFocus()
        
        color.set()
        image.draw(at: .zero, from: NSRect(origin: .zero, size: image.size), operation: .sourceIn, fraction: 1.0)
        
        tintedImage.unlockFocus()
        return tintedImage
    }
    
    // MARK: - Actions
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        
        if event?.type == .rightMouseUp {
            // Right-click: Show context menu (future implementation)
            Self.logger.debug("Right-click detected on menu bar item")
        } else {
            // Left-click: Show dropdown
            showDropdown()
        }
    }
}

// MARK: - MenuBarDropdownView

/// SwiftUI view for the menu bar dropdown content
struct MenuBarDropdownView: View {
    @EnvironmentObject var menuBarManager: MenuBarManager
    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var audioEngine = AudioCaptureEngine.shared
    
    private var currentMicrophoneName: String {
        // Get available devices and find the current one
        let availableDevices = audioEngine.getAvailableInputDevices()

        if let deviceID = settingsManager.preferredInputDevice {
            // Find the device name by ID
            if let device = availableDevices.first(where: { $0.deviceID == deviceID }) {
                return device.name
            }
        }

        // Fallback to "Default System Device" if no specific device is selected or found
        return "Default System Device"
    }

    private var currentHotkeyDescription: String {
        // Get the actual hotkey configuration from GlobalHotkeyManager
        // The description already includes "(Hold)" for modifier-only combinations
        let hotkeyManager = GlobalHotkeyManager.shared
        return hotkeyManager.currentHotkey.description
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.blue)
                        .accessibilityLabel("Whisper Node app icon")
                    Text("Whisper Node")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                }
                
                Divider()
            }
            .padding(.bottom, 4)
            
            // Status information
            VStack(alignment: .leading, spacing: 6) {
                StatusRow(icon: "speaker.wave.2.fill", label: "Microphone", value: currentMicrophoneName)
                StatusRow(icon: "brain.head.profile", label: "Model", value: "Whisper Small")
                StatusRow(icon: "keyboard", label: "Shortcut", value: currentHotkeyDescription)
            }
            
            Divider()
                .padding(.vertical, 4)
            
            // Action buttons
            VStack(alignment: .leading, spacing: 4) {
                MenuButton(icon: "gearshape.fill", title: "Preferences...") {
                    menuBarManager.hideDropdown()
                    PreferencesWindowManager.shared.showPreferences()
                }
                .accessibilityIdentifier("menubar-preferences-button")
                
                MenuButton(icon: "arrow.clockwise", title: "Restart Whisper Node") {
                    // TODO: Restart application
                    menuBarManager.hideDropdown()
                }
                .accessibilityIdentifier("menubar-restart-button")
                
                Divider()
                    .padding(.vertical, 2)
                
                MenuButton(icon: "power", title: "Quit Whisper Node") {
                    NSApp.terminate(nil)
                }
                .accessibilityIdentifier("menubar-quit-button")
            }
        }
        .padding(16)
        .frame(width: MenuBarManager.dropdownWidth)
    }
}

// MARK: - Supporting Views

struct StatusRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 16)
            
            Text(label)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .foregroundColor(.primary)
        }
        .font(.system(size: 13))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

struct MenuButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.primary)
                    .frame(width: 16)
                
                Text(title)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(title)
        .accessibilityHint("Activates \(title.lowercased())")
    }
}
