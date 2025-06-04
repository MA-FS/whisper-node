import SwiftUI
import AVFoundation
import CoreAudio

struct VoiceTab: View {
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var audioEngine = AudioCaptureEngine()
    @StateObject private var hapticManager = HapticManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var availableDevices: [(deviceID: AudioDeviceID, name: String)] = []
    @State private var permissionStatus: AudioCaptureEngine.PermissionStatus = .undetermined
    @State private var isTestRecording = false
    @State private var testRecordingProgress: Double = 0.0
    @State private var testRecordingTimer: Timer?
    @State private var testRecordingAudioData: [Float] = []
    @State private var showPermissionAlert = false
    @State private var showAudioError = false
    @State private var audioErrorMessage = ""
    
    // Timer for level meter updates
    @State private var levelMeterTimer: Timer?
    @State private var deviceCheckTimer: Timer?
    
    // Constants
    private static let testRecordingDuration: TimeInterval = 3.0
    private static let progressUpdateInterval: TimeInterval = 0.1
    private static let levelMeterUpdateInterval: TimeInterval = 1.0/30.0 // 30fps for better performance
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            HStack {
                Image(systemName: "mic.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
                    .accessibilityLabel("Voice settings icon")
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Voice Settings")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Configure microphone and voice detection")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 16)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Microphone Permission Status
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Microphone Permission")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        
                        HStack(spacing: 12) {
                            Image(systemName: permissionIcon)
                                .foregroundColor(permissionColor)
                                .font(.system(size: 16, weight: .medium))
                            
                            Text(permissionStatusText)
                                .font(.subheadline)
                                .foregroundColor(permissionColor)
                            
                            Spacer()
                            
                            if permissionStatus == .denied {
                                Button("Open System Preferences") {
                                    openSystemPreferences()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        .padding(16)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    
                    // Microphone Device Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Microphone Device")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Select microphone", selection: $settings.preferredInputDevice) {
                                Text("Default System Device")
                                    .tag(nil as UInt32?)
                                
                                ForEach(availableDevices, id: \.deviceID) { device in
                                    Text(device.name)
                                        .tag(device.deviceID as UInt32?)
                                }
                            }
                            .pickerStyle(.menu)
                            .disabled(permissionStatus != .granted)
                            .accessibilityLabel("Microphone device selection")
                            .accessibilityHint("Choose which microphone to use for voice input. Select 'Default System Device' to use your system's default microphone.")
                            
                            Text("Select the microphone device to use for voice input")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Audio Format Information
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Audio Format")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Text("Sample Rate:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("16 kHz")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    
                                    HStack(spacing: 8) {
                                        Text("Channels:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("Mono")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    
                                    HStack(spacing: 8) {
                                        Text("Bit Depth:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("32-bit Float")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(16)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(8)
                            
                            Text("Optimized audio format for speech recognition")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Input Level Meter
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Input Level")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            // Level meter section
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    // Level meter
                                    InputLevelMeter(
                                        level: audioEngine.inputLevel,
                                        vadThreshold: settings.vadThreshold,
                                        isVoiceDetected: audioEngine.isVoiceDetected
                                    )
                                    .frame(height: 24)
                                    .disabled(permissionStatus != .granted)
                                    
                                    Text("\(Int(audioEngine.inputLevel)) dB")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .frame(width: 50, alignment: .trailing)
                                        .foregroundColor(audioEngine.isVoiceDetected ? .green : .primary)
                                }
                                .padding(.bottom, 4)
                            }
                            
                            // VAD threshold section  
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Text("VAD Threshold:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 100, alignment: .leading)
                                    
                                    Slider(value: $settings.vadThreshold, in: -80...0, step: 1.0) {
                                        Text("VAD Threshold")
                                    } minimumValueLabel: {
                                        Text("-80")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    } maximumValueLabel: {
                                        Text("0")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .disabled(permissionStatus != .granted)
                                    
                                    Text("\(Int(settings.vadThreshold)) dB")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .frame(width: 40, alignment: .trailing)
                                }
                            }
                            
                            Text("Adjust threshold for voice activity detection. Lower values are more sensitive.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    
                    // Test Recording
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Test Recording")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Button(action: {
                                    if isTestRecording {
                                        stopTestRecording()
                                    } else {
                                        startTestRecording()
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: isTestRecording ? "stop.circle.fill" : "play.circle.fill")
                                            .font(.system(size: 16))
                                        Text(isTestRecording ? "Stop Test" : "Start Test")
                                            .fontWeight(.medium)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(permissionStatus != .granted)
                                .accessibilityLabel(isTestRecording ? "Stop test recording" : "Start test recording")
                                .accessibilityHint("Test your microphone setup with a short recording")
                                
                                if isTestRecording {
                                    ProgressView(value: testRecordingProgress)
                                        .progressViewStyle(LinearProgressViewStyle())
                                        .frame(maxWidth: .infinity)
                                        .animation(reduceMotion ? .none : .easeInOut(duration: 0.1), value: testRecordingProgress)
                                }
                            }
                            
                            Text("Record a short test to verify your microphone setup")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    
                    // Haptic Feedback
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Haptic Feedback")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            // Enable/Disable Toggle
                            HStack {
                                Toggle(isOn: $hapticManager.isEnabled) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Enable Haptic Feedback")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text("Subtle feedback for recording events on supported devices")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .toggleStyle(SwitchToggleStyle())
                                .accessibilityLabel("Enable haptic feedback")
                                .accessibilityHint("Provides subtle haptic feedback during recording start and stop events")
                            }
                            
                            if hapticManager.isEnabled {
                                // Intensity Slider
                                VStack(spacing: 8) {
                                    HStack(spacing: 8) {
                                        Text("Intensity:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .frame(width: 60, alignment: .leading)
                                        
                                        Slider(value: $hapticManager.intensity, in: 0.1...1.0, step: 0.1) {
                                            Text("Haptic Intensity")
                                        } minimumValueLabel: {
                                            Text("Light")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        } maximumValueLabel: {
                                            Text("Strong")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .accessibilityLabel("Haptic feedback intensity")
                                        .accessibilityValue(String(format: "%.0f%%", hapticManager.intensity * 100))
                                        
                                        Text("\(Int(hapticManager.intensity * 100))%")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .frame(width: 35, alignment: .trailing)
                                    }
                                    
                                    // Test Haptic Button
                                    HStack {
                                        Button("Test Haptic") {
                                            hapticManager.testHaptic()
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .accessibilityLabel("Test haptic feedback")
                                        .accessibilityHint("Trigger a test haptic pulse to feel the current intensity setting")
                                        
                                        Spacer()
                                    }
                                }
                                .padding(.leading, 20)
                                .transition(.opacity.combined(with: .slide))
                            }
                            
                            Text("Haptic feedback is available on MacBooks with Force Touch trackpads (2015 and later models)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
            }
            
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            checkPermissionAndSetupAudio()
            refreshAvailableDevices()
            applyDeviceSelection()
            startLevelMeterTimer()
            startDeviceCheckTimer()
        }
        .onChange(of: settings.preferredInputDevice) { _ in
            // Validate device when selection changes
            validateSelectedDevice()
            
            // Apply the device selection to the audio engine
            applyDeviceSelection()
        }
        .onDisappear {
            stopLevelMeterTimer()
            stopDeviceCheckTimer()
            stopTestRecording()
            testRecordingTimer?.invalidate()
            testRecordingTimer = nil
        }
        .alert("Microphone Permission Required", isPresented: $showPermissionAlert) {
            Button("Open System Preferences") {
                openSystemPreferences()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Whisper Node needs microphone access to capture voice input. Please grant permission in System Preferences.")
        }
        .alert("Audio Information", isPresented: $showAudioError) {
            if audioErrorMessage.contains("successful") {
                Button("OK", role: .cancel) { }
            } else {
                Button("Retry") {
                    checkPermissionAndSetupAudio()
                    startLevelMeterTimer()
                }
                Button("OK", role: .cancel) { }
            }
        } message: {
            Text(audioErrorMessage)
        }
    }
    
    // MARK: - Computed Properties
    
    private var permissionIcon: String {
        switch permissionStatus {
        case .granted:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        case .undetermined:
            return "questionmark.circle.fill"
        }
    }
    
    private var permissionColor: Color {
        switch permissionStatus {
        case .granted:
            return .green
        case .denied:
            return .red
        case .undetermined:
            return .orange
        }
    }
    
    private var permissionStatusText: String {
        switch permissionStatus {
        case .granted:
            return "Permission granted"
        case .denied:
            return "Permission denied"
        case .undetermined:
            return "Permission not determined"
        }
    }
    
    // MARK: - Private Methods
    
    private func checkPermissionAndSetupAudio() {
        permissionStatus = audioEngine.checkPermissionStatus()
        
        if permissionStatus == .undetermined {
            Task {
                let granted = await audioEngine.requestPermission()
                await MainActor.run {
                    permissionStatus = granted ? .granted : .denied
                    if !granted {
                        showPermissionAlert = true
                    }
                }
            }
        }
    }
    
    private func refreshAvailableDevices() {
        availableDevices = audioEngine.getAvailableInputDevices()
        validateSelectedDevice()
    }
    
    private func validateSelectedDevice() {
        guard let selectedDeviceID = settings.preferredInputDevice else { return }
        
        // Check if the currently selected device is still available
        let isDeviceAvailable = availableDevices.contains { device in
            device.deviceID == selectedDeviceID
        }
        
        if !isDeviceAvailable {
            // Selected device is no longer available, fallback to default
            settings.preferredInputDevice = nil
            
            // Show user-friendly message about device change
            audioErrorMessage = "Selected microphone device is no longer available. Switched to default device."
            showAudioError = true
        }
    }
    
    private func applyDeviceSelection() {
        // Apply the preferred device to the audio engine
        do {
            try audioEngine.setPreferredInputDevice(settings.preferredInputDevice)
            
            // Restart audio capture with new device
            if permissionStatus == .granted {
                stopLevelMeterTimer()
                startLevelMeterTimer()
            }
        } catch {
            audioErrorMessage = "Failed to apply microphone device selection: \(error.localizedDescription)"
            showAudioError = true
        }
    }
    
    private func startLevelMeterTimer() {
        guard permissionStatus == .granted else { return }
        
        // Ensure any existing timer is invalidated first
        levelMeterTimer?.invalidate()
        
        // Start audio capture for level monitoring
        Task {
            do {
                try await audioEngine.startCapture()
                await MainActor.run {
                    // Start timer for UI updates (30fps for better performance)  
                    levelMeterTimer = Timer.scheduledTimer(withTimeInterval: Self.levelMeterUpdateInterval, repeats: true) { _ in
                        // Level updates are handled by @Published properties in audioEngine.
                        // This timer ensures continuous monitoring and UI responsiveness.
                    }
                }
            } catch {
                await MainActor.run {
                    // Handle error state in UI
                    audioErrorMessage = "Failed to start audio capture: \(error.localizedDescription)"
                    showAudioError = true
                    
                    // Check if this is a permission issue vs other error
                    let currentPermission = audioEngine.checkPermissionStatus()
                    if currentPermission != .granted {
                        permissionStatus = currentPermission
                    }
                }
                return
            }
        }
    }
    
    private func stopLevelMeterTimer() {
        levelMeterTimer?.invalidate()
        levelMeterTimer = nil
        audioEngine.stopCapture()
    }
    
    private func startDeviceCheckTimer() {
        // Check for device changes every 2 seconds
        deviceCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                refreshAvailableDevices()
            }
        }
    }
    
    private func stopDeviceCheckTimer() {
        deviceCheckTimer?.invalidate()
        deviceCheckTimer = nil
    }
    
    private func startTestRecording() {
        guard permissionStatus == .granted else { return }
        
        isTestRecording = true
        testRecordingProgress = 0.0
        testRecordingAudioData = []
        
        // Set up raw audio data capture callback for test recording (captures all audio, not just voice-detected)
        audioEngine.onRawAudioDataAvailable = { audioData in
            DispatchQueue.main.async {
                guard isTestRecording else { return }
                
                // Convert Data back to Float array for processing
                let floatArray = audioData.withUnsafeBytes { bytes in
                    Array(bytes.bindMemory(to: Float.self))
                }
                testRecordingAudioData.append(contentsOf: floatArray)
            }
        }
        
        let testDuration = Self.testRecordingDuration
        let updateInterval = Self.progressUpdateInterval
        let totalSteps = testDuration / updateInterval
        
        var currentStep = 0.0
        
        testRecordingTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { timer in
            currentStep += 1.0
            testRecordingProgress = currentStep / totalSteps
            
            if currentStep >= totalSteps {
                timer.invalidate()
                stopTestRecording()
            }
        }
    }
    
    private func stopTestRecording() {
        testRecordingTimer?.invalidate()
        testRecordingTimer = nil
        isTestRecording = false
        testRecordingProgress = 0.0
        
        // Reset raw audio data capture callback
        audioEngine.onRawAudioDataAvailable = nil
        
        // Provide feedback about the test recording
        if !testRecordingAudioData.isEmpty {
            let sampleCount = testRecordingAudioData.count
            let durationRecorded = Double(sampleCount) / 16000.0 // 16kHz sample rate
            
            // Calculate average level during recording
            let rms = sqrt(testRecordingAudioData.map { $0 * $0 }.reduce(0, +) / Float(sampleCount))
            let dbLevel = 20 * log10(max(rms, 1e-10))
            
            print("Test recording complete: \(String(format: "%.1f", durationRecorded))s, average level: \(String(format: "%.1f", dbLevel)) dB")
            
            // Show success feedback in UI if needed
            if dbLevel > -60 {
                // Good recording detected
                audioErrorMessage = "Test recording successful! Average level: \(String(format: "%.1f", dbLevel)) dB"
            } else {
                // Weak or no signal detected
                audioErrorMessage = "Test recording complete, but signal is very weak. Check microphone connection."
            }
            showAudioError = true
        } else {
            // No audio data captured
            audioErrorMessage = "No audio captured during test. Please check microphone permissions and connection."
            showAudioError = true
        }
        
        testRecordingAudioData = []
    }
    
    private func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Supporting Views

struct InputLevelMeter: View {
    let level: Float
    let vadThreshold: Float
    let isVoiceDetected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Rectangle()
                    .fill(Color(.controlBackgroundColor))
                    .cornerRadius(4)
                
                // Level bar
                Rectangle()
                    .fill(levelColor)
                    .frame(width: max(0, levelWidth(for: geometry.size.width)))
                    .cornerRadius(4)
                    .animation(reduceMotion ? .none : .easeOut(duration: 0.1), value: level)
                
                // VAD threshold indicator
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 2)
                    .offset(x: thresholdPosition(for: geometry.size.width))
                
                // Level markers
                ForEach([-60, -40, -20, 0], id: \.self) { dbValue in
                    Rectangle()
                        .fill(Color(.separatorColor))
                        .frame(width: 1)
                        .offset(x: dbToPosition(Float(dbValue), width: geometry.size.width))
                        .opacity(0.5)
                }
            }
            .overlay(
                // Level text overlays
                HStack {
                    Text("-60")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("-40")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("-20")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("0")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .offset(y: 25),
                alignment: .top
            )
        }
    }
    
    private var levelColor: Color {
        if isVoiceDetected {
            return .green
        } else if level > vadThreshold {
            return .orange
        } else {
            return .blue
        }
    }
    
    private func levelWidth(for totalWidth: CGFloat) -> CGFloat {
        let normalizedLevel = CGFloat((level + 80) / 80) // Normalize -80dB to 0dB range
        return max(0, min(1, normalizedLevel)) * totalWidth
    }
    
    private func thresholdPosition(for totalWidth: CGFloat) -> CGFloat {
        let normalizedThreshold = CGFloat((vadThreshold + 80) / 80)
        return max(0, min(1, normalizedThreshold)) * totalWidth
    }
    
    private func dbToPosition(_ db: Float, width: CGFloat) -> CGFloat {
        let normalizedDb = CGFloat((db + 80) / 80)
        return max(0, min(1, normalizedDb)) * width
    }
}

#Preview {
    VoiceTab()
        .frame(width: 480, height: 320)
}