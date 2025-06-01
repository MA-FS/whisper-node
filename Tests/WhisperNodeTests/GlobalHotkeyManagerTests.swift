import XCTest
import CoreGraphics
@testable import WhisperNode

final class GlobalHotkeyManagerTests: XCTestCase {
    var hotkeyManager: GlobalHotkeyManager!
    var mockDelegate: MockGlobalHotkeyManagerDelegate!
    
    override func setUpWithError() throws {
        hotkeyManager = GlobalHotkeyManager()
        mockDelegate = MockGlobalHotkeyManagerDelegate()
        hotkeyManager.delegate = mockDelegate
    }
    
    override func tearDownWithError() throws {
        hotkeyManager.stopListening()
        hotkeyManager = nil
        mockDelegate = nil
    }
    
    // MARK: - Configuration Tests
    
    func testDefaultConfiguration() {
        XCTAssertEqual(hotkeyManager.currentHotkey.keyCode, 49) // Space bar
        XCTAssertEqual(hotkeyManager.currentHotkey.modifierFlags, .maskAlternate)
        XCTAssertEqual(hotkeyManager.currentHotkey.description, "Option+Space")
    }
    
    func testUpdateHotkey() {
        let newConfig = HotkeyConfiguration(
            keyCode: 3, // F key
            modifierFlags: [.maskCommand, .maskShift],
            description: "Cmd+Shift+F"
        )
        
        hotkeyManager.updateHotkey(newConfig)
        
        XCTAssertEqual(hotkeyManager.currentHotkey, newConfig)
    }
    
    // MARK: - Conflict Detection Tests
    
    func testSystemShortcutConflictDetection() {
        // Test Cmd+Space (Spotlight) conflict
        let conflictingConfig = HotkeyConfiguration(
            keyCode: 49, // Space
            modifierFlags: .maskCommand,
            description: "Cmd+Space"
        )
        
        hotkeyManager.updateHotkey(conflictingConfig)
        
        // Should detect conflict and not update
        XCTAssertNotEqual(hotkeyManager.currentHotkey, conflictingConfig)
        XCTAssertTrue(mockDelegate.didDetectConflict)
        XCTAssertFalse(mockDelegate.suggestedAlternatives.isEmpty)
    }
    
    func testValidHotkeyNoConflict() {
        let validConfig = HotkeyConfiguration(
            keyCode: 49, // Space
            modifierFlags: [.maskAlternate, .maskShift],
            description: "Option+Shift+Space"
        )
        
        hotkeyManager.updateHotkey(validConfig)
        
        XCTAssertEqual(hotkeyManager.currentHotkey, validConfig)
        XCTAssertFalse(mockDelegate.didDetectConflict)
    }
    
    // MARK: - Recording State Tests
    
    func testInitialRecordingState() {
        XCTAssertFalse(hotkeyManager.isRecording)
    }
    
    // MARK: - Configuration Equality Tests
    
    func testHotkeyConfigurationEquality() {
        let config1 = HotkeyConfiguration(keyCode: 49, modifierFlags: .maskAlternate, description: "Option+Space")
        let config2 = HotkeyConfiguration(keyCode: 49, modifierFlags: .maskAlternate, description: "Option+Space")
        let config3 = HotkeyConfiguration(keyCode: 50, modifierFlags: .maskAlternate, description: "Option+`")
        
        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }
    
    // MARK: - Error Handling Tests
    
    func testHotkeyErrorDescriptions() {
        XCTAssertNotNil(HotkeyError.eventTapCreationFailed.errorDescription)
        XCTAssertNotNil(HotkeyError.accessibilityPermissionDenied.errorDescription)
        XCTAssertNotNil(HotkeyError.hotkeyConflict("Test").errorDescription)
    }
}

// MARK: - Mock Delegate

class MockGlobalHotkeyManagerDelegate: GlobalHotkeyManagerDelegate {
    var didStartListening = false
    var didStartRecording = false
    var didCompleteRecording = false
    var recordingDuration: CFTimeInterval = 0
    var didCancelRecording = false
    var cancelReason: RecordingCancelReason?
    var didFailWithError = false
    var error: HotkeyError?
    var accessibilityPermissionRequired = false
    var didDetectConflict = false
    var conflictDescription: String?
    var suggestedAlternatives: [HotkeyConfiguration] = []
    
    func hotkeyManager(_ manager: GlobalHotkeyManager, didStartListening: Bool) {
        self.didStartListening = true
    }
    
    func hotkeyManager(_ manager: GlobalHotkeyManager, didStartRecording: Bool) {
        self.didStartRecording = true
    }
    
    func hotkeyManager(_ manager: GlobalHotkeyManager, didCompleteRecording duration: CFTimeInterval) {
        didCompleteRecording = true
        recordingDuration = duration
    }
    
    func hotkeyManager(_ manager: GlobalHotkeyManager, didCancelRecording reason: RecordingCancelReason) {
        didCancelRecording = true
        cancelReason = reason
    }
    
    func hotkeyManager(_ manager: GlobalHotkeyManager, didFailWithError error: HotkeyError) {
        didFailWithError = true
        self.error = error
    }
    
    func hotkeyManager(_ manager: GlobalHotkeyManager, accessibilityPermissionRequired: Bool) {
        self.accessibilityPermissionRequired = accessibilityPermissionRequired
    }
    
    func hotkeyManager(_ manager: GlobalHotkeyManager, didDetectConflict conflict: HotkeyConflict, suggestedAlternatives: [HotkeyConfiguration]) {
        didDetectConflict = true
        conflictDescription = conflict.description
        self.suggestedAlternatives = suggestedAlternatives
    }
}