import SwiftUI
import AppKit
import OSLog

/// Contextual help and guidance system for WhisperNode
///
/// Provides intelligent, context-aware assistance throughout the application with
/// tooltips, guided tours, troubleshooting assistance, and user education.
///
/// ## Features
/// - Context-aware help tooltips and popovers
/// - Interactive guided tours for new users
/// - Troubleshooting assistance with diagnostic information
/// - User education tips and best practices
/// - Accessibility-compliant help interface
///
/// ## Usage
/// ```swift
/// // Show contextual help
/// HelpSystem.shared.showHelp(for: .hotkeySetup, from: sourceView)
/// 
/// // Start guided tour
/// HelpSystem.shared.startGuidedTour(.firstRun)
/// 
/// // Show troubleshooting
/// HelpSystem.shared.showTroubleshooting(for: .microphoneAccess)
/// ```
@MainActor
public class HelpSystem: NSObject, ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = HelpSystem()
    
    // MARK: - Logger
    
    private static let logger = Logger(subsystem: "com.whispernode.help", category: "system")
    
    // MARK: - Published Properties
    
    @Published public var isHelpVisible = false
    @Published public var currentHelpContext: HelpContext?
    @Published public var isGuidedTourActive = false
    @Published public var currentTourStep = 0
    
    // MARK: - Private Properties
    
    private var helpPopover: NSPopover?
    private var currentTour: GuidedTour?
    private var helpWindow: NSWindow?
    
    // MARK: - Help Context Types
    
    public enum HelpContext: String, CaseIterable {
        case hotkeySetup = "hotkey_setup"
        case microphonePermissions = "microphone_permissions"
        case accessibilityPermissions = "accessibility_permissions"
        case modelSelection = "model_selection"
        case voiceSettings = "voice_settings"
        case troubleshooting = "troubleshooting"
        case firstRun = "first_run"
        case recordingIndicator = "recording_indicator"
        case menuBar = "menu_bar"
        case textInsertion = "text_insertion"
        
        var title: String {
            switch self {
            case .hotkeySetup:
                return "Hotkey Setup"
            case .microphonePermissions:
                return "Microphone Access"
            case .accessibilityPermissions:
                return "Accessibility Permissions"
            case .modelSelection:
                return "AI Model Selection"
            case .voiceSettings:
                return "Voice Settings"
            case .troubleshooting:
                return "Troubleshooting"
            case .firstRun:
                return "Getting Started"
            case .recordingIndicator:
                return "Recording Indicator"
            case .menuBar:
                return "Menu Bar"
            case .textInsertion:
                return "Text Insertion"
            }
        }
        
        var icon: String {
            switch self {
            case .hotkeySetup:
                return "keyboard"
            case .microphonePermissions:
                return "mic.fill"
            case .accessibilityPermissions:
                return "accessibility"
            case .modelSelection:
                return "brain.head.profile"
            case .voiceSettings:
                return "waveform"
            case .troubleshooting:
                return "wrench.and.screwdriver"
            case .firstRun:
                return "hand.wave"
            case .recordingIndicator:
                return "record.circle"
            case .menuBar:
                return "menubar.rectangle"
            case .textInsertion:
                return "text.cursor"
            }
        }
    }
    
    // MARK: - Guided Tour Types
    
    public enum GuidedTour: String, CaseIterable {
        case firstRun = "first_run"
        case advancedFeatures = "advanced_features"
        case troubleshooting = "troubleshooting"
        
        var steps: [TourStep] {
            switch self {
            case .firstRun:
                return FirstRunTour.steps
            case .advancedFeatures:
                return AdvancedFeaturesTour.steps
            case .troubleshooting:
                return TroubleshootingTour.steps
            }
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        Self.logger.info("HelpSystem initialized")
    }
    
    // MARK: - Public Interface
    
    /// Show contextual help for a specific topic
    /// - Parameters:
    ///   - context: The help context to display
    ///   - sourceView: The view to anchor the help popover to
    ///   - preferredEdge: Preferred edge for popover positioning
    public func showHelp(
        for context: HelpContext,
        from sourceView: NSView,
        preferredEdge: NSRectEdge = .maxY
    ) {
        Self.logger.info("Showing help for context: \(context.rawValue)")
        
        currentHelpContext = context
        
        // Create help content view
        let helpContent = HelpContentView(context: context) { [weak self] in
            self?.hideHelp()
        }
        
        // Create and configure popover
        let popover = NSPopover()
        popover.contentViewController = NSHostingController(rootView: helpContent)
        popover.behavior = .transient
        popover.delegate = self
        
        // Show popover
        popover.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: preferredEdge)
        
        helpPopover = popover
        isHelpVisible = true
    }
    
    /// Hide currently visible help
    public func hideHelp() {
        Self.logger.debug("Hiding help")
        
        helpPopover?.close()
        helpPopover = nil
        currentHelpContext = nil
        isHelpVisible = false
    }
    
    /// Start a guided tour
    /// - Parameter tour: The tour to start
    public func startGuidedTour(_ tour: GuidedTour) {
        Self.logger.info("Starting guided tour: \(tour.rawValue)")
        
        currentTour = tour
        currentTourStep = 0
        isGuidedTourActive = true
        
        showTourStep()
    }
    
    /// Advance to the next tour step
    public func nextTourStep() {
        guard let tour = currentTour else { return }
        
        currentTourStep += 1
        
        if currentTourStep >= tour.steps.count {
            endGuidedTour()
        } else {
            showTourStep()
        }
    }
    
    /// Go back to the previous tour step
    public func previousTourStep() {
        guard currentTourStep > 0 else { return }
        
        currentTourStep -= 1
        showTourStep()
    }
    
    /// End the current guided tour
    public func endGuidedTour() {
        Self.logger.info("Ending guided tour")
        
        currentTour = nil
        currentTourStep = 0
        isGuidedTourActive = false
        hideHelp()
    }
    
    /// Show troubleshooting assistance
    /// - Parameter issue: The specific issue to troubleshoot
    public func showTroubleshooting(for issue: TroubleshootingIssue) {
        Self.logger.info("Showing troubleshooting for: \(issue.rawValue)")
        
        let troubleshootingView = TroubleshootingView(issue: issue) { [weak self] in
            self?.hideTroubleshooting()
        }
        
        showHelpWindow(with: troubleshootingView, title: "Troubleshooting: \(issue.title)")
    }
    
    /// Hide troubleshooting window
    public func hideTroubleshooting() {
        helpWindow?.close()
        helpWindow = nil
    }
    
    // MARK: - Private Methods
    
    private func showTourStep() {
        guard let tour = currentTour,
              currentTourStep < tour.steps.count else { return }
        
        let step = tour.steps[currentTourStep]
        Self.logger.debug("Showing tour step: \(step.title)")
        
        // Implementation for showing tour step would go here
        // This would involve highlighting UI elements and showing guidance
    }
    
    private func showHelpWindow<Content: View>(with content: Content, title: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = title
        window.contentViewController = NSHostingController(rootView: content)
        window.center()
        window.makeKeyAndOrderFront(nil)
        
        helpWindow = window
    }
}

// MARK: - NSPopoverDelegate

extension HelpSystem: NSPopoverDelegate {
    public func popoverDidClose(_ notification: Notification) {
        isHelpVisible = false
        currentHelpContext = nil
        helpPopover = nil
    }
}

// MARK: - Supporting Types

public struct TourStep {
    let title: String
    let description: String
    let targetElement: String?
    let action: (() -> Void)?
    
    public init(title: String, description: String, targetElement: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.description = description
        self.targetElement = targetElement
        self.action = action
    }
}

public enum TroubleshootingIssue: String, CaseIterable {
    case microphoneNotWorking = "microphone_not_working"
    case hotkeyNotResponding = "hotkey_not_responding"
    case transcriptionInaccurate = "transcription_inaccurate"
    case appNotStarting = "app_not_starting"
    case permissionsDenied = "permissions_denied"
    case performanceIssues = "performance_issues"

    var title: String {
        switch self {
        case .microphoneNotWorking:
            return "Microphone Not Working"
        case .hotkeyNotResponding:
            return "Hotkey Not Responding"
        case .transcriptionInaccurate:
            return "Transcription Inaccurate"
        case .appNotStarting:
            return "App Not Starting"
        case .permissionsDenied:
            return "Permissions Denied"
        case .performanceIssues:
            return "Performance Issues"
        }
    }
}

// MARK: - Help Content View

struct HelpContentView: View {
    let context: HelpSystem.HelpContext
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: context.icon)
                    .font(.title2)
                    .foregroundColor(.blue)

                Text(context.title)
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(helpContent)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    if !helpSteps.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Steps:")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            ForEach(Array(helpSteps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(index + 1).")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 20, alignment: .leading)

                                    Text(step)
                                        .font(.caption)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }

                    if !relatedLinks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Related:")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            ForEach(relatedLinks, id: \.title) { link in
                                Button(action: link.action) {
                                    HStack {
                                        Image(systemName: "arrow.up.right.square")
                                            .font(.caption)
                                        Text(link.title)
                                            .font(.caption)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                .foregroundColor(.blue)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .padding(16)
        .frame(width: 350)
    }

    private var helpContent: String {
        switch context {
        case .hotkeySetup:
            return "Set up global hotkeys to activate WhisperNode from anywhere on your Mac. The default hotkey is Control+Option+Space."
        case .microphonePermissions:
            return "WhisperNode needs microphone access to capture your voice. Grant permission in System Preferences > Security & Privacy > Microphone."
        case .accessibilityPermissions:
            return "Accessibility permissions allow WhisperNode to detect global hotkeys and insert text into other applications."
        case .modelSelection:
            return "Choose the AI model that best fits your needs. Larger models are more accurate but use more resources."
        case .voiceSettings:
            return "Configure voice detection sensitivity and audio input settings for optimal transcription quality."
        case .troubleshooting:
            return "Having issues? Check common solutions and diagnostic information to resolve problems quickly."
        case .firstRun:
            return "Welcome to WhisperNode! Let's get you set up with everything you need for fast, private speech-to-text."
        case .recordingIndicator:
            return "The recording indicator shows your current status: blue for recording, spinning for processing, green for completion."
        case .menuBar:
            return "Access WhisperNode settings and status from the menu bar icon. Click to open preferences or check system status."
        case .textInsertion:
            return "WhisperNode automatically inserts transcribed text into the active application. Make sure the text field is focused."
        }
    }

    private var helpSteps: [String] {
        switch context {
        case .hotkeySetup:
            return [
                "Open WhisperNode preferences",
                "Go to the Shortcuts tab",
                "Click in the hotkey field",
                "Press your desired key combination",
                "Test the hotkey to ensure it works"
            ]
        case .microphonePermissions:
            return [
                "Open System Preferences",
                "Click Security & Privacy",
                "Select the Privacy tab",
                "Click Microphone in the sidebar",
                "Check the box next to WhisperNode"
            ]
        case .accessibilityPermissions:
            return [
                "Open System Preferences",
                "Click Security & Privacy",
                "Select the Privacy tab",
                "Click Accessibility in the sidebar",
                "Check the box next to WhisperNode"
            ]
        default:
            return []
        }
    }

    private var relatedLinks: [(title: String, action: () -> Void)] {
        switch context {
        case .hotkeySetup:
            return [
                ("Open Shortcuts Settings", { PreferencesWindowManager.shared.showPreferences() }),
                ("Troubleshooting", { HelpSystem.shared.showTroubleshooting(for: .hotkeyNotResponding) })
            ]
        case .microphonePermissions:
            return [
                ("Open Voice Settings", { PreferencesWindowManager.shared.showPreferences() }),
                ("Troubleshooting", { HelpSystem.shared.showTroubleshooting(for: .microphoneNotWorking) })
            ]
        default:
            return []
        }
    }
}

// MARK: - Tour Definitions

struct FirstRunTour {
    static let steps: [TourStep] = [
        TourStep(
            title: "Welcome to WhisperNode",
            description: "WhisperNode provides fast, private speech-to-text conversion right on your Mac. Let's get you set up!"
        ),
        TourStep(
            title: "Grant Permissions",
            description: "We'll need microphone and accessibility permissions to work properly. Don't worry - everything stays on your device."
        ),
        TourStep(
            title: "Choose Your Hotkey",
            description: "Set up a global hotkey to activate WhisperNode from anywhere. The default is Control+Option+Space."
        ),
        TourStep(
            title: "Select AI Model",
            description: "Choose the AI model that fits your needs. Larger models are more accurate but use more resources."
        ),
        TourStep(
            title: "You're Ready!",
            description: "Press your hotkey anywhere to start recording. Speak clearly and WhisperNode will insert the text automatically."
        )
    ]
}

struct AdvancedFeaturesTour {
    static let steps: [TourStep] = [
        TourStep(
            title: "Voice Activity Detection",
            description: "Adjust sensitivity to optimize when WhisperNode starts and stops recording based on your voice."
        ),
        TourStep(
            title: "Model Performance",
            description: "Monitor CPU and memory usage to find the right balance between accuracy and performance."
        ),
        TourStep(
            title: "Keyboard Shortcuts",
            description: "Set up additional shortcuts for different functions like model switching or settings access."
        )
    ]
}

struct TroubleshootingTour {
    static let steps: [TourStep] = [
        TourStep(
            title: "Check Permissions",
            description: "Most issues stem from missing permissions. Verify microphone and accessibility access."
        ),
        TourStep(
            title: "Test Your Setup",
            description: "Use the built-in test recording feature to verify your microphone and transcription are working."
        ),
        TourStep(
            title: "Performance Optimization",
            description: "If experiencing slowdowns, try a smaller AI model or check system resource usage."
        )
    ]
}

// MARK: - Troubleshooting View

struct TroubleshootingView: View {
    let issue: TroubleshootingIssue
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.title)
                    .foregroundColor(.orange)

                VStack(alignment: .leading) {
                    Text("Troubleshooting")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(issue.title)
                        .font(.headline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Close", action: onDismiss)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Problem description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Problem")
                            .font(.headline)
                        Text(problemDescription)
                            .font(.body)
                    }

                    // Solutions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Solutions")
                            .font(.headline)

                        ForEach(Array(solutions.enumerated()), id: \.offset) { index, solution in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("\(index + 1).")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.blue)
                                    Text(solution.title)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }

                                Text(solution.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 20)

                                if let action = solution.action {
                                    Button(solution.actionTitle ?? "Try This") {
                                        action()
                                    }
                                    .padding(.leading, 20)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    // Additional resources
                    if !additionalResources.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Additional Resources")
                                .font(.headline)

                            ForEach(additionalResources, id: \.title) { resource in
                                Button(action: resource.action) {
                                    HStack {
                                        Image(systemName: "arrow.up.right.square")
                                        Text(resource.title)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 500, height: 400)
    }

    private var problemDescription: String {
        switch issue {
        case .microphoneNotWorking:
            return "WhisperNode cannot access your microphone or audio input is not being detected."
        case .hotkeyNotResponding:
            return "The global hotkey is not activating WhisperNode when pressed."
        case .transcriptionInaccurate:
            return "The transcribed text doesn't match what you said or contains many errors."
        case .appNotStarting:
            return "WhisperNode fails to launch or crashes during startup."
        case .permissionsDenied:
            return "Required system permissions have been denied, preventing normal operation."
        case .performanceIssues:
            return "WhisperNode is running slowly or using excessive system resources."
        }
    }

    private var solutions: [(title: String, description: String, action: (() -> Void)?, actionTitle: String?)] {
        switch issue {
        case .microphoneNotWorking:
            return [
                ("Check Microphone Permissions", "Ensure WhisperNode has microphone access in System Preferences", {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }, "Open System Preferences"),
                ("Test Microphone", "Use the built-in test recording to verify your microphone works", {
                    PreferencesWindowManager.shared.showPreferences()
                }, "Open Voice Settings"),
                ("Check Audio Input", "Verify the correct microphone is selected in system settings", nil, nil)
            ]
        case .hotkeyNotResponding:
            return [
                ("Check Accessibility Permissions", "WhisperNode needs accessibility access for global hotkeys", {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }, "Open System Preferences"),
                ("Try Different Hotkey", "Some key combinations may conflict with other apps", {
                    PreferencesWindowManager.shared.showPreferences()
                }, "Change Hotkey"),
                ("Restart WhisperNode", "Sometimes a restart resolves hotkey issues", {
                    NSApp.terminate(nil)
                }, "Restart App")
            ]
        default:
            return []
        }
    }

    private var additionalResources: [(title: String, action: () -> Void)] {
        return [
            ("View System Requirements", { /* Open system requirements */ }),
            ("Contact Support", { /* Open support */ }),
            ("Check for Updates", { /* Check for app updates */ })
        ]
    }
}
