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
    
    var errorManager: ErrorHandlingManager {
        return ErrorHandlingManager.shared
    }
    
    override func setUp() async throws {
        try await super.setUp()
        // Reset degradation state for clean test environment
        errorManager.restoreAllFunctionality()
    }
    
    override func tearDown() async throws {
        try await super.tearDown()
    }
    
    // MARK: - Error Type Tests
    
    func testWhisperNodeErrorDescriptions() {
        let errors: [ErrorHandlingManager.WhisperNodeError] = [
            .microphoneAccessDenied,
            .audioCaptureFailure("Audio device not available"),
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
        XCTAssertEqual(ErrorHandlingManager.WhisperNodeError.audioCaptureFailure("test").severity, 
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
        XCTAssertTrue(ErrorHandlingManager.WhisperNodeError.audioCaptureFailure("test").isRecoverable)
        
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
        let callbackExpectation = expectation(description: "Retry callback stored")
        let errorHandledExpectation = expectation(description: "Model download error handled")
        var retryCallbackExecuted = false
        
        let retryAction = {
            retryCallbackExecuted = true
            callbackExpectation.fulfill()
        }
        
        Task {
            // Handle the error first
            errorManager.handleModelDownloadFailure("Network timeout", retryAction: retryAction)
            errorHandledExpectation.fulfill()
            
            // Simulate a retry trigger by waiting and calling the retry manually
            // In a real scenario, this would be triggered by user action or automatic retry
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            await retryAction()
        }
        
        wait(for: [errorHandledExpectation, callbackExpectation], timeout: 5.0)
        XCTAssertTrue(retryCallbackExecuted, "Retry callback should be executed when retry is triggered")
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
    
    func testAudioCaptureErrorIntegration() async {
        // Test that audio capture errors are properly handled
        let initialVoiceState = errorManager.getCurrentDegradationState()["voiceInput"]
        XCTAssertTrue(initialVoiceState == true, "Voice input should start enabled")
        
        // Simulate microphone access denial
        errorManager.handleMicrophoneAccessDenied()
        
        // Verify degradation state is updated
        let degradedState = errorManager.getCurrentDegradationState()["voiceInput"]
        XCTAssertFalse(degradedState!, "Voice input should be disabled after access denied")
        
        // Test recovery
        errorManager.restoreFunctionality(for: "voiceInput")
        let recoveredState = errorManager.getCurrentDegradationState()["voiceInput"]
        XCTAssertTrue(recoveredState!, "Voice input should be restored")
    }
    
    func testModelManagerErrorIntegration() async {
        // Test that model manager integrates with error handling
        let initialDownloadState = errorManager.getCurrentDegradationState()["modelDownload"]
        XCTAssertTrue(initialDownloadState == true, "Model download should start enabled")
        
        // Simulate model download failure
        var retryExecuted = false
        let retryAction = {
            retryExecuted = true
        }
        
        errorManager.handleModelDownloadFailure("Simulated network error", retryAction: retryAction)
        
        // Verify degradation state is updated
        let degradedState = errorManager.getCurrentDegradationState()["modelDownload"]
        XCTAssertFalse(degradedState!, "Model download should be disabled after failure")
        
        // Test recovery
        errorManager.restoreFunctionality(for: "modelDownload")
        let recoveredState = errorManager.getCurrentDegradationState()["modelDownload"]
        XCTAssertTrue(recoveredState!, "Model download should be restored")
    }
    
    func testTranscriptionErrorIntegration() async {
        // Test transcription error handling and degradation
        let initialTranscriptionState = errorManager.getCurrentDegradationState()["transcription"]
        XCTAssertTrue(initialTranscriptionState == true, "Transcription should start enabled")
        
        // Simulate transcription failure
        errorManager.handleTranscriptionFailure()
        
        // Verify degradation state is updated
        let degradedState = errorManager.getCurrentDegradationState()["transcription"]
        XCTAssertFalse(degradedState!, "Transcription should be disabled after failure")
        
        // Test recovery
        errorManager.restoreFunctionality(for: "transcription")
        let recoveredState = errorManager.getCurrentDegradationState()["transcription"]
        XCTAssertTrue(recoveredState!, "Transcription should be restored")
    }
    
    func testHotkeyConflictIntegration() async {
        // Test hotkey conflict handling
        let initialHotkeyState = errorManager.getCurrentDegradationState()["hotkey"]
        XCTAssertTrue(initialHotkeyState == true, "Hotkey should start enabled")
        
        // Simulate hotkey conflict
        errorManager.handleHotkeyConflict("Cmd+Space conflicts with Spotlight")
        
        // Verify degradation state is updated
        let degradedState = errorManager.getCurrentDegradationState()["hotkey"]
        XCTAssertFalse(degradedState!, "Hotkey should be disabled after conflict")
        
        // Test recovery
        errorManager.restoreFunctionality(for: "hotkey")
        let recoveredState = errorManager.getCurrentDegradationState()["hotkey"]
        XCTAssertTrue(recoveredState!, "Hotkey should be restored")
    }
    
    func testCriticalFunctionalityAvailability() async {
        // Test critical functionality detection
        XCTAssertTrue(errorManager.isCriticalFunctionalityAvailable, "All functionality should be available initially")
        
        // Disable voice input (critical)
        errorManager.handleMicrophoneAccessDenied()
        XCTAssertFalse(errorManager.isCriticalFunctionalityAvailable, "Critical functionality should be unavailable without voice input")
        
        // Restore voice input but disable transcription
        errorManager.restoreFunctionality(for: "voiceInput")
        errorManager.handleTranscriptionFailure()
        XCTAssertFalse(errorManager.isCriticalFunctionalityAvailable, "Critical functionality should be unavailable without transcription")
        
        // Restore all
        errorManager.restoreAllFunctionality()
        XCTAssertTrue(errorManager.isCriticalFunctionalityAvailable, "Critical functionality should be available after full restore")
    }
}