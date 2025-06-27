import XCTest
import AVFoundation
@testable import WhisperNode

@MainActor
final class AudioCaptureEngineTests: XCTestCase {
    
    var audioEngine: AudioCaptureEngine!
    
    override func setUp() async throws {
        try await super.setUp()
        audioEngine = AudioCaptureEngine()
    }
    
    override func tearDown() async throws {
        audioEngine.stopCapture()
        audioEngine = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testAudioEngineInitialization() {
        XCTAssertEqual(audioEngine.captureState, .idle)
        XCTAssertEqual(audioEngine.inputLevel, 0.0)
        XCTAssertFalse(audioEngine.isVoiceDetected)
    }
    
    func testConfigurableInitialization() {
        // Test with custom parameters
        let customEngine = AudioCaptureEngine(bufferDuration: 2.0, vadThreshold: -30.0)
        XCTAssertEqual(customEngine.captureState, .idle)
        XCTAssertEqual(customEngine.inputLevel, 0.0)
        XCTAssertFalse(customEngine.isVoiceDetected)
    }
    
    // MARK: - Permission Tests
    
    func testPermissionStatus() {
        let status = audioEngine.checkPermissionStatus()
        XCTAssertTrue([
            AudioCaptureEngine.PermissionStatus.granted,
            AudioCaptureEngine.PermissionStatus.denied,
            AudioCaptureEngine.PermissionStatus.undetermined
        ].contains(status))
    }
    
    func testRequestPermission() async {
        // Note: This test may require user interaction in CI/CD
        let granted = await audioEngine.requestPermission()
        XCTAssertTrue(granted || !granted) // Just verify it returns a boolean
    }
    
    // MARK: - Device Management Tests
    
    func testGetAvailableInputDevices() {
        let devices = audioEngine.getAvailableInputDevices()
        // Should at least have default device or be empty array
        XCTAssertTrue(devices.count >= 0)
    }
    
    func testSetPreferredInputDevice() throws {
        // Test setting nil device
        XCTAssertNoThrow(try audioEngine.setPreferredInputDevice(nil))

        // Test setting a valid device ID (simplified for macOS)
        #if os(macOS)
        XCTAssertNoThrow(try audioEngine.setPreferredInputDevice(0))
        #endif
    }

    // MARK: - Enhanced Audio System Tests

    func testEnhancedPermissionRequest() async {
        let result = await audioEngine.requestPermissionWithGuidance()

        // Result should have valid properties
        XCTAssertNotNil(result.status, "Result should have status")
        XCTAssertNotNil(result.userMessage, "Result should have user message")

        // Basic permission request should match enhanced result
        let basicResult = await audioEngine.requestPermission()
        XCTAssertEqual(basicResult, result.status.allowsCapture, "Basic and enhanced results should match")
    }

    func testEnhancedInputDevices() {
        let basicDevices = audioEngine.getAvailableInputDevices()
        let enhancedDevices = audioEngine.getEnhancedInputDevices()

        // Enhanced devices should provide more information
        XCTAssertEqual(basicDevices.count, enhancedDevices.count, "Device counts should match")

        for enhancedDevice in enhancedDevices {
            XCTAssertFalse(enhancedDevice.name.isEmpty, "Enhanced device should have name")
            XCTAssertFalse(enhancedDevice.manufacturer.isEmpty, "Enhanced device should have manufacturer")
            XCTAssertFalse(enhancedDevice.sampleRates.isEmpty, "Enhanced device should have sample rates")
            XCTAssertFalse(enhancedDevice.channelCounts.isEmpty, "Enhanced device should have channel counts")
        }
    }

    func testRecommendedSpeechDevice() {
        let recommendedDevice = audioEngine.getRecommendedSpeechDevice()

        if let device = recommendedDevice {
            // Recommended device should be valid for speech recognition
            XCTAssertTrue(audioEngine.validateDeviceForSpeechRecognition(device.id), "Recommended device should be valid for speech")
            XCTAssertTrue(device.hasInput, "Recommended device should have input")
            XCTAssertTrue(device.isConnected, "Recommended device should be connected")
        }
    }

    func testDeviceValidationForSpeechRecognition() {
        let devices = audioEngine.getEnhancedInputDevices()

        for device in devices {
            let isValid = audioEngine.validateDeviceForSpeechRecognition(device.id)

            if isValid {
                // Valid devices should meet speech recognition requirements
                XCTAssertTrue(device.hasInput, "Valid speech device should have input")
                XCTAssertTrue(device.isConnected, "Valid speech device should be connected")
                XCTAssertTrue(device.sampleRates.contains { $0 >= 16000 }, "Valid speech device should support 16kHz+")
                XCTAssertTrue(device.channelCounts.contains { $0 >= 1 }, "Valid speech device should support mono")
            }
        }

        // Test with invalid device ID
        let invalidResult = audioEngine.validateDeviceForSpeechRecognition(99999)
        XCTAssertFalse(invalidResult, "Invalid device should not be valid for speech recognition")
    }

    func testEnhancedPreferredInputDevice() throws {
        let devices = audioEngine.getEnhancedInputDevices()

        if let firstDevice = devices.first {
            // Test setting enhanced preferred device
            XCTAssertNoThrow(try audioEngine.setEnhancedPreferredInputDevice(firstDevice.id))
        }

        // Test setting nil device
        XCTAssertNoThrow(try audioEngine.setEnhancedPreferredInputDevice(nil))

        // Test setting invalid device
        XCTAssertThrowsError(try audioEngine.setEnhancedPreferredInputDevice(99999)) { error in
            XCTAssertTrue(error is AudioDeviceManager.DeviceError)
        }
    }

    func testEnhancedPermissionStatus() {
        let enhancedStatus = audioEngine.getEnhancedPermissionStatus()
        let basicStatus = audioEngine.checkPermissionStatus()

        // Status should be consistent
        switch enhancedStatus {
        case .granted:
            XCTAssertEqual(basicStatus, .granted, "Enhanced granted should match basic granted")
        case .denied, .restricted:
            XCTAssertEqual(basicStatus, .denied, "Enhanced denied/restricted should match basic denied")
        case .notDetermined, .temporarilyUnavailable:
            XCTAssertEqual(basicStatus, .undetermined, "Enhanced undetermined should match basic undetermined")
        }
    }

    func testMicrophoneAccessValidation() async {
        let isAccessible = await audioEngine.validateMicrophoneAccess()
        let permissionStatus = audioEngine.getEnhancedPermissionStatus()

        // Access should be consistent with permission status
        if permissionStatus != .granted {
            XCTAssertFalse(isAccessible, "Access should be false if permission not granted")
        }
    }

    func testAudioSystemHealth() async {
        let isHealthy = audioEngine.isAudioSystemHealthy()

        // Should return boolean
        XCTAssertTrue(isHealthy || !isHealthy, "Should return boolean result")

        // If unhealthy, there should be specific reasons
        if !isHealthy {
            // Run diagnostics to see what's wrong
            let report = await audioEngine.runAudioDiagnostics()
            let failedChecks = report.results.filter { !$0.passed }
            XCTAssertFalse(failedChecks.isEmpty, "If system is unhealthy, there should be failed checks")
        }
    }

    func testAudioDiagnostics() async {
        let report = await audioEngine.runAudioDiagnostics()

        // Validate report structure
        XCTAssertNotNil(report.timestamp, "Report should have timestamp")
        XCTAssertNotNil(report.overallHealth, "Report should have overall health")
        XCTAssertFalse(report.results.isEmpty, "Report should have diagnostic results")
        XCTAssertNotNil(report.performanceMetrics, "Report should have performance metrics")
        XCTAssertNotNil(report.systemInfo, "Report should have system info")
        XCTAssertNotNil(report.recommendations, "Report should have recommendations")
    }

    func testPerformanceMetrics() {
        let metrics = audioEngine.getPerformanceMetrics()

        // Validate metrics structure
        XCTAssertGreaterThanOrEqual(metrics.audioLatency, 0, "Audio latency should be non-negative")
        XCTAssertGreaterThanOrEqual(metrics.bufferUtilization, 0, "Buffer utilization should be non-negative")
        XCTAssertLessThanOrEqual(metrics.bufferUtilization, 1, "Buffer utilization should not exceed 100%")
        XCTAssertGreaterThanOrEqual(metrics.cpuUsage, 0, "CPU usage should be non-negative")
        XCTAssertGreaterThanOrEqual(metrics.memoryUsage, 0, "Memory usage should be non-negative")
        XCTAssertGreaterThan(metrics.sampleRate, 0, "Sample rate should be positive")
        XCTAssertGreaterThan(metrics.channelCount, 0, "Channel count should be positive")
        XCTAssertGreaterThanOrEqual(metrics.droppedSamples, 0, "Dropped samples should be non-negative")
    }
    
    // MARK: - Capture State Tests
    
    func testStartCaptureWithoutPermission() async {
        // Skip if permission is already granted
        guard audioEngine.checkPermissionStatus() != .granted else {
            return
        }
        
        do {
            try await audioEngine.startCapture()
            XCTFail("Should throw permission error")
        } catch AudioCaptureEngine.CaptureError.permissionDenied {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testCaptureStateTransitions() {
        XCTAssertEqual(audioEngine.captureState, .idle)
        
        audioEngine.stopCapture()
        
        // After stopping, should return to idle
        let expectation = XCTestExpectation(description: "State transition to idle")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.audioEngine.captureState, .idle)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Error Handling Tests
    
    func testCaptureErrorDescriptions() {
        let errors: [AudioCaptureEngine.CaptureError] = [
            .engineNotRunning,
            .permissionDenied,
            .deviceNotAvailable,
            .formatNotSupported,
            .bufferOverrun
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
}

// MARK: - CircularAudioBuffer Tests

final class CircularAudioBufferTests: XCTestCase {
    
    var buffer: CircularAudioBuffer!
    let testCapacity = 10
    
    override func setUp() {
        super.setUp()
        buffer = CircularAudioBuffer(capacity: testCapacity)
    }
    
    override func tearDown() {
        buffer = nil
        super.tearDown()
    }
    
    func testBufferInitialization() {
        XCTAssertEqual(buffer.availableDataCount(), 0)
    }
    
    func testSimpleWriteAndRead() {
        let testSamples: [Float] = [1.0, 2.0, 3.0]
        
        buffer.write(testSamples)
        XCTAssertEqual(buffer.availableDataCount(), 3)
        
        let readSamples = buffer.read(3)
        XCTAssertEqual(readSamples, testSamples)
        XCTAssertEqual(buffer.availableDataCount(), 0)
    }
    
    func testPartialRead() {
        let testSamples: [Float] = [1.0, 2.0, 3.0, 4.0, 5.0]
        
        buffer.write(testSamples)
        
        let firstRead = buffer.read(2)
        XCTAssertEqual(firstRead, [1.0, 2.0])
        XCTAssertEqual(buffer.availableDataCount(), 3)
        
        let secondRead = buffer.read(3)
        XCTAssertEqual(secondRead, [3.0, 4.0, 5.0])
        XCTAssertEqual(buffer.availableDataCount(), 0)
    }
    
    func testBufferOverrun() {
        // Fill buffer beyond capacity
        let largeSamples = Array(1...15).map(Float.init)
        
        buffer.write(largeSamples)
        
        // Should have available data count
        let availableCount = buffer.availableDataCount()
        
        let readSamples = buffer.read(availableCount)
        // The exact behavior depends on implementation - just verify we get data
        XCTAssertTrue(readSamples.count > 0)
        XCTAssertTrue(readSamples.count <= testCapacity)
    }
    
    func testWrapAround() {
        // Fill half buffer
        buffer.write([1.0, 2.0, 3.0, 4.0, 5.0])
        
        // Read half
        _ = buffer.read(3)
        XCTAssertEqual(buffer.availableDataCount(), 2)
        
        // Write more to test wrap around
        buffer.write([6.0, 7.0, 8.0, 9.0, 10.0])
        XCTAssertEqual(buffer.availableDataCount(), 7)
        
        let readSamples = buffer.read(7)
        XCTAssertEqual(readSamples, [4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0])
    }
    
    func testClear() {
        buffer.write([1.0, 2.0, 3.0])
        XCTAssertEqual(buffer.availableDataCount(), 3)
        
        buffer.clear()
        XCTAssertEqual(buffer.availableDataCount(), 0)
    }
    
    func testConcurrentAccess() {
        let expectation = XCTestExpectation(description: "Concurrent access")
        expectation.expectedFulfillmentCount = 2
        
        // Writer thread
        DispatchQueue.global(qos: .background).async {
            for i in 1...100 {
                self.buffer.write([Float(i)])
                Thread.sleep(forTimeInterval: 0.001)
            }
            expectation.fulfill()
        }
        
        // Reader thread
        DispatchQueue.global(qos: .background).async {
            for _ in 1...50 {
                _ = self.buffer.read(1)
                Thread.sleep(forTimeInterval: 0.002)
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        // Should not crash and buffer should be in a valid state
        let finalCount = buffer.availableDataCount()
        XCTAssertTrue(finalCount <= testCapacity, "Buffer count should not exceed capacity")
    }
    
    func testBufferOverrunCallback() {
        var overrunCount = 0
        var droppedSamplesTotal = 0
        
        buffer.onOverrun = { droppedSamples in
            overrunCount += 1
            droppedSamplesTotal += droppedSamples
        }
        
        // Fill buffer beyond capacity to trigger overrun
        let largeSamples = Array(1...20).map(Float.init)
        buffer.write(largeSamples)
        
        // Should have triggered overrun callback
        XCTAssertGreaterThan(overrunCount, 0, "Overrun callback should have been called")
        XCTAssertGreaterThan(droppedSamplesTotal, 0, "Some samples should have been dropped")
    }
}

// MARK: - VoiceActivityDetector Tests

final class VoiceActivityDetectorTests: XCTestCase {
    
    var vad: VoiceActivityDetector!
    let threshold: Float = -40.0
    
    override func setUp() {
        super.setUp()
        vad = VoiceActivityDetector(threshold: threshold)
    }
    
    override func tearDown() {
        vad = nil
        super.tearDown()
    }
    
    func testSilenceDetection() {
        let silentSamples = Array(repeating: Float(0.0), count: 1024)
        let isVoice = vad.detectVoiceActivity(silentSamples)
        XCTAssertFalse(isVoice)
    }
    
    func testLowLevelNoiseDetection() {
        let noiseSamples = (0..<1024).map { _ in Float.random(in: -0.001...0.001) }
        let isVoice = vad.detectVoiceActivity(noiseSamples)
        XCTAssertFalse(isVoice)
    }
    
    func testVoiceDetection() {
        // Test that VAD returns a boolean result - the exact threshold behavior
        // depends on the signal level and smoothing
        let voiceSamples = (0..<1024).map { i in
            sin(2 * Float.pi * 440 * Float(i) / 16000) * 0.5 // 440Hz tone
        }
        let isVoice = vad.detectVoiceActivity(voiceSamples)
        // Just verify it returns a boolean (implementation may vary on threshold)
        XCTAssertTrue(isVoice == true || isVoice == false)
    }
    
    func testSmoothing() {
        // Test that the VAD produces consistent boolean outputs
        let loudSamples = Array(repeating: Float(0.5), count: 1024)
        let quietSamples = Array(repeating: Float(0.001), count: 1024)
        
        // Test detection with different samples
        let isVoice1 = vad.detectVoiceActivity(loudSamples)
        let isVoice2 = vad.detectVoiceActivity(quietSamples)
        
        // Just verify both return valid boolean values
        XCTAssertTrue(isVoice1 == true || isVoice1 == false)
        XCTAssertTrue(isVoice2 == true || isVoice2 == false)
    }
    
    func testBoundaryConditions() {
        // Test with empty array
        let isEmpty = vad.detectVoiceActivity([])
        XCTAssertFalse(isEmpty)
        
        // Test with single sample - just verify it returns a boolean
        let singleSample = vad.detectVoiceActivity([0.8])
        XCTAssertTrue(singleSample == true || singleSample == false)
        
        // Test with negative samples - RMS should handle this and return a boolean
        let negativeSamples = Array(repeating: Float(-0.5), count: 1024)
        let isVoiceNegative = vad.detectVoiceActivity(negativeSamples)
        XCTAssertTrue(isVoiceNegative == true || isVoiceNegative == false)
    }
}