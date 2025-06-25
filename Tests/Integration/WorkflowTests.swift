import XCTest
import os.log
@testable import WhisperNode

/// End-to-End Workflow Tests for WhisperNode
///
/// Tests complete user workflows and scenarios to ensure the application
/// functions reliably in real-world usage patterns.
///
/// ## Test Coverage
/// - User scenario simulation
/// - Real-world workflow patterns
/// - Edge case handling
/// - Performance measurement under realistic conditions
/// - Multi-step workflow validation
/// - User experience validation
class WorkflowTests: XCTestCase {
    
    private static let logger = Logger(subsystem: "com.whispernode.tests", category: "workflow")
    
    // MARK: - Test Infrastructure
    
    private var testHarness: TestHarness!
    private var performanceMeasurement: PerformanceMeasurement!
    
    private let testTimeout: TimeInterval = 15.0
    
    // MARK: - Setup and Teardown
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        testHarness = TestHarness()
        try testHarness.setUp()
        
        performanceMeasurement = PerformanceMeasurement()
        
        Self.logger.info("Workflow tests setup completed")
    }
    
    override func tearDownWithError() throws {
        testHarness?.tearDown()
        testHarness = nil
        performanceMeasurement = nil
        
        Self.logger.info("Workflow tests teardown completed")
        try super.tearDownWithError()
    }
    
    // MARK: - Basic User Workflows
    
    /// Test basic dictation workflow
    func testBasicDictationWorkflow() throws {
        let expectation = XCTestExpectation(description: "Basic dictation")
        
        performanceMeasurement.startMeasuring()
        
        // Simulate user pressing hotkey
        testHarness.simulateHotkeyPress(.controlOption)
        performanceMeasurement.markCheckpoint("user_hotkey_press")
        
        // User speaks
        let speechAudio = testHarness.generateSampleAudio(duration: 2.0, frequency: 440.0)
        testHarness.injectAudioData(speechAudio)
        performanceMeasurement.markCheckpoint("user_speech_complete")
        
        // User releases hotkey
        testHarness.simulateHotkeyRelease(.controlOption)
        performanceMeasurement.markCheckpoint("user_hotkey_release")
        
        // Wait for transcription and insertion
        testHarness.waitForTranscription { result in
            self.performanceMeasurement.markCheckpoint("workflow_complete")
            
            XCTAssertNotNil(result.text, "Should receive transcription")
            XCTAssertGreaterThan(result.confidence, 0.7, "Confidence should be reasonable")
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: testTimeout)
        
        let metrics = performanceMeasurement.stopMeasuring()
        XCTAssertLessThan(metrics.totalLatency, 5.0, "Basic workflow should complete quickly")
        
        Self.logger.info("Basic dictation workflow completed in \(String(format: "%.2f", metrics.totalLatency))s")
    }
    
    /// Test rapid successive dictations
    func testRapidSuccessiveDictations() throws {
        let dictationCount = 3
        let interval: TimeInterval = 1.0
        
        for i in 0..<dictationCount {
            let expectation = XCTestExpectation(description: "Rapid dictation \(i + 1)")
            
            Self.logger.info("Starting rapid dictation \(i + 1)/\(dictationCount)")
            
            // Quick dictation cycle
            testHarness.simulateHotkeyPress(.controlOption)
            
            let quickAudio = testHarness.generateSampleAudio(duration: 1.0)
            testHarness.injectAudioData(quickAudio)
            
            testHarness.simulateHotkeyRelease(.controlOption)
            
            testHarness.waitForTranscription { result in
                XCTAssertNotNil(result.text, "Rapid dictation \(i + 1) should succeed")
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: testTimeout)
            
            // Brief pause between dictations
            if i < dictationCount - 1 {
                Thread.sleep(forTimeInterval: interval)
            }
        }
        
        Self.logger.info("Rapid successive dictations completed successfully")
    }
    
    /// Test long-form dictation workflow
    func testLongFormDictationWorkflow() throws {
        let expectation = XCTestExpectation(description: "Long-form dictation")
        
        performanceMeasurement.startMeasuring()
        
        // Simulate extended speech
        testHarness.simulateHotkeyPress(.controlOption)
        
        let longAudio = testHarness.generateSampleAudio(duration: 10.0, frequency: 440.0)
        testHarness.injectAudioData(longAudio)
        
        testHarness.simulateHotkeyRelease(.controlOption)
        performanceMeasurement.markCheckpoint("long_speech_complete")
        
        testHarness.waitForTranscription { result in
            self.performanceMeasurement.markCheckpoint("long_transcription_complete")
            
            XCTAssertNotNil(result.text, "Should handle long-form speech")
            XCTAssertGreaterThan(result.duration, 8.0, "Should recognize extended duration")
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: testTimeout)
        
        let metrics = performanceMeasurement.stopMeasuring()
        Self.logger.info("Long-form dictation: \(String(format: "%.2f", metrics.totalLatency))s total")
    }
    
    // MARK: - Real-World Scenarios
    
    /// Test email composition scenario
    func testEmailCompositionScenario() throws {
        let expectation = XCTestExpectation(description: "Email composition")
        
        // Simulate composing an email with multiple dictations
        let emailParts = [
            ("greeting", "Hello John"),
            ("body", "I wanted to follow up on our meeting yesterday"),
            ("closing", "Best regards")
        ]
        
        let mockEmailApp = testHarness.createMockTargetApplication()
        var completedParts = 0
        
        for (part, expectedContent) in emailParts {
            Self.logger.info("Dictating email \(part)")
            
            testHarness.simulateHotkeyPress(.controlOption)
            
            let speechAudio = testHarness.generateSampleAudio(duration: 2.0)
            testHarness.injectAudioData(speechAudio)
            
            testHarness.simulateHotkeyRelease(.controlOption)
            
            testHarness.waitForTranscription { result in
                XCTAssertNotNil(result.text, "Email \(part) should be transcribed")
                
                completedParts += 1
                if completedParts == emailParts.count {
                    expectation.fulfill()
                }
            }
            
            // Pause between email parts
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        wait(for: [expectation], timeout: testTimeout)
        
        Self.logger.info("Email composition scenario completed")
    }
    
    /// Test code documentation scenario
    func testCodeDocumentationScenario() throws {
        let expectation = XCTestExpectation(description: "Code documentation")
        
        // Simulate dictating code comments
        let codeComments = [
            "This function calculates the fibonacci sequence",
            "Parameters include the number of iterations",
            "Returns an array of fibonacci numbers"
        ]
        
        let mockCodeEditor = testHarness.createMockTargetApplication()
        var completedComments = 0
        
        for comment in codeComments {
            testHarness.simulateHotkeyPress(.controlOption)
            
            let commentAudio = testHarness.generateSampleAudio(duration: 3.0)
            testHarness.injectAudioData(commentAudio)
            
            testHarness.simulateHotkeyRelease(.controlOption)
            
            testHarness.waitForTranscription { result in
                XCTAssertNotNil(result.text, "Code comment should be transcribed")
                
                completedComments += 1
                if completedComments == codeComments.count {
                    expectation.fulfill()
                }
            }
            
            Thread.sleep(forTimeInterval: 0.3)
        }
        
        wait(for: [expectation], timeout: testTimeout)
        
        Self.logger.info("Code documentation scenario completed")
    }
    
    /// Test meeting notes scenario
    func testMeetingNotesScenario() throws {
        let expectation = XCTestExpectation(description: "Meeting notes")
        
        performanceMeasurement.startMeasuring()
        
        // Simulate taking meeting notes with varied speech patterns
        let noteSegments = [
            (duration: 1.5, frequency: 440.0), // Quick note
            (duration: 4.0, frequency: 330.0), // Detailed explanation
            (duration: 2.0, frequency: 550.0), // Action item
            (duration: 1.0, frequency: 660.0)  // Brief reminder
        ]
        
        var completedSegments = 0
        
        for (index, segment) in noteSegments.enumerated() {
            Self.logger.info("Recording meeting note segment \(index + 1)")
            
            testHarness.simulateHotkeyPress(.controlOption)
            
            let noteAudio = testHarness.generateSampleAudio(
                duration: segment.duration,
                frequency: segment.frequency
            )
            testHarness.injectAudioData(noteAudio)
            
            testHarness.simulateHotkeyRelease(.controlOption)
            
            testHarness.waitForTranscription { result in
                XCTAssertNotNil(result.text, "Meeting note segment should be transcribed")
                XCTAssertGreaterThan(result.confidence, 0.6, "Should have reasonable confidence")
                
                completedSegments += 1
                if completedSegments == noteSegments.count {
                    self.performanceMeasurement.markCheckpoint("meeting_notes_complete")
                    expectation.fulfill()
                }
            }
            
            // Realistic pause between notes
            Thread.sleep(forTimeInterval: 0.8)
        }
        
        wait(for: [expectation], timeout: testTimeout)
        
        let metrics = performanceMeasurement.stopMeasuring()
        Self.logger.info("Meeting notes scenario: \(String(format: "%.2f", metrics.totalLatency))s total")
    }
    
    // MARK: - Edge Case Workflows
    
    /// Test interrupted workflow recovery
    func testInterruptedWorkflowRecovery() throws {
        let expectation = XCTestExpectation(description: "Interrupted workflow recovery")
        
        // Start normal workflow
        testHarness.simulateHotkeyPress(.controlOption)
        
        let partialAudio = testHarness.generateSampleAudio(duration: 1.0)
        testHarness.injectAudioData(partialAudio)
        
        // Simulate interruption (force stop)
        testHarness.audioEngine.stopCapture()
        
        // Try to recover with new workflow
        Thread.sleep(forTimeInterval: 0.5)
        
        testHarness.simulateHotkeyPress(.controlOption)
        
        let recoveryAudio = testHarness.generateSampleAudio(duration: 2.0)
        testHarness.injectAudioData(recoveryAudio)
        
        testHarness.simulateHotkeyRelease(.controlOption)
        
        testHarness.waitForTranscription { result in
            XCTAssertNotNil(result.text, "Should recover from interruption")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: testTimeout)
        
        Self.logger.info("Interrupted workflow recovery completed")
    }
    
    /// Test silent audio handling
    func testSilentAudioHandling() throws {
        let expectation = XCTestExpectation(description: "Silent audio handling")
        
        testHarness.simulateHotkeyPress(.controlOption)
        
        // Inject silent audio
        let silentAudio = testHarness.loadTestAudio("silence.wav")
        testHarness.injectAudioData(silentAudio)
        
        testHarness.simulateHotkeyRelease(.controlOption)
        
        testHarness.waitForTranscription { result in
            // Should handle gracefully, possibly with empty result
            XCTAssertNotNil(result, "Should handle silent audio gracefully")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: testTimeout)
        
        Self.logger.info("Silent audio handling completed")
    }
    
    /// Test very short utterance workflow
    func testVeryShortUtteranceWorkflow() throws {
        let expectation = XCTestExpectation(description: "Very short utterance")
        
        testHarness.simulateHotkeyPress(.controlOption)
        
        // Very brief audio (0.2 seconds)
        let shortAudio = testHarness.generateSampleAudio(duration: 0.2)
        testHarness.injectAudioData(shortAudio)
        
        testHarness.simulateHotkeyRelease(.controlOption)
        
        testHarness.waitForTranscription { result in
            // Should handle short utterances appropriately
            XCTAssertNotNil(result, "Should handle very short utterances")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: testTimeout)
        
        Self.logger.info("Very short utterance workflow completed")
    }
    
    // MARK: - Performance Under Load
    
    /// Test workflow performance under system load
    func testWorkflowPerformanceUnderLoad() throws {
        let expectation = XCTestExpectation(description: "Performance under load")
        
        // Simulate system load by running multiple concurrent operations
        let concurrentOperations = 3
        let group = DispatchGroup()
        
        for i in 0..<concurrentOperations {
            group.enter()
            
            DispatchQueue.global(qos: .background).async {
                // Simulate background work
                for _ in 0..<1000 {
                    _ = Array(0..<1000).map { $0 * 2 }
                }
                group.leave()
            }
        }
        
        // Run workflow under load
        performanceMeasurement.startMeasuring()
        
        testHarness.simulateHotkeyPress(.controlOption)
        
        let testAudio = testHarness.generateSampleAudio(duration: 3.0)
        testHarness.injectAudioData(testAudio)
        
        testHarness.simulateHotkeyRelease(.controlOption)
        
        testHarness.waitForTranscription { result in
            let metrics = self.performanceMeasurement.stopMeasuring()
            
            XCTAssertNotNil(result.text, "Should work under system load")
            XCTAssertLessThan(metrics.totalLatency, 8.0, "Should maintain reasonable performance under load")
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: testTimeout)
        
        // Wait for background operations to complete
        group.wait()
        
        Self.logger.info("Workflow performance under load test completed")
    }
}
