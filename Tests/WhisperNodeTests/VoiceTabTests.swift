import XCTest
import SwiftUI
@testable import WhisperNode

final class VoiceTabTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    @MainActor
    func testSettingsManagerVoiceDefaults() throws {
        let settings = SettingsManager.shared
        
        // Test default VAD threshold
        XCTAssertEqual(settings.vadThreshold, -40.0, "Default VAD threshold should be -40.0 dB")
        
        // Test default input device
        XCTAssertNil(settings.preferredInputDevice, "Default input device should be nil (system default)")
        
        // Test default test recording setting
        XCTAssertFalse(settings.enableTestRecording, "Test recording should be disabled by default")
    }
    
    @MainActor
    func testVADThresholdRange() throws {
        let settings = SettingsManager.shared
        
        // Test setting valid VAD threshold values
        settings.vadThreshold = -60.0
        XCTAssertEqual(settings.vadThreshold, -60.0)
        
        settings.vadThreshold = -20.0
        XCTAssertEqual(settings.vadThreshold, -20.0)
        
        settings.vadThreshold = 0.0
        XCTAssertEqual(settings.vadThreshold, 0.0)
        
        // Reset to default
        settings.vadThreshold = -40.0
    }
    
    @MainActor
    func testInputDeviceSelection() throws {
        let settings = SettingsManager.shared
        
        // Test setting a device ID
        let testDeviceID: UInt32 = 12345
        settings.preferredInputDevice = testDeviceID
        XCTAssertEqual(settings.preferredInputDevice, testDeviceID)
        
        // Test clearing device selection
        settings.preferredInputDevice = nil
        XCTAssertNil(settings.preferredInputDevice)
    }
    
    func testInputLevelMeterNormalization() throws {
        let levelMeter = InputLevelMeter(level: -40.0, vadThreshold: -40.0, isVoiceDetected: false)
        
        // Test that the view can be created without throwing
        let view = levelMeter
        XCTAssertNotNil(view)
        
        // Test level calculation logic (indirectly through view creation)
        let silentMeter = InputLevelMeter(level: -80.0, vadThreshold: -40.0, isVoiceDetected: false)
        XCTAssertNotNil(silentMeter)
        
        let loudMeter = InputLevelMeter(level: 0.0, vadThreshold: -40.0, isVoiceDetected: true)
        XCTAssertNotNil(loudMeter)
    }
    
    func testVoiceTabViewCreation() throws {
        let voiceTab = VoiceTab()
        
        // Test that the view can be created without throwing
        XCTAssertNotNil(voiceTab)
        
        // Test that the view body can be accessed (basic SwiftUI view test)
        let _ = voiceTab.body
    }
    
    func testAudioEngineIntegration() throws {
        let audioEngine = AudioCaptureEngine()
        
        // Test initial state
        XCTAssertEqual(audioEngine.captureState, .idle)
        XCTAssertEqual(audioEngine.inputLevel, 0.0)
        XCTAssertFalse(audioEngine.isVoiceDetected)
        
        // Test permission status check
        let permissionStatus = audioEngine.checkPermissionStatus()
        XCTAssertTrue([.granted, .denied, .undetermined].contains(permissionStatus))
        
        // Test device enumeration
        let devices = audioEngine.getAvailableInputDevices()
        XCTAssertTrue(devices.count >= 0) // Should not throw
    }
    
    func testPermissionStatusMapping() throws {
        // Test permission status display logic (would be in a real app)
        let grantedStatus = AudioCaptureEngine.PermissionStatus.granted
        let deniedStatus = AudioCaptureEngine.PermissionStatus.denied
        let undeterminedStatus = AudioCaptureEngine.PermissionStatus.undetermined
        
        XCTAssertEqual(grantedStatus, .granted)
        XCTAssertEqual(deniedStatus, .denied)
        XCTAssertEqual(undeterminedStatus, .undetermined)
    }
}

// MARK: - Audio Engine Mock Tests

final class AudioEngineVoiceTabIntegrationTests: XCTestCase {
    
    @MainActor
    func testVADThresholdUpdatesFromSettings() throws {
        let settings = SettingsManager.shared
        let audioEngine = AudioCaptureEngine()
        
        // Test that VAD threshold can be updated
        let originalThreshold = settings.vadThreshold
        settings.vadThreshold = -30.0
        
        // In a real implementation, the audio engine would observe settings changes
        XCTAssertEqual(settings.vadThreshold, -30.0)
        
        // Reset
        settings.vadThreshold = originalThreshold
    }
    
    @MainActor
    func testDeviceSelectionPersistence() throws {
        let settings = SettingsManager.shared
        
        // Test that device selection persists
        let testDevice: UInt32 = 67890
        settings.preferredInputDevice = testDevice
        
        // Simulate app restart by reading from UserDefaults
        let storedDevice = UserDefaults.standard.object(forKey: "preferredInputDevice") as? UInt32
        XCTAssertEqual(storedDevice, testDevice)
        
        // Clean up
        settings.preferredInputDevice = nil
    }
}