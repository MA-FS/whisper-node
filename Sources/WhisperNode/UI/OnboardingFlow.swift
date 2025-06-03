import SwiftUI
import AVFoundation
import OSLog

/// First-run onboarding flow for Whisper Node
///
/// Provides a step-by-step setup wizard that guides users through essential configuration:
/// - Welcome and app introduction
/// - Microphone permission request and handling
/// - Initial Whisper model selection and download
/// - Basic hotkey configuration
/// - Setup completion confirmation
///
/// The onboarding flow can be resumed if interrupted and saves progress between sessions.
struct OnboardingFlow: View {
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var core = WhisperNodeCore.shared
    @State private var currentStep: Int = 0
    @Environment(\.dismiss) private var dismiss
    
    private static let logger = Logger(subsystem: "com.whispernode.onboarding", category: "flow")
    private static let stepTransitionDuration: TimeInterval = 0.3
    
    private let steps: [OnboardingStep] = [
        .welcome,
        .permissions,
        .modelSelection,
        .hotkeySetup,
        .completion
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(NSColor.windowBackgroundColor)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Progress indicator
                    OnboardingProgressBar(
                        currentStep: currentStep,
                        totalSteps: steps.count
                    )
                    .padding(.horizontal, 40)
                    .padding(.top, 20)
                    
                    // Content area
                    TabView(selection: $currentStep) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            stepView(for: step, at: index)
                                .tag(index)
                                .accessibilityLabel("Onboarding step \(index + 1) of \(steps.count): \(step.title)")
                                .accessibilityHint("Navigate through onboarding steps")
                                .focusable()
                        }
                    }
                    .tabViewStyle(DefaultTabViewStyle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Onboarding wizard")
                }
            }
        }
        .frame(width: 600, height: 500)
        .onAppear {
            // Resume from saved step if onboarding was interrupted
            currentStep = settings.onboardingStep
            Self.logger.info("Onboarding flow started at step \(currentStep)")
        }
        .onChange(of: currentStep) { newStep in
            settings.onboardingStep = newStep
            Self.logger.debug("Onboarding step updated to \(newStep)")
        }
    }
    
    @ViewBuilder
    private func stepView(for step: OnboardingStep, at index: Int) -> some View {
        switch step {
        case .welcome:
            WelcomeStep(onNext: nextStep)
        case .permissions:
            PermissionsStep(onNext: nextStep, onBack: previousStep)
        case .modelSelection:
            ModelSelectionStep(onNext: nextStep, onBack: previousStep)
        case .hotkeySetup:
            HotkeySetupStep(onNext: nextStep, onBack: previousStep)
        case .completion:
            CompletionStep(onFinish: completeOnboarding)
        }
    }
    
    private func nextStep() {
        if currentStep < steps.count - 1 {
            withAnimation(.easeInOut(duration: Self.stepTransitionDuration)) {
                currentStep += 1
            }
        }
    }
    
    private func previousStep() {
        if currentStep > 0 {
            withAnimation(.easeInOut(duration: Self.stepTransitionDuration)) {
                currentStep -= 1
            }
        }
    }
    
    private func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        settings.onboardingStep = 0
        Self.logger.info("Onboarding completed successfully")
        
        // Use the window manager to handle dismissal
        OnboardingWindowManager.shared.hideOnboarding()
    }
}

// MARK: - Onboarding Steps Enum

enum OnboardingStep: CaseIterable {
    case welcome
    case permissions
    case modelSelection
    case hotkeySetup
    case completion
    
    var title: String {
        switch self {
        case .welcome:
            return "Welcome to Whisper Node"
        case .permissions:
            return "Microphone Access"
        case .modelSelection:
            return "Choose Your Model"
        case .hotkeySetup:
            return "Set Your Hotkey"
        case .completion:
            return "You're All Set!"
        }
    }
}

// MARK: - Progress Bar

struct OnboardingProgressBar: View {
    let currentStep: Int
    let totalSteps: Int
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Step \(currentStep + 1) of \(totalSteps)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            ProgressView(value: Double(currentStep + 1), total: Double(totalSteps))
                .progressViewStyle(LinearProgressViewStyle())
        }
    }
}

// MARK: - Welcome Step

struct WelcomeStep: View {
    let onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            VStack(spacing: 20) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                
                VStack(spacing: 12) {
                    Text("Welcome to Whisper Node")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Blazingly fast, private speech-to-text")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 8) {
                    FeatureRow(icon: "lock.fill", text: "100% offline processing")
                    FeatureRow(icon: "bolt.fill", text: "Lightning-fast transcription")
                    FeatureRow(icon: "keyboard", text: "Press-and-hold activation")
                    FeatureRow(icon: "brain.head.profile", text: "Advanced AI models")
                }
                .padding(.top, 20)
            }
            
            Spacer()
            
            HStack {
                Spacer()
                Button("Get Started") {
                    onNext()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityLabel("Get started with onboarding")
                .accessibilityHint("Begin the setup process for Whisper Node")
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 40)
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(text)
                .foregroundColor(.primary)
            Spacer()
        }
    }
}

// MARK: - Permissions Step

struct PermissionsStep: View {
    let onNext: () -> Void
    let onBack: () -> Void
    
    @State private var permissionStatus: AVAuthorizationStatus = .notDetermined
    @State private var isCheckingPermissions = false
    @State private var showingSystemPreferences = false
    
    private static let logger = Logger(subsystem: "com.whispernode.onboarding", category: "permissions")
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            VStack(spacing: 20) {
                Image(systemName: permissionIcon)
                    .font(.system(size: 64))
                    .foregroundColor(permissionColor)
                
                VStack(spacing: 12) {
                    Text("Microphone Access Required")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text(permissionMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }
            
            Spacer()
            
            VStack(spacing: 16) {
                if permissionStatus == .authorized {
                    Text("✓ Microphone access granted")
                        .foregroundColor(.green)
                        .font(.headline)
                } else if permissionStatus == .denied {
                    VStack(spacing: 12) {
                        Text("Microphone access was denied")
                            .foregroundColor(.red)
                            .font(.headline)
                        
                        Text("Please enable microphone access in System Preferences")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button("Open System Preferences") {
                            openSystemPreferences()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            
            HStack {
                Button("Back") {
                    onBack()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                if permissionStatus == .authorized || permissionStatus == .restricted {
                    Button("Continue") {
                        onNext()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(permissionButtonTitle) {
                        if permissionStatus == .restricted {
                            // Allow continuing even with restricted permissions
                            onNext()
                        } else {
                            requestPermission()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCheckingPermissions)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 40)
        .onAppear {
            checkCurrentPermissionStatus()
        }
    }
    
    private var permissionIcon: String {
        switch permissionStatus {
        case .authorized:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        case .notDetermined:
            return "mic.circle"
        case .restricted:
            return "exclamationmark.circle.fill"
        @unknown default:
            return "questionmark.circle"
        }
    }
    
    private var permissionColor: Color {
        switch permissionStatus {
        case .authorized:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .blue
        @unknown default:
            return .gray
        }
    }
    
    private var permissionMessage: String {
        switch permissionStatus {
        case .authorized:
            return "Great! Whisper Node can now access your microphone for speech recognition."
        case .denied:
            return "Whisper Node needs microphone access to convert your speech to text."
        case .notDetermined:
            return "Whisper Node needs microphone access to convert your speech to text. This data stays completely private on your device."
        case .restricted:
            return "Microphone access is restricted by organizational policies or parental controls. Please contact your system administrator or check your device's restrictions in System Settings."
        @unknown default:
            return "Unable to determine microphone permission status."
        }
    }
    
    private var permissionButtonTitle: String {
        switch permissionStatus {
        case .denied:
            return "Retry"
        case .notDetermined:
            return "Grant Access"
        case .restricted:
            return "Continue Anyway"
        default:
            return "Check Status"
        }
    }
    
    private func checkCurrentPermissionStatus() {
        permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        Self.logger.debug("Current microphone permission status: \(String(describing: permissionStatus))")
    }
    
    private func requestPermission() {
        isCheckingPermissions = true
        
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                self.isCheckingPermissions = false
                self.permissionStatus = granted ? .authorized : .denied
                
                Self.logger.info("Microphone permission request result: \(granted ? "granted" : "denied")")
                
                if granted {
                    // Small delay before auto-advancing to give user feedback
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.onNext()
                    }
                }
            }
        }
    }
    
    private func openSystemPreferences() {
        // Use the appropriate URL based on macOS version
        // macOS 13+ uses System Settings, earlier versions use System Preferences
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone", // macOS 13+
            "x-apple.preferences:com.apple.preference.security?Privacy_Microphone" // macOS 12 and earlier
        ]
        
        for urlString in urls {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                Self.logger.info("Opened system settings for microphone permissions using: \(urlString)")
                return
            }
        }
        
        // Fallback: try to open the general Privacy & Security pane
        if let fallbackUrl = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(fallbackUrl)
            Self.logger.warning("Fallback: Opened general Privacy & Security settings")
        } else {
            Self.logger.error("Failed to open system settings for microphone permissions")
        }
    }
}

// MARK: - Model Selection Step

struct ModelSelectionStep: View {
    let onNext: () -> Void
    let onBack: () -> Void
    
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var modelManager = ModelManager.shared
    @State private var selectedModel = "tiny.en"
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0.0
    @State private var downloadError: String?
    
    private var buttonTitle: String {
        if isDownloading {
            return "Downloading..."
        }
        
        if let selectedModelInfo = modelManager.availableModels.first(where: { $0.name == selectedModel }) {
            switch selectedModelInfo.status {
            case .bundled, .installed:
                return "Continue"
            case .available:
                return "Download and Continue"
            case .downloading:
                return "Downloading..."
            case .failed:
                return "Retry Download"
            }
        }
        
        return "Continue"
    }
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            VStack(spacing: 20) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                
                VStack(spacing: 12) {
                    Text("Choose Your AI Model")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Select the Whisper model that best fits your needs")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            VStack(spacing: 12) {
                ForEach(modelManager.availableModels, id: \.name) { model in
                    OnboardingModelRow(
                        model: model,
                        isSelected: selectedModel == model.name,
                        onSelect: { selectedModel = model.name }
                    )
                    .accessibilityLabel("\(model.displayName), \(model.downloadSize / 1024 / 1024) MB, Status: \(statusText(for: model.status))")
                    .accessibilityHint("Double tap to select this model for speech recognition")
                }
            }
            .padding(.horizontal, 20)
            
            if isDownloading {
                VStack(spacing: 8) {
                    Text("Downloading \(selectedModel)...")
                        .font(.headline)
                    
                    ProgressView(value: downloadProgress)
                        .frame(maxWidth: 300)
                    
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 40)
            }
            
            if let error = downloadError {
                Text("Download failed: \(error)")
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
            
            HStack {
                Button("Back") {
                    onBack()
                }
                .buttonStyle(.bordered)
                .disabled(isDownloading)
                
                Spacer()
                
                Button(buttonTitle) {
                    downloadAndContinue()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDownloading)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 40)
        .onAppear {
            selectedModel = settings.activeModelName
        }
    }
    
    private func statusText(for status: ModelStatus) -> String {
        switch status {
        case .bundled:
            return "Included with app"
        case .installed:
            return "Downloaded"
        case .available:
            return "Available for download"
        case .downloading:
            return "Downloading"
        case .failed:
            return "Download failed"
        }
    }
    
    private func downloadAndContinue() {
        guard let selectedModelInfo = modelManager.availableModels.first(where: { $0.name == selectedModel }) else {
            downloadError = "Selected model not found in available models"
            return
        }
        
        // If model is already installed or bundled, skip download
        if selectedModelInfo.status == .installed || selectedModelInfo.status == .bundled {
            settings.activeModelName = selectedModel
            onNext()
            return
        }
        
        isDownloading = true
        downloadError = nil
        
        Task {
            // Start the actual model download
            await modelManager.downloadModel(selectedModelInfo)
            
            // Monitor download progress
            await monitorDownloadProgress()
        }
    }
    
    private func monitorDownloadProgress() async {
        var iterationCount = 0
        let maxIterations = 1200 // 2 minutes max (120 seconds / 0.1 second intervals)
        
        while isDownloading && iterationCount < maxIterations {
            iterationCount += 1
            
            guard let model = modelManager.availableModels.first(where: { $0.name == selectedModel }) else {
                DispatchQueue.main.async {
                    self.downloadError = "Model not found during monitoring"
                    self.isDownloading = false
                }
                return
            }
            
            DispatchQueue.main.async {
                self.downloadProgress = model.downloadProgress
                
                switch model.status {
                case .installed:
                    self.isDownloading = false
                    self.settings.activeModelName = self.selectedModel
                    self.onNext()
                case .failed:
                    self.isDownloading = false
                    self.downloadError = model.errorMessage ?? "Download failed"
                case .downloading:
                    // Continue monitoring
                    break
                default:
                    break
                }
            }
            
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        // Handle timeout case
        if iterationCount >= maxIterations && isDownloading {
            DispatchQueue.main.async {
                self.downloadError = "Download timed out after 2 minutes"
                self.isDownloading = false
            }
        }
    }
}

struct OnboardingModelInfo {
    let name: String
    let displayName: String
    let size: String
    let speed: String
    let accuracy: String
}

struct OnboardingModelRow: View {
    let model: ModelInfo
    let isSelected: Bool
    let onSelect: () -> Void
    
    private var statusIndicator: String {
        switch model.status {
        case .bundled:
            return "Included"
        case .installed:
            return "Downloaded"
        case .available:
            return "Available"
        case .downloading:
            return "Downloading..."
        case .failed:
            return "Failed"
        }
    }
    
    private var statusColor: Color {
        switch model.status {
        case .bundled, .installed:
            return .green
        case .available:
            return .blue
        case .downloading:
            return .orange
        case .failed:
            return .red
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("\(model.downloadSize / 1024 / 1024) MB")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(statusIndicator)
                        .font(.caption)
                        .foregroundColor(statusColor)
                    
                    Text(model.description.components(separatedBy: ".").first ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Circle()
                    .foregroundColor(isSelected ? Color.blue : Color.clear)
                    .overlay(
                        Circle()
                            .stroke(Color.blue, lineWidth: 2)
                    )
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .foregroundColor(Color.white)
                            .frame(width: 8, height: 8)
                            .opacity(isSelected ? 1 : 0)
                    )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .foregroundColor(isSelected ? Color.blue.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Hotkey Setup Step

struct HotkeySetupStep: View {
    let onNext: () -> Void
    let onBack: () -> Void
    
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var hotkeyManager = GlobalHotkeyManager.shared
    @State private var isRecording = false
    @State private var recordedHotkeyDescription: String = ""
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            VStack(spacing: 20) {
                Image(systemName: "keyboard")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                
                VStack(spacing: 12) {
                    Text("Set Your Hotkey")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Choose the key combination to activate voice input")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            VStack(spacing: 20) {
                Text("Current Hotkey:")
                    .font(.headline)
                
                Text(isRecording ? "Press your hotkey combination..." : hotkeyManager.currentHotkey.description)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .foregroundColor(isRecording ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isRecording ? Color.blue : Color.gray.opacity(0.3), lineWidth: isRecording ? 2 : 1)
                            )
                    )
                    .animation(.easeInOut(duration: 0.2), value: isRecording)
                
                Button(isRecording ? "Press keys to record..." : "Change Hotkey") {
                    if isRecording {
                        stopHotkeyRecording()
                    } else {
                        startHotkeyRecording()
                    }
                }
                .buttonStyle(.bordered)
            }
            
            VStack(spacing: 8) {
                Text("How to use:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Press and hold your hotkey")
                    Text("2. Speak your text")
                    Text("3. Release the hotkey")
                    Text("4. Text appears at your cursor")
                }
                .font(.body)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack {
                Button("Back") {
                    onBack()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Continue") {
                    onNext()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 40)
        .onAppear {
            // Initialize with current hotkey description
            recordedHotkeyDescription = hotkeyManager.currentHotkey.description
        }
    }
    
    private func startHotkeyRecording() {
        isRecording = true
        hotkeyManager.isRecording = true
        
        // Start capturing key events using NSEvent monitoring
        HotkeyRecorder.shared.startRecording { [self] keyCode, modifierFlags in
            Task { @MainActor in
                // Create a human-readable description for the captured hotkey
                let description = self.createHotkeyDescription(keyCode: keyCode, modifierFlags: modifierFlags)
                
                // Create new hotkey configuration
                let newConfiguration = HotkeyConfiguration(
                    keyCode: keyCode,
                    modifierFlags: modifierFlags,
                    description: description
                )
                
                // Update the hotkey configuration
                self.recordedHotkeyDescription = description
                
                // Stop recording automatically after capture
                self.stopHotkeyRecording(with: newConfiguration)
            }
        }
        
        // Set a timeout for recording (15 seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
            if self.isRecording {
                self.stopHotkeyRecording(with: nil)
            }
        }
    }
    
    private func stopHotkeyRecording(with configuration: HotkeyConfiguration? = nil) {
        isRecording = false
        hotkeyManager.isRecording = false
        
        // Stop the hotkey recorder
        HotkeyRecorder.shared.stopRecording()
        
        // If we captured a valid hotkey, update the hotkey manager
        if let config = configuration {
            hotkeyManager.updateHotkey(config)
            recordedHotkeyDescription = config.description
        } else {
            // Reset to previous state if no hotkey was captured
            recordedHotkeyDescription = hotkeyManager.currentHotkey.description
        }
    }
    
    private func createHotkeyDescription(keyCode: UInt16, modifierFlags: CGEventFlags) -> String {
        var parts: [String] = []
        
        // Add modifier keys
        if modifierFlags.contains(.maskCommand) {
            parts.append("⌘")
        }
        if modifierFlags.contains(.maskAlternate) {
            parts.append("⌥")
        }
        if modifierFlags.contains(.maskShift) {
            parts.append("⇧")
        }
        if modifierFlags.contains(.maskControl) {
            parts.append("⌃")
        }
        
        // Add the main key
        let keyName = keyCodeToString(keyCode)
        parts.append(keyName)
        
        return parts.joined(separator: "")
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        // Map common key codes to their string representations
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 53: return "Escape"
        case 51: return "Delete"
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 50: return "`"
        default: return "Key \(keyCode)"
        }
    }
}

// MARK: - Completion Step

struct CompletionStep: View {
    let onFinish: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.green)
                
                VStack(spacing: 12) {
                    Text("You're All Set!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Whisper Node is ready to convert your speech to text")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Tips:")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• Access preferences from the menu bar")
                        Text("• Try different models for speed vs accuracy")
                        Text("• Voice input works in any text field")
                        Text("• Check the menu bar for status updates")
                    }
                    .font(.body)
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .foregroundColor(Color.blue.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                        )
                )
            }
            
            Spacer()
            
            HStack {
                Spacer()
                Button("Start Using Whisper Node") {
                    onFinish()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 40)
    }
}

#Preview {
    OnboardingFlow()
}