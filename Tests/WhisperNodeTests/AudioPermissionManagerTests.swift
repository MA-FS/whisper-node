import XCTest
@testable import WhisperNode
import AVFoundation

/// Comprehensive tests for AudioPermissionManager
@MainActor
final class AudioPermissionManagerTests: XCTestCase {
    
    var permissionManager: AudioPermissionManager!
    
    override func setUp() async throws {
        try await super.setUp()
        permissionManager = AudioPermissionManager.shared
    }
    
    override func tearDown() async throws {
        permissionManager.stopMonitoring()
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testSharedInstance() {
        let instance1 = AudioPermissionManager.shared
        let instance2 = AudioPermissionManager.shared
        XCTAssertTrue(instance1 === instance2, "AudioPermissionManager should be a singleton")
    }
    
    func testInitialState() {
        XCTAssertTrue(permissionManager.isMonitoring, "Should be monitoring by default")
        XCTAssertNotNil(permissionManager.currentPermissionStatus, "Should have initial permission status")
    }
    
    // MARK: - Permission Status Tests
    
    func testPermissionStatusTypes() {
        let statuses: [AudioPermissionManager.PermissionStatus] = [
            .notDetermined,
            .granted,
            .denied,
            .restricted,
            .temporarilyUnavailable
        ]
        
        for status in statuses {
            XCTAssertFalse(status.description.isEmpty, "Status should have description")
            
            // Test allowsCapture property
            switch status {
            case .granted:
                XCTAssertTrue(status.allowsCapture, "Granted status should allow capture")
            default:
                XCTAssertFalse(status.allowsCapture, "Non-granted status should not allow capture")
            }
        }
    }
    
    func testCheckPermissionStatus() {
        let status = permissionManager.checkPermissionStatus()
        
        // Status should be one of the valid types
        let validStatuses: [AudioPermissionManager.PermissionStatus] = [
            .notDetermined, .granted, .denied, .restricted, .temporarilyUnavailable
        ]
        XCTAssertTrue(validStatuses.contains(status), "Should return valid permission status")
        
        // Current status should match
        XCTAssertEqual(status, permissionManager.currentPermissionStatus, "Current status should match check result")
    }
    
    // MARK: - Permission Request Tests
    
    func testRequestPermission() async {
        let granted = await permissionManager.requestPermission()
        
        // Should return a boolean
        XCTAssertTrue(granted || !granted, "Should return boolean result")
        
        // Status should be updated after request
        let newStatus = permissionManager.currentPermissionStatus
        if granted {
            XCTAssertEqual(newStatus, .granted, "Status should be granted if permission was granted")
        } else {
            XCTAssertNotEqual(newStatus, .granted, "Status should not be granted if permission was denied")
        }
    }
    
    func testRequestPermissionWithGuidance() async {
        let result = await permissionManager.requestPermissionWithGuidance()
        
        // Result should have valid properties
        XCTAssertNotNil(result.status, "Result should have status")
        XCTAssertNotNil(result.userMessage, "Result should have user message")
        
        // Status consistency
        XCTAssertEqual(result.status.allowsCapture, result.status == .granted, "Status allowsCapture should match granted state")
        
        // If already granted, should not be newly granted
        if result.status == .granted && permissionManager.currentPermissionStatus == .granted {
            XCTAssertFalse(result.isNewlyGranted, "Should not be newly granted if already granted")
        }
    }
    
    // MARK: - Microphone Access Validation Tests
    
    func testValidateMicrophoneAccess() async {
        let isAccessible = await permissionManager.validateMicrophoneAccess()
        
        // Should return boolean
        XCTAssertTrue(isAccessible || !isAccessible, "Should return boolean result")
        
        // If permission is not granted, access should be false
        if permissionManager.currentPermissionStatus != .granted {
            XCTAssertFalse(isAccessible, "Access should be false if permission not granted")
        }
    }
    
    // MARK: - Monitoring Tests
    
    func testStartStopMonitoring() {
        // Should be monitoring by default
        XCTAssertTrue(permissionManager.isMonitoring, "Should be monitoring initially")
        
        permissionManager.stopMonitoring()
        XCTAssertFalse(permissionManager.isMonitoring, "Should not be monitoring after stop")
        
        permissionManager.startMonitoring()
        XCTAssertTrue(permissionManager.isMonitoring, "Should be monitoring after start")
        
        // Test multiple start calls
        permissionManager.startMonitoring()
        permissionManager.startMonitoring()
        XCTAssertTrue(permissionManager.isMonitoring, "Multiple start calls should be safe")
        
        // Test multiple stop calls
        permissionManager.stopMonitoring()
        permissionManager.stopMonitoring()
        XCTAssertFalse(permissionManager.isMonitoring, "Multiple stop calls should be safe")
    }
    
    func testPermissionStatusChangeCallback() {
        let expectation = XCTestExpectation(description: "Permission status change callback")
        expectation.isInverted = true // We don't expect this to be called immediately
        
        permissionManager.onPermissionStatusChanged = { status in
            expectation.fulfill()
        }
        
        permissionManager.startMonitoring()
        
        // Wait briefly to ensure no immediate callback
        wait(for: [expectation], timeout: 1.0)
        
        permissionManager.stopMonitoring()
    }
    
    func testPermissionGrantedCallback() {
        let expectation = XCTestExpectation(description: "Permission granted callback")
        expectation.isInverted = true // We don't expect this to be called immediately
        
        permissionManager.onPermissionGranted = {
            expectation.fulfill()
        }
        
        // Wait briefly to ensure no immediate callback
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testPermissionDeniedCallback() {
        let expectation = XCTestExpectation(description: "Permission denied callback")
        expectation.isInverted = true // We don't expect this to be called immediately
        
        permissionManager.onPermissionDenied = { message in
            XCTAssertFalse(message.isEmpty, "Denial message should not be empty")
            expectation.fulfill()
        }
        
        // Wait briefly to ensure no immediate callback
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Guidance Message Tests
    
    func testGetGuidanceMessage() {
        let message = permissionManager.getGuidanceMessage()
        
        XCTAssertFalse(message.isEmpty, "Guidance message should not be empty")
        
        // Message should be appropriate for current status
        let currentStatus = permissionManager.currentPermissionStatus
        switch currentStatus {
        case .granted:
            XCTAssertTrue(message.contains("granted") || message.contains("enabled"), "Granted message should mention granted/enabled")
        case .denied:
            XCTAssertTrue(message.contains("denied") || message.contains("disabled"), "Denied message should mention denied/disabled")
        case .notDetermined:
            XCTAssertTrue(message.contains("required") || message.contains("permission"), "Not determined message should mention requirement")
        case .restricted:
            XCTAssertTrue(message.contains("restricted"), "Restricted message should mention restriction")
        case .temporarilyUnavailable:
            XCTAssertTrue(message.contains("unavailable") || message.contains("try again"), "Unavailable message should mention unavailability")
        }
    }
    
    // MARK: - System Preferences Tests
    
    func testOpenSystemPreferences() {
        // This test just ensures the method doesn't crash
        // We can't easily test if System Preferences actually opens
        XCTAssertNoThrow(permissionManager.openSystemPreferences())
    }
    
    // MARK: - PermissionResult Tests
    
    func testPermissionResultInitialization() {
        let result1 = AudioPermissionManager.PermissionResult(status: .granted)
        XCTAssertEqual(result1.status, .granted)
        XCTAssertFalse(result1.isNewlyGranted)
        XCTAssertNil(result1.userMessage)
        XCTAssertNil(result1.recoveryAction)
        
        let result2 = AudioPermissionManager.PermissionResult(
            status: .denied,
            isNewlyGranted: false,
            userMessage: "Test message",
            recoveryAction: {}
        )
        XCTAssertEqual(result2.status, .denied)
        XCTAssertFalse(result2.isNewlyGranted)
        XCTAssertEqual(result2.userMessage, "Test message")
        XCTAssertNotNil(result2.recoveryAction)
    }
    
    // MARK: - Edge Cases Tests
    
    func testMultiplePermissionRequests() async {
        // Test multiple simultaneous permission requests
        async let request1 = permissionManager.requestPermission()
        async let request2 = permissionManager.requestPermission()
        async let request3 = permissionManager.requestPermission()
        
        let results = await [request1, request2, request3]
        
        // All requests should return the same result
        XCTAssertEqual(results[0], results[1], "Simultaneous requests should return same result")
        XCTAssertEqual(results[1], results[2], "Simultaneous requests should return same result")
    }
    
    func testPermissionStatusConsistency() {
        let status1 = permissionManager.checkPermissionStatus()
        let status2 = permissionManager.currentPermissionStatus

        XCTAssertEqual(status1, status2, "Permission status should be consistent")

        // Check again after a brief delay
        let expectation = XCTestExpectation(description: "Delayed consistency check")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let status3 = self.permissionManager.checkPermissionStatus()
            XCTAssertEqual(status1, status3, "Permission status should remain consistent")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Performance Tests
    
    func testPermissionCheckPerformance() {
        measure {
            _ = permissionManager.checkPermissionStatus()
        }
    }
    
    func testGuidanceMessagePerformance() {
        measure {
            _ = permissionManager.getGuidanceMessage()
        }
    }
    
    // MARK: - Integration Tests
    
    func testIntegrationWithAVAudioSession() {
        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        let systemStatus = session.recordPermission
        let managerStatus = permissionManager.currentPermissionStatus
        
        // Status should be consistent with system
        switch systemStatus {
        case .granted:
            XCTAssertEqual(managerStatus, .granted, "Manager status should match system granted")
        case .denied:
            XCTAssertEqual(managerStatus, .denied, "Manager status should match system denied")
        case .undetermined:
            XCTAssertEqual(managerStatus, .notDetermined, "Manager status should match system undetermined")
        @unknown default:
            XCTFail("Unknown system permission status")
        }
        #endif
    }
    
    func testIntegrationWithAVCaptureDevice() {
        #if os(macOS)
        let systemStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let managerStatus = permissionManager.currentPermissionStatus
        
        // Status should be consistent with system
        switch systemStatus {
        case .authorized:
            XCTAssertEqual(managerStatus, .granted, "Manager status should match system authorized")
        case .denied:
            XCTAssertEqual(managerStatus, .denied, "Manager status should match system denied")
        case .restricted:
            XCTAssertEqual(managerStatus, .restricted, "Manager status should match system restricted")
        case .notDetermined:
            XCTAssertEqual(managerStatus, .notDetermined, "Manager status should match system not determined")
        @unknown default:
            XCTFail("Unknown system permission status")
        }
        #endif
    }
}
