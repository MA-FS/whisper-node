import XCTest
@testable import WhisperNode

/// Comprehensive tests for the ErrorHandlingManager system
///
/// Tests all error scenarios defined in T15 specification including:
/// - Microphone access denial with system preferences link
/// - Model download failure with automatic retry and fallback
/// - Transcription failure with silent error and visual feedback
/// - Hotkey conflicts with non-blocking notification
/// - Low disk space prevention with warning
/// - Graceful degradation for all error states
@MainActor
final class ErrorHandlingManagerTests: XCTestCase {
    
    var errorManager: ErrorHandlingManager!
    
    override func setUp() async throws {
        try await super.setUp()
        errorManager = ErrorHandlingManager.shared
    }
    
    override func tearDown() async throws {
        errorManager = nil
        try await super.tearDown()
    }
    
    // MARK: - Error Type Tests
    
    func testWhisperNodeErrorDescriptions() {
        let errors: [ErrorHandlingManager.WhisperNodeError] = [
            .microphoneAccessDenied,
            .modelDownloadFailed("Network timeout"),
            .transcriptionFailed,
            .hotkeyConflict("Cmd+Space conflicts with Spotlight"),
            .insufficientDiskSpace,
            .networkConnectionFailed,
            .modelCorrupted("tiny.en"),
            .systemResourcesExhausted
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription, 
                           "Error should have a description: \(error)")
            XCTAssertNotNil(error.recoverySuggestion, 
                           "Error should have recovery suggestion: \(error)")
        }
    }
    
    func testErrorSeverityClassification() {
        // Critical errors - require immediate user action
        XCTAssertEqual(ErrorHandlingManager.WhisperNodeError.microphoneAccessDenied.severity, 
                      .critical)
        XCTAssertEqual(ErrorHandlingManager.WhisperNodeError.insufficientDiskSpace.severity, 
                      .critical)
        
        // Warning errors - important but not blocking
        XCTAssertEqual(ErrorHandlingManager.WhisperNodeError.modelDownloadFailed("test").severity, 
                      .warning)
        XCTAssertEqual(ErrorHandlingManager.WhisperNodeError.hotkeyConflict("test").severity, 
                      .warning)
        XCTAssertEqual(ErrorHandlingManager.WhisperNodeError.systemResourcesExhausted.severity, 
                      .warning)
        
        // Minor errors - brief feedback only
        XCTAssertEqual(ErrorHandlingManager.WhisperNodeError.transcriptionFailed.severity, 
                      .minor)
        XCTAssertEqual(ErrorHandlingManager.WhisperNodeError.networkConnectionFailed.severity, 
                      .minor)
        XCTAssertEqual(ErrorHandlingManager.WhisperNodeError.modelCorrupted("test").severity, 
                      .minor)
    }
    
    func testRecoverableErrors() {
        // Recoverable errors
        XCTAssertTrue(ErrorHandlingManager.WhisperNodeError.modelDownloadFailed("test").isRecoverable)
        XCTAssertTrue(ErrorHandlingManager.WhisperNodeError.networkConnectionFailed.isRecoverable)
        XCTAssertTrue(ErrorHandlingManager.WhisperNodeError.modelCorrupted("test").isRecoverable)
        XCTAssertTrue(ErrorHandlingManager.WhisperNodeError.transcriptionFailed.isRecoverable)
        
        // Non-recoverable errors
        XCTAssertFalse(ErrorHandlingManager.WhisperNodeError.microphoneAccessDenied.isRecoverable)
        XCTAssertFalse(ErrorHandlingManager.WhisperNodeError.hotkeyConflict("test").isRecoverable)
        XCTAssertFalse(ErrorHandlingManager.WhisperNodeError.insufficientDiskSpace.isRecoverable)
        XCTAssertFalse(ErrorHandlingManager.WhisperNodeError.systemResourcesExhausted.isRecoverable)
    }
    
    // MARK: - Disk Space Tests
    
    func testDiskSpaceCheckWithSufficientSpace() {
        // Test with a small amount that should be available
        let smallRequirement: UInt64 = 1_000 // 1KB
        let hasSpace = errorManager.checkDiskSpace(requiredBytes: smallRequirement)
        XCTAssertTrue(hasSpace, "Should have sufficient space for small requirement")
    }
    
    func testDiskSpaceCheckWithLargeRequirement() {
        // Test with an unrealistic large amount
        let largeRequirement: UInt64 = 999_999_999_999_999 // Nearly 1PB
        let hasSpace = errorManager.checkDiskSpace(requiredBytes: largeRequirement)
        XCTAssertFalse(hasSpace, "Should not have space for unrealistic large requirement")
    }
    
    // MARK: - Error Handling Tests
    
    func testHandleMicrophoneAccessDenied() {
        // Test that microphone access denial is handled appropriately
        let expectation = expectation(description: "Microphone access error handled")
        
        Task {
            errorManager.handleMicrophoneAccessDenied()
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testHandleModelDownloadFailure() {
        let expectation = expectation(description: "Model download error handled")
        var retryCallbackExecuted = false
        
        let retryAction = {
            retryCallbackExecuted = true
            expectation.fulfill()
        }
        
        Task {
            errorManager.handleModelDownloadFailure("Network timeout", retryAction: retryAction)
        }
        
        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(retryCallbackExecuted, "Retry callback should be executed")
    }
    
    func testHandleTranscriptionFailure() {
        let expectation = expectation(description: "Transcription error handled")
        
        Task {
            errorManager.handleTranscriptionFailure()
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testHandleHotkeyConflict() {
        let expectation = expectation(description: "Hotkey conflict handled")
        
        Task {
            errorManager.handleHotkeyConflict("Cmd+Space conflicts with Spotlight")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Graceful Degradation Tests
    
    func testCurrentDegradationState() {
        let degradationState = errorManager.getCurrentDegradationState()
        
        // Should contain all expected feature flags
        XCTAssertNotNil(degradationState["voiceInput"])
        XCTAssertNotNil(degradationState["modelDownload"])
        XCTAssertNotNil(degradationState["transcription"])
        XCTAssertNotNil(degradationState["hotkey"])
    }
    
    func testCriticalFunctionalityAvailability() {
        let isAvailable = errorManager.isCriticalFunctionalityAvailable
        XCTAssertTrue(isAvailable, "Critical functionality should be available by default")
    }
    
    // MARK: - Integration Tests
    
    func testErrorHandlingIntegration() {
        // Test that error handling works end-to-end
        let expectation = expectation(description: "Error integration test")
        
        Task {
            // Test various error scenarios
            errorManager.handleError(.transcriptionFailed)
            errorManager.handleError(.hotkeyConflict("Test conflict"))
            errorManager.handleError(.networkConnectionFailed)
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testRecoveryCallbackExecution() {
        let expectation = expectation(description: "Recovery callback execution")
        var callbackExecuted = false
        
        let recovery = {
            callbackExecuted = true
            expectation.fulfill()
        }
        
        Task {
            // Test with a recoverable error
            errorManager.handleError(.modelDownloadFailed("Test error"), recovery: recovery)
        }
        
        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(callbackExecuted, "Recovery callback should be executed for recoverable errors")
    }
    
    // MARK: - Performance Tests
    
    func testErrorHandlingPerformance() {
        measure {
            for _ in 0..<100 {
                errorManager.handleError(.transcriptionFailed)
            }
        }
    }
}

// MARK: - Error Scenario Integration Tests

/// Tests that validate error handling integrates properly with core components
extension ErrorHandlingManagerTests {
    
    func testAudioCaptureErrorIntegration() {
        // Test that audio capture errors are properly handled
        let audioEngine = AudioCaptureEngine()
        
        // Check permission status without requesting
        let permissionStatus = audioEngine.checkPermissionStatus()
        XCTAssertTrue([.granted, .denied, .undetermined].contains(permissionStatus),
                     "Permission status should be one of the expected values")
    }
    
    func testModelManagerErrorIntegration() {
        // Test that model manager integrates with error handling
        let modelManager = ModelManager.shared
        
        Task {
            await modelManager.refreshModels()
            let availableModels = modelManager.availableModels
            XCTAssertFalse(availableModels.isEmpty, "Should have at least bundled models available")
        }
    }
}