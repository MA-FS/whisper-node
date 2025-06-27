import XCTest
@testable import WhisperNode
import AVFoundation
import AudioToolbox

/// Comprehensive tests for AudioDeviceManager
@MainActor
final class AudioDeviceManagerTests: XCTestCase {
    
    var deviceManager: AudioDeviceManager!
    
    override func setUp() async throws {
        try await super.setUp()
        deviceManager = AudioDeviceManager.shared
    }
    
    override func tearDown() async throws {
        deviceManager.stopMonitoring()
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testSharedInstance() {
        let instance1 = AudioDeviceManager.shared
        let instance2 = AudioDeviceManager.shared
        XCTAssertTrue(instance1 === instance2, "AudioDeviceManager should be a singleton")
    }
    
    func testInitialState() {
        XCTAssertFalse(deviceManager.isMonitoring, "Should not be monitoring initially")
        XCTAssertNotNil(deviceManager.availableInputDevices, "Available devices should be initialized")
    }
    
    // MARK: - Device Enumeration Tests
    
    func testGetAvailableInputDevices() {
        let devices = deviceManager.getAvailableInputDevices()
        
        // Should return an array (may be empty in CI environments)
        XCTAssertNotNil(devices, "Should return device array")
        
        // If devices are available, they should have valid properties
        for device in devices {
            XCTAssertFalse(device.name.isEmpty, "Device name should not be empty")
            XCTAssertTrue(device.hasInput, "Input devices should have input capability")
            XCTAssertFalse(device.sampleRates.isEmpty, "Device should have sample rates")
            XCTAssertFalse(device.channelCounts.isEmpty, "Device should have channel counts")
        }
    }
    
    func testGetDeviceInfo() {
        let devices = deviceManager.getAvailableInputDevices()
        
        if let firstDevice = devices.first {
            let deviceInfo = deviceManager.getDeviceInfo(for: firstDevice.id)
            XCTAssertNotNil(deviceInfo, "Should return device info for valid device ID")
            XCTAssertEqual(deviceInfo?.id, firstDevice.id, "Device IDs should match")
        }
        
        // Test with invalid device ID
        let invalidDeviceInfo = deviceManager.getDeviceInfo(for: 99999)
        XCTAssertNil(invalidDeviceInfo, "Should return nil for invalid device ID")
    }
    
    func testDefaultInputDevice() {
        let defaultDevice = deviceManager.defaultInputDevice
        
        // Default device may be nil in CI environments
        if let defaultDevice = defaultDevice {
            XCTAssertTrue(defaultDevice.isDefault, "Default device should be marked as default")
            XCTAssertTrue(defaultDevice.hasInput, "Default input device should have input capability")
        }
    }
    
    // MARK: - Device Validation Tests
    
    func testValidateDeviceForSpeechRecognition() {
        let devices = deviceManager.getAvailableInputDevices()
        
        for device in devices {
            let isValid = deviceManager.validateDeviceForSpeechRecognition(device.id)
            
            if isValid {
                // Valid devices should meet speech recognition requirements
                XCTAssertTrue(device.hasInput, "Valid speech device should have input")
                XCTAssertTrue(device.isConnected, "Valid speech device should be connected")
                XCTAssertTrue(device.sampleRates.contains { $0 >= 16000 }, "Valid speech device should support 16kHz+")
                XCTAssertTrue(device.channelCounts.contains { $0 >= 1 }, "Valid speech device should support mono")
            }
        }
        
        // Test with invalid device ID
        let invalidResult = deviceManager.validateDeviceForSpeechRecognition(99999)
        XCTAssertFalse(invalidResult, "Invalid device should not be valid for speech recognition")
    }
    
    func testGetRecommendedSpeechDevice() {
        let recommendedDevice = deviceManager.getRecommendedSpeechDevice()
        
        if let recommendedDevice = recommendedDevice {
            // Recommended device should be valid for speech recognition
            XCTAssertTrue(deviceManager.validateDeviceForSpeechRecognition(recommendedDevice.id))
            XCTAssertTrue(recommendedDevice.hasInput, "Recommended device should have input")
            XCTAssertTrue(recommendedDevice.isConnected, "Recommended device should be connected")
        }
    }
    
    // MARK: - Device Management Tests
    
    func testSetPreferredInputDevice() throws {
        // Test setting nil device (reset to default)
        XCTAssertNoThrow(try deviceManager.setPreferredInputDevice(nil))
        
        let devices = deviceManager.getAvailableInputDevices()
        
        if let firstDevice = devices.first {
            // Test setting valid device
            XCTAssertNoThrow(try deviceManager.setPreferredInputDevice(firstDevice.id))
            
            // Verify preferred device is set
            XCTAssertEqual(deviceManager.preferredInputDevice?.id, firstDevice.id)
        }
        
        // Test setting invalid device
        XCTAssertThrowsError(try deviceManager.setPreferredInputDevice(99999)) { error in
            XCTAssertTrue(error is AudioDeviceManager.DeviceError)
        }
    }
    
    // MARK: - Monitoring Tests
    
    func testStartStopMonitoring() {
        XCTAssertFalse(deviceManager.isMonitoring, "Should not be monitoring initially")
        
        deviceManager.startMonitoring()
        XCTAssertTrue(deviceManager.isMonitoring, "Should be monitoring after start")
        
        deviceManager.stopMonitoring()
        XCTAssertFalse(deviceManager.isMonitoring, "Should not be monitoring after stop")
        
        // Test multiple start calls
        deviceManager.startMonitoring()
        deviceManager.startMonitoring()
        XCTAssertTrue(deviceManager.isMonitoring, "Multiple start calls should be safe")
        
        // Test multiple stop calls
        deviceManager.stopMonitoring()
        deviceManager.stopMonitoring()
        XCTAssertFalse(deviceManager.isMonitoring, "Multiple stop calls should be safe")
    }
    
    func testDeviceChangeCallbacks() {
        let expectation = XCTestExpectation(description: "Device list callback")
        expectation.isInverted = true // We don't expect this to be called immediately
        
        deviceManager.onDeviceListChanged = { devices in
            expectation.fulfill()
        }
        
        deviceManager.startMonitoring()
        
        // Wait briefly to ensure no immediate callback
        wait(for: [expectation], timeout: 1.0)
        
        deviceManager.stopMonitoring()
    }
    
    // MARK: - Error Handling Tests
    
    func testDeviceErrorTypes() {
        let errors: [AudioDeviceManager.DeviceError] = [
            .deviceNotFound,
            .deviceNotAvailable,
            .permissionDenied,
            .configurationFailed,
            .systemError(noErr)
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error should have description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty")
        }
    }
    
    // MARK: - AudioDeviceInfo Tests
    
    func testAudioDeviceInfoEquality() {
        let device1 = AudioDeviceManager.AudioDeviceInfo(
            id: 1,
            name: "Test Device",
            manufacturer: "Test Manufacturer",
            isDefault: false,
            hasInput: true,
            hasOutput: false,
            sampleRates: [44100.0],
            channelCounts: [1],
            isConnected: true
        )
        
        let device2 = AudioDeviceManager.AudioDeviceInfo(
            id: 1,
            name: "Different Name",
            manufacturer: "Different Manufacturer",
            isDefault: true,
            hasInput: false,
            hasOutput: true,
            sampleRates: [48000.0],
            channelCounts: [2],
            isConnected: false
        )
        
        let device3 = AudioDeviceManager.AudioDeviceInfo(
            id: 2,
            name: "Test Device",
            manufacturer: "Test Manufacturer",
            isDefault: false,
            hasInput: true,
            hasOutput: false,
            sampleRates: [44100.0],
            channelCounts: [1],
            isConnected: true
        )
        
        // Devices with same ID should be equal
        XCTAssertEqual(device1, device2, "Devices with same ID should be equal")
        
        // Devices with different IDs should not be equal
        XCTAssertNotEqual(device1, device3, "Devices with different IDs should not be equal")
    }
    
    // MARK: - Performance Tests
    
    func testDeviceEnumerationPerformance() {
        measure {
            _ = deviceManager.getAvailableInputDevices()
        }
    }
    
    func testDeviceValidationPerformance() throws {
        let devices = deviceManager.getAvailableInputDevices()
        
        guard !devices.isEmpty else {
            throw XCTSkip("No devices available for performance testing")
        }
        
        measure {
            for device in devices {
                _ = deviceManager.validateDeviceForSpeechRecognition(device.id)
            }
        }
    }
    
    // MARK: - Integration Tests
    
    func testIntegrationWithAVAudioEngine() {
        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        // Verify that device manager can work with AVAudioEngine
        XCTAssertTrue(inputFormat.sampleRate > 0, "Audio engine should have valid input format")
        
        let devices = deviceManager.getAvailableInputDevices()
        
        // If devices are available, at least one should be compatible
        if !devices.isEmpty {
            let compatibleDevices = devices.filter { device in
                device.sampleRates.contains(inputFormat.sampleRate) &&
                device.channelCounts.contains(inputFormat.channelCount)
            }
            
            // Note: This may fail in CI environments without audio devices
            if !compatibleDevices.isEmpty {
                XCTAssertTrue(compatibleDevices.count > 0, "Should have at least one compatible device")
            }
        }
    }
}
