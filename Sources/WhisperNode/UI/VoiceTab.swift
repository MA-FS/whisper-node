import SwiftUI
import AVFoundation
import CoreAudio

struct VoiceTab: View {
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var audioEngine = AudioCaptureEngine.shared
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

                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("\(Int(audioEngine.inputLevel)) dB")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .frame(width: 50, alignment: .trailing)
                                            .foregroundColor(audioEngine.isVoiceDetected ? .green : .primary)

                                        // Audio engine status indicator
                                        Text(audioEngineStatusText)
                                            .font(.caption2)
                                            .foregroundColor(audioEngineStatusColor)
                                            .frame(width: 50, alignment: .trailing)
                                    }
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
                                        stopTestRecording(showResults: true)
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
            Task {
                await checkPermissionAndSetupAudio()
                refreshAvailableDevices()
                applyDeviceSelection()
                // Only start level meter after permission is confirmed
                if permissionStatus == .granted {
                    startLevelMeterTimer()
                }
                startDeviceCheckTimer()
            }
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
            // Only stop test recording if one is actually in progress
            if isTestRecording {
                stopTestRecording(showResults: false) // Don't show results during tab navigation
            }
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
                    Task {
                        await checkPermissionAndSetupAudio()
                        if permissionStatus == .granted {
                            startLevelMeterTimer()
                        }
                    }
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

    private var audioEngineStatusText: String {
        switch audioEngine.captureState {
        case .idle: return "Idle"
        case .starting: return "Starting"
        case .recording: return "Active"
        case .stopping: return "Stopping"
        case .error: return "Error"
        }
    }

    private var audioEngineStatusColor: Color {
        switch audioEngine.captureState {
        case .idle: return .secondary
        case .starting: return .orange
        case .recording: return .green
        case .stopping: return .orange
        case .error: return .red
        }
    }

    // MARK: - Private Methods
    
    private func checkPermissionAndSetupAudio() async {
        permissionStatus = audioEngine.checkPermissionStatus()

        if permissionStatus == .undetermined {
            let granted = await audioEngine.requestPermission()
            await MainActor.run {
                permissionStatus = granted ? .granted : .denied
                if !granted {
                    showPermissionAlert = true
                } else {
                    // Permission granted - immediately start level meter
                    print("VoiceTab: Permission granted, starting level meter immediately")
                    startLevelMeterTimer()
                }
            }
        } else if permissionStatus == .granted {
            // Permission already granted - ensure level meter is running
            print("VoiceTab: Permission already granted, ensuring level meter is running")
            startLevelMeterTimer()
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
        guard permissionStatus == .granted else {
            print("VoiceTab: Cannot start level meter - permission not granted: \(permissionStatus)")
            return
        }

        // Ensure any existing timer is invalidated first
        levelMeterTimer?.invalidate()

        print("VoiceTab: Starting audio capture for level monitoring...")

        // Start audio capture for level monitoring
        Task {
            do {
                try await audioEngine.startCapture()
                await MainActor.run {
                    print("VoiceTab: Audio capture started successfully, starting UI update timer")

                    // Start timer for UI updates (30fps for better performance)
                    levelMeterTimer = Timer.scheduledTimer(withTimeInterval: Self.levelMeterUpdateInterval, repeats: true) { _ in
                        // Force UI updates by accessing the published properties
                        // This ensures the UI stays responsive and reflects current audio levels
                        Task { @MainActor in
                            // Trigger UI update by accessing the published properties
                            let currentLevel = audioEngine.inputLevel
                            let isVoiceActive = audioEngine.isVoiceDetected
                            let captureState = audioEngine.captureState

                            // Debug logging (can be removed in production)
                            if Int.random(in: 1...90) == 1 { // Log every ~3 seconds at 30fps
                                print("VoiceTab: Audio level: \(String(format: "%.1f", currentLevel)) dB, Voice: \(isVoiceActive), State: \(captureState)")
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    print("VoiceTab: Failed to start audio capture: \(error)")

                    // Handle error state in UI
                    audioErrorMessage = "Failed to start audio capture: \(error.localizedDescription)"
                    showAudioError = true

                    // Check if this is a permission issue vs other error
                    let currentPermission = audioEngine.checkPermissionStatus()
                    if currentPermission != .granted {
                        permissionStatus = currentPermission
                        print("VoiceTab: Permission issue detected: \(currentPermission)")
                    }
                }
                return
            }
        }
    }
    
    private func stopLevelMeterTimer() {
        print("VoiceTab: Stopping level meter timer and audio capture")
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
        guard permissionStatus == .granted else {
            print("VoiceTab: Cannot start test recording - permission not granted")
            return
        }

        print("VoiceTab: Starting test recording...")
        isTestRecording = true
        testRecordingProgress = 0.0
        testRecordingAudioData = []

        // Ensure audio capture is running for test recording
        if audioEngine.captureState != .recording {
            print("VoiceTab: Audio engine not recording, attempting to start...")
            Task {
                do {
                    try await audioEngine.startCapture()
                    print("VoiceTab: Audio capture started for test recording")
                } catch {
                    await MainActor.run {
                        print("VoiceTab: Failed to start audio capture for test recording: \(error)")
                        audioErrorMessage = "Failed to start audio capture for test recording: \(error.localizedDescription)"
                        showAudioError = true
                        stopTestRecording(showResults: false)
                    }
                    return
                }
            }
        }

        // Set up raw audio data capture callback for test recording (captures all audio, not just voice-detected)
        audioEngine.onRawAudioDataAvailable = { audioData in
            DispatchQueue.main.async {
                guard isTestRecording else { return }

                // Convert Data back to Float array for processing
                let floatArray = audioData.withUnsafeBytes { bytes in
                    Array(bytes.bindMemory(to: Float.self))
                }
                testRecordingAudioData.append(contentsOf: floatArray)

                // Log progress occasionally
                if testRecordingAudioData.count % 8000 == 0 { // Every ~0.5 seconds at 16kHz
                    let duration = Double(testRecordingAudioData.count) / 16000.0
                    print("VoiceTab: Test recording captured \(String(format: "%.1f", duration))s of audio")
                }
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
                stopTestRecording(showResults: true)
            }
        }
    }
    
    private func stopTestRecording(showResults: Bool = true) {
        print("VoiceTab: Stopping test recording (showResults: \(showResults))...")
        testRecordingTimer?.invalidate()
        testRecordingTimer = nil
        isTestRecording = false
        testRecordingProgress = 0.0

        // Reset raw audio data capture callback
        audioEngine.onRawAudioDataAvailable = nil

        // If not showing results (e.g., during tab navigation), just clean up and return
        guard showResults else {
            print("VoiceTab: Test recording cleanup completed without showing results")
            testRecordingAudioData = []
            return
        }

        // Provide detailed feedback about the test recording
        if !testRecordingAudioData.isEmpty {
            let sampleCount = testRecordingAudioData.count
            let durationRecorded = Double(sampleCount) / 16000.0 // 16kHz sample rate

            // Calculate average level during recording
            let rms = sqrt(testRecordingAudioData.map { $0 * $0 }.reduce(0, +) / Float(sampleCount))
            let dbLevel = 20 * log10(max(rms, 1e-10))

            // Calculate peak level
            let peak = testRecordingAudioData.max() ?? 0.0
            let peakDb = 20 * log10(max(peak, 1e-10))

            print("VoiceTab: Test recording complete - Duration: \(String(format: "%.1f", durationRecorded))s, Avg: \(String(format: "%.1f", dbLevel)) dB, Peak: \(String(format: "%.1f", peakDb)) dB")

            // Determine quality and provide helpful feedback
            let qualityMessage: String
            if dbLevel > -20 {
                qualityMessage = "Excellent signal level!"
            } else if dbLevel > -40 {
                qualityMessage = "Good signal level."
            } else if dbLevel > -60 {
                qualityMessage = "Low signal level - consider moving closer to the microphone."
            } else {
                qualityMessage = "Very low signal level - check microphone connection and volume."
            }

            audioErrorMessage = """
            Test recording successful!

            Duration: \(String(format: "%.1f", durationRecorded)) seconds
            Average level: \(String(format: "%.1f", dbLevel)) dB
            Peak level: \(String(format: "%.1f", peakDb)) dB

            \(qualityMessage)
            """
            showAudioError = true
        } else {
            print("VoiceTab: Test recording failed - no audio data captured")
            audioErrorMessage = """
            Test recording failed - no audio data captured.

            Possible causes:
            • Microphone permission not granted
            • Microphone not connected or selected
            • Audio input device not working
            • System audio settings issue

            Please check your microphone settings and try again.
            """
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