import XCTest
import os.log
@testable import WhisperNode

/// Component Interaction Tests for WhisperNode
///
/// Tests the interactions between different components to ensure
/// proper interface validation, data flow, and error propagation.
///
/// ## Test Coverage
/// - Interface validation between components
/// - Data flow verification
/// - Error propagation testing
/// - State synchronization validation
/// - Component lifecycle management
/// - Cross-component communication
class ComponentInteractionTests: XCTestCase {
    
    private static let logger = Logger(subsystem: "com.whispernode.tests", category: "component-interaction")
    
    // MARK: - Test Infrastructure
    
    private var testHarness: TestHarness!
    private var performanceMeasurement: PerformanceMeasurement!
    
    private let testTimeout: TimeInterval = 10.0
    
    // MARK: - Setup and Teardown
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        testHarness = TestHarness()
        try testHarness.setUp()
        
        performanceMeasurement = PerformanceMeasurement()
        
        Self.logger.info("Component interaction tests setup completed")
    }
    
    override func tearDownWithError() throws {
        testHarness?.tearDown()
        testHarness = nil
        performanceMeasurement = nil
        
        Self.logger.info("Component interaction tests teardown completed")
        try super.tearDownWithError()
    }
    
    // MARK: - Hotkey to Audio Component Interaction
    
    /// Test hotkey manager to audio engine interaction
    func testHotkeyToAudioInteraction() throws {
        let expectation = XCTestExpectation(description: "Hotkey to audio interaction")
        
        // Verify initial state
        XCTAssertFalse(testHarness.isAudioCaptureActive, "Audio should be inactive initially")
        
        // Test hotkey press triggers audio start
        testHarness.simulateHotkeyPress(.controlOption)
        
        // Verify audio engine responds to hotkey
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.testHarness.isAudioCaptureActive, "Audio should start after hotkey press")
            
            // Test hotkey release stops audio
            self.testHarness.simulateHotkeyRelease(.controlOption)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                XCTAssertFalse(self.testHarness.isAudioCaptureActive, "Audio should stop after hotkey release")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: testTimeout)
        
        Self.logger.info("Hotkey to audio interaction test completed")
    }
    
    /// Test hotkey state synchronization
    func testHotkeyStateSynchronization() throws {
        let expectation = XCTestExpectation(description: "Hotkey state sync")
        
        // Test multiple rapid presses
        testHarness.simulateHotkeyPress(.controlOption)
        testHarness.simulateHotkeyPress(.controlOption) // Duplicate press
        
        XCTAssertTrue(testHarness.isAudioCaptureActive, "Should handle duplicate hotkey presses")
        
        testHarness.simulateHotkeyRelease(.controlOption)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertFalse(self.testHarness.isAudioCaptureActive, "Should stop after release")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: testTimeout)
        
        Self.logger.info("Hotkey state synchronization test completed")
    }
    
    // MARK: - Audio to Transcription Component Interaction
    
    /// Test audio engine to transcription engine data flow
    func testAudioToTranscriptionDataFlow() throws {
        let expectation = XCTestExpectation(description: "Audio to transcription data flow")
        
        // Start audio capture
        testHarness.simulateHotkeyPress(.controlOption)
        
        // Inject audio data
        let testAudio = testHarness.generateSampleAudio(duration: 2.0)
        testHarness.injectAudioData(testAudio)
        
        // Verify audio data is captured
        let capturedAudio = testHarness.audioEngine.getCapturedAudio()
        XCTAssertEqual(capturedAudio.count, testAudio.count, "Audio data should be captured correctly")
        
        // Stop capture and trigger transcription
        testHarness.simulateHotkeyRelease(.controlOption)
        
        testHarness.waitForTranscription { result in
            XCTAssertNotNil(result.text, "Transcription should receive audio data")
            XCTAssertGreaterThan(result.duration, 0, "Should have valid duration")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: testTimeout)
        
        Self.logger.info("Audio to transcription data flow test completed")
    }
    
    /// Test audio format compatibility
    func testAudioFormatCompatibility() throws {
        let expectation = XCTestExpectation(description: "Audio format compatibility")
        
        // Test different audio formats/durations
        let testCases = [
            (duration: 0.5, frequency: 440.0),
            (duration: 2.0, frequency: 880.0),
            (duration: 5.0, frequency: 220.0)
        ]
        
        var completedTests = 0
        
        for (index, testCase) in testCases.enumerated() {
            Self.logger.info("Testing audio format case \(index + 1)")
            
            testHarness.simulateHotkeyPress(.controlOption)
            
            let audio = testHarness.generateSampleAudio(
                duration: testCase.duration,
                frequency: testCase.frequency
            )
            testHarness.injectAudioData(audio)
            
            testHarness.simulateHotkeyRelease(.controlOption)
            
            testHarness.waitForTranscription { result in
                XCTAssertNotNil(result.text, "Should handle audio format \(index + 1)")
                
                completedTests += 1
                if completedTests == testCases.count {
                    expectation.fulfill()
                }
            }
            
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        wait(for: [expectation], timeout: testTimeout)
        
        Self.logger.info("Audio format compatibility test completed")
    }
    
    // MARK: - Transcription to Text Insertion Interaction
    
    /// Test transcription to text insertion pipeline
    func testTranscriptionToTextInsertionPipeline() throws {
        let expectation = XCTestExpectation(description: "Transcription to text insertion")
        
        let mockApp = testHarness.createMockTargetApplication()
        
        testHarness.simulateHotkeyPress(.controlOption)
        
        let testAudio = testHarness.generateSampleAudio(duration: 1.5)
        testHarness.injectAudioData(testAudio)
        
        testHarness.simulateHotkeyRelease(.controlOption)
        
        testHarness.waitForTranscription { result in
            XCTAssertNotNil(result.text, "Should receive transcription result")
            
            // Verify text insertion receives the result
            XCTAssertNotNil(self.testHarness.lastInsertedText, "Text should be inserted")
            XCTAssertEqual(mockApp.insertedText, result.text, "Inserted text should match transcription")
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: testTimeout)
        
        Self.logger.info("Transcription to text insertion pipeline test completed")
    }
    
    /// Test text insertion error handling
    func testTextInsertionErrorHandling() throws {
        let expectation = XCTestExpectation(description: "Text insertion error handling")
        
        // Create inactive target application
        let mockApp = testHarness.createMockTargetApplication()
        mockApp.setActive(false)
        
        testHarness.simulateHotkeyPress(.controlOption)
        
        let testAudio = testHarness.generateSampleAudio(duration: 1.0)
        testHarness.injectAudioData(testAudio)
        
        testHarness.simulateHotkeyRelease(.controlOption)
        
        testHarness.waitForTranscription { result in
            XCTAssertNotNil(result.text, "Transcription should complete even if insertion fails")
            
            // Text insertion might fail, but should not affect transcription
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: testTimeout)
        
        Self.logger.info("Text insertion error handling test completed")
    }
    
    // MARK: - Cross-Component Error Propagation
    
    /// Test error propagation across all components
    func testCrossComponentErrorPropagation() throws {
        try testAudioEngineErrorPropagation()
        try testTranscriptionEngineErrorPropagation()
        try testTextInsertionErrorPropagation()
    }
    
    func testAudioEngineErrorPropagation() throws {
        let expectation = XCTestExpectation(description: "Audio engine error propagation")
        
        // Force audio engine into error state
        testHarness.audioEngine.stopCapture()
        
        testHarness.simulateHotkeyPress(.controlOption)
        
        // Should handle audio engine failure gracefully
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            XCTAssertFalse(self.testHarness.isAudioCaptureActive, "Audio should remain inactive on error")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: testTimeout)
        
        Self.logger.info("Audio engine error propagation test completed")
    }
    
    func testTranscriptionEngineErrorPropagation() throws {
        let expectation = XCTestExpectation(description: "Transcription engine error propagation")
        
        testHarness.simulateHotkeyPress(.controlOption)
        
        // Inject problematic audio data
        let emptyAudio: [Float] = []
        testHarness.injectAudioData(emptyAudio)
        
        testHarness.simulateHotkeyRelease(.controlOption)
        
        testHarness.waitForTranscription { result in
            // Should handle transcription errors gracefully
            XCTAssertNotNil(result, "Should receive some result even on transcription error")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: testTimeout)
        
        Self.logger.info("Transcription engine error propagation test completed")
    }
    
    func testTextInsertionErrorPropagation() throws {
        let expectation = XCTestExpectation(description: "Text insertion error propagation")
        
        // Create mock app that will fail insertion
        let mockApp = testHarness.createMockTargetApplication()
        mockApp.setActive(false)
        
        testHarness.simulateHotkeyPress(.controlOption)
        
        let testAudio = testHarness.generateSampleAudio(duration: 1.0)
        testHarness.injectAudioData(testAudio)
        
        testHarness.simulateHotkeyRelease(.controlOption)
        
        testHarness.waitForTranscription { result in
            // Transcription should complete despite text insertion failure
            XCTAssertNotNil(result.text, "Transcription should complete despite insertion failure")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: testTimeout)
        
        Self.logger.info("Text insertion error propagation test completed")
    }
    
    // MARK: - Component State Synchronization
    
    /// Test state synchronization across all components
    func testComponentStateSynchronization() throws {
        let expectation = XCTestExpectation(description: "Component state synchronization")
        
        performanceMeasurement.startMeasuring()
        
        // Initial state verification
        XCTAssertFalse(testHarness.isAudioCaptureActive, "Initial: Audio inactive")
        XCTAssertNil(testHarness.lastTranscriptionResult, "Initial: No transcription")
        XCTAssertNil(testHarness.lastInsertedText, "Initial: No inserted text")
        
        // Start workflow
        testHarness.simulateHotkeyPress(.controlOption)
        performanceMeasurement.markCheckpoint("hotkey_pressed")
        
        // State after hotkey press
        XCTAssertTrue(testHarness.isAudioCaptureActive, "After press: Audio active")
        
        // Inject audio
        let testAudio = testHarness.generateSampleAudio(duration: 2.0)
        testHarness.injectAudioData(testAudio)
        performanceMeasurement.markCheckpoint("audio_injected")
        
        // Complete workflow
        testHarness.simulateHotkeyRelease(.controlOption)
        performanceMeasurement.markCheckpoint("hotkey_released")
        
        testHarness.waitForTranscription { result in
            self.performanceMeasurement.markCheckpoint("transcription_complete")
            
            // Final state verification
            XCTAssertNotNil(self.testHarness.lastTranscriptionResult, "Final: Has transcription")
            XCTAssertNotNil(self.testHarness.lastInsertedText, "Final: Has inserted text")
            XCTAssertFalse(self.testHarness.isAudioCaptureActive, "Final: Audio inactive")
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: testTimeout)
        
        let metrics = performanceMeasurement.stopMeasuring()
        Self.logger.info("Component state synchronization completed in \(String(format: "%.2f", metrics.totalLatency))s")
    }
    
    // MARK: - Component Lifecycle Management
    
    /// Test component initialization and cleanup
    func testComponentLifecycleManagement() throws {
        let expectation = XCTestExpectation(description: "Component lifecycle")
        
        // Test component initialization
        XCTAssertNotNil(testHarness.audioEngine, "Audio engine should be initialized")
        XCTAssertNotNil(testHarness.transcriptionEngine, "Transcription engine should be initialized")
        XCTAssertNotNil(testHarness.textInsertion, "Text insertion should be initialized")
        XCTAssertNotNil(testHarness.hotkeyManager, "Hotkey manager should be initialized")
        
        // Test component interaction during lifecycle
        testHarness.simulateHotkeyPress(.controlOption)
        
        let testAudio = testHarness.generateSampleAudio(duration: 1.0)
        testHarness.injectAudioData(testAudio)
        
        testHarness.simulateHotkeyRelease(.controlOption)
        
        testHarness.waitForTranscription { result in
            XCTAssertNotNil(result.text, "Components should work together during lifecycle")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: testTimeout)
        
        // Test component cleanup (handled in tearDown)
        Self.logger.info("Component lifecycle management test completed")
    }
    
    // MARK: - Interface Validation
    
    /// Test component interface contracts
    func testComponentInterfaceContracts() throws {
        // Test audio engine interface
        XCTAssertFalse(testHarness.audioEngine.isCapturing, "Audio engine should have correct initial state")
        
        testHarness.audioEngine.startCapture()
        XCTAssertTrue(testHarness.audioEngine.isCapturing, "Audio engine should respond to start")
        
        testHarness.audioEngine.stopCapture()
        XCTAssertFalse(testHarness.audioEngine.isCapturing, "Audio engine should respond to stop")
        
        // Test transcription engine interface
        let sampleAudio = testHarness.generateSampleAudio(duration: 1.0)
        let result = testHarness.transcriptionEngine.transcribe(sampleAudio)
        
        XCTAssertNotNil(result.text, "Transcription engine should return text")
        XCTAssertGreaterThan(result.confidence, 0.0, "Transcription engine should return confidence")
        XCTAssertGreaterThan(result.duration, 0.0, "Transcription engine should return duration")
        
        // Test text insertion interface
        let insertionSuccess = testHarness.textInsertion.insertText("Test text")
        XCTAssertTrue(insertionSuccess, "Text insertion should succeed")
        XCTAssertEqual(testHarness.textInsertion.lastInsertedText, "Test text", "Text insertion should track inserted text")
        
        Self.logger.info("Component interface contracts test completed")
    }
}
