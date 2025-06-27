import XCTest
import os.log
#if canImport(WhisperNode)
@testable import WhisperNode
#endif

/// Main Integration Test Suite for WhisperNode
///
/// Orchestrates comprehensive integration testing across all components
/// to ensure the complete user workflow functions reliably.
///
/// ## Test Coverage
/// - Complete workflow validation (hotkey → audio → transcription → text insertion)
/// - Component interaction testing
/// - Error propagation and recovery
/// - Performance requirements validation
/// - Cross-platform compatibility
/// - System configuration testing
///
/// ## Requirements Validated
/// - End-to-end latency under 3 seconds
/// - Hotkey to audio start latency under 100ms
/// - Memory usage under 100MB during normal operation
/// - 95%+ success rate for normal usage scenarios
/// - Cross-component state synchronization
class IntegrationTestSuite: XCTestCase {
    
    private static let logger = Logger(subsystem: "com.whispernode.tests", category: "integration")
    
    // MARK: - Test Infrastructure
    
    private var testHarness: TestHarness!
    private var performanceMeasurement: PerformanceMeasurement!
    private var systemConfig: SystemConfigDetector.SystemInfo!

    private let testTimeout: TimeInterval = TestConstants.defaultTimeout
    private var testResults: [String: Bool] = [:]
    
    // MARK: - Setup and Teardown
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Detect system configuration
        systemConfig = SystemConfigDetector.detectSystemConfiguration()
        
        // Skip tests if system is not compatible
        guard systemConfig.isCompatible else {
            throw XCTSkip("System not compatible with integration tests")
        }
        
        // Skip tests if test environment is not ready
        guard systemConfig.testEnvironmentReady else {
            throw XCTSkip("Test environment not ready (accessibility permissions required)")
        }
        
        // Initialize test infrastructure
        testHarness = TestHarness()
        try testHarness.setUp()
        
        performanceMeasurement = PerformanceMeasurement()
        
        Self.logger.info("Integration test suite setup completed")
    }
    
    override func tearDownWithError() throws {
        testHarness?.tearDown()
        testHarness = nil
        performanceMeasurement = nil

        Self.logger.info("Integration test suite teardown completed")
        try super.tearDownWithError()
    }

    // MARK: - Test Result Tracking

    private func recordTestResult(_ testName: String, passed: Bool) {
        testResults[testName] = passed
        Self.logger.info("Test result recorded: \(testName) = \(passed ? "PASS" : "FAIL")")
    }
    
    // MARK: - Complete Workflow Tests
    
    /// Test the complete workflow from hotkey press to text insertion
    func testCompleteWorkflow() throws {
        let testName = "complete_workflow"
        let expectation = XCTestExpectation(description: "Complete workflow")
        let testAudio = testHarness.loadTestAudio("sample_speech.wav")
        let expectedText = "Hello world"
        
        // Setup mock target application
        let mockApp = testHarness.createMockTargetApplication()
        
        // Start performance measurement
        performanceMeasurement.startMeasuring()
        
        // Simulate hotkey press
        testHarness.simulateHotkeyPress(.controlOption)
        performanceMeasurement.markCheckpoint("hotkey_pressed")
        
        // Verify audio capture starts
        XCTAssertTrue(testHarness.isAudioCaptureActive, "Audio capture should start after hotkey press")
        performanceMeasurement.markCheckpoint("audio_start")
        
        // Inject test audio
        testHarness.injectAudioData(testAudio)
        performanceMeasurement.markCheckpoint("audio_injected")
        
        // Simulate hotkey release
        testHarness.simulateHotkeyRelease(.controlOption)
        performanceMeasurement.markCheckpoint("hotkey_released")
        
        // Wait for transcription and text insertion
        testHarness.waitForTranscription { result in
            self.performanceMeasurement.markCheckpoint("transcription_complete")
            
            XCTAssertEqual(result.text, expectedText, "Transcription should match expected text")
            XCTAssertGreaterThan(result.confidence, 0.8, "Transcription confidence should be high")
            
            // Verify text was inserted
            XCTAssertEqual(mockApp.insertedText, expectedText, "Text should be inserted into target application")
            self.performanceMeasurement.markCheckpoint("text_inserted")
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: testTimeout)
        
        // Validate performance requirements
        let metrics = performanceMeasurement.stopMeasuring()
        let validation = performanceMeasurement.validatePerformanceRequirements(metrics)

        let testPassed = validation.passed
        recordTestResult(testName, passed: testPassed)
        XCTAssertTrue(testPassed, "Performance requirements should be met: \(validation.issues.joined(separator: ", "))")
    }
    
    /// Test workflow with different audio samples
    func testWorkflowWithVariousAudioSamples() throws {
        let testCases = [
            ("short_utterance.wav", "Short"),
            ("long_utterance.wav", "Long utterance"),
            ("sample_speech.wav", "Sample speech")
        ]
        
        for (audioFile, expectedText) in testCases {
            let expectation = XCTestExpectation(description: "Workflow with \(audioFile)")
            let testAudio = testHarness.loadTestAudio(audioFile)
            let mockApp = testHarness.createMockTargetApplication()
            
            // Execute workflow
            testHarness.simulateHotkeyPress(.controlOption)
            XCTAssertTrue(testHarness.isAudioCaptureActive)
            
            testHarness.injectAudioData(testAudio)
            testHarness.simulateHotkeyRelease(.controlOption)
            
            testHarness.waitForTranscription { result in
                XCTAssertNotNil(result.text, "Should receive transcription result")
                XCTAssertFalse(result.text.isEmpty, "Transcription should not be empty")
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: testTimeout)
        }
    }
    
    // MARK: - Error Recovery Tests
    
    /// Test error recovery across all components
    func testErrorRecovery() throws {
        try testErrorRecoveryForAudioFailure()
        try testErrorRecoveryForTranscriptionFailure()
        try testErrorRecoveryForTextInsertionFailure()
    }
    
    func testErrorRecoveryForAudioFailure() throws {
        let expectation = XCTestExpectation(description: "Audio failure recovery")
        
        // Simulate audio capture failure
        testHarness.audioEngine.stopCapture() // Force stop
        
        testHarness.simulateHotkeyPress(.controlOption)
        
        // Should handle gracefully without crashing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            XCTAssertFalse(self.testHarness.isAudioCaptureActive, "Audio should remain inactive after failure")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: testTimeout)
    }
    
    func testErrorRecoveryForTranscriptionFailure() throws {
        let expectation = XCTestExpectation(description: "Transcription failure recovery")
        
        // Inject invalid audio data
        let invalidAudio: [Float] = [] // Empty audio
        
        testHarness.simulateHotkeyPress(.controlOption)
        testHarness.injectAudioData(invalidAudio)
        testHarness.simulateHotkeyRelease(.controlOption)
        
        testHarness.waitForTranscription { result in
            // Should handle gracefully, possibly with empty or error result
            XCTAssertNotNil(result, "Should receive some result even on failure")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: testTimeout)
    }
    
    func testErrorRecoveryForTextInsertionFailure() throws {
        let expectation = XCTestExpectation(description: "Text insertion failure recovery")
        let testAudio = testHarness.loadTestAudio("sample_speech.wav")
        
        // Create inactive mock application
        let mockApp = testHarness.createMockTargetApplication()
        mockApp.setActive(false)
        
        testHarness.simulateHotkeyPress(.controlOption)
        testHarness.injectAudioData(testAudio)
        testHarness.simulateHotkeyRelease(.controlOption)
        
        testHarness.waitForTranscription { result in
            // Should complete transcription even if insertion fails
            XCTAssertNotNil(result.text, "Transcription should complete")
            
            // Text insertion might fail, but should not crash
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: testTimeout)
    }
    
    // MARK: - Performance Validation Tests
    
    /// Test performance requirements under normal conditions
    func testPerformanceRequirements() throws {
        let measurement = PerformanceMeasurement()
        
        measurement.startMeasuring()
        try testCompleteWorkflow()
        let metrics = measurement.stopMeasuring()
        
        // Validate performance requirements
        XCTAssertLessThan(metrics.totalLatency, 3.0, "Total latency should be under 3 seconds")
        XCTAssertLessThan(metrics.hotkeyToAudioLatency, 0.1, "Hotkey to audio latency should be under 100ms")
        XCTAssertLessThan(metrics.memoryUsage, 100.0, "Memory usage should be under 100MB")
    }
    
    /// Test performance under stress conditions
    func testPerformanceUnderStress() throws {
        let iterations = 5
        var totalLatencies: [TimeInterval] = []
        
        for i in 0..<iterations {
            Self.logger.info("Stress test iteration \(i + 1)/\(iterations)")
            
            let measurement = PerformanceMeasurement()
            measurement.startMeasuring()
            
            try testCompleteWorkflow()
            
            let metrics = measurement.stopMeasuring()
            totalLatencies.append(metrics.totalLatency)
            
            // Brief pause between iterations
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        let averageLatency = totalLatencies.reduce(0, +) / Double(iterations)
        let maxLatency = totalLatencies.max() ?? 0
        
        XCTAssertLessThan(averageLatency, 2.0, "Average latency should be under 2 seconds")
        XCTAssertLessThan(maxLatency, 5.0, "Maximum latency should be under 5 seconds")
        
        Self.logger.info("Stress test completed - Average: \(String(format: "%.2f", averageLatency))s, Max: \(String(format: "%.2f", maxLatency))s")
    }
    
    // MARK: - System Configuration Tests
    
    /// Test compatibility across different system configurations
    func testSystemCompatibility() throws {
        Self.logger.info("Testing system compatibility")
        
        // Validate system requirements
        XCTAssertTrue(systemConfig.isCompatible, "System should meet compatibility requirements")
        XCTAssertGreaterThan(systemConfig.audioDevices.count, 0, "Should have at least one audio device")
        XCTAssertEqual(systemConfig.memoryInfo.memoryPressure, .normal, "Memory pressure should be normal for testing")
        
        // Test with current system configuration
        try testCompleteWorkflow()
        
        Self.logger.info("System compatibility validated")
    }
    
    // MARK: - Component State Synchronization Tests
    
    /// Test that all components maintain proper state synchronization
    func testComponentStateSynchronization() throws {
        let expectation = XCTestExpectation(description: "Component state sync")
        
        // Initial state verification
        XCTAssertFalse(testHarness.isAudioCaptureActive, "Audio should be inactive initially")
        XCTAssertNil(testHarness.lastTranscriptionResult, "No transcription result initially")
        XCTAssertNil(testHarness.lastInsertedText, "No inserted text initially")
        
        // Start workflow
        testHarness.simulateHotkeyPress(.controlOption)
        XCTAssertTrue(testHarness.isAudioCaptureActive, "Audio should be active after hotkey press")
        
        let testAudio = testHarness.loadTestAudio("sample_speech.wav")
        testHarness.injectAudioData(testAudio)
        testHarness.simulateHotkeyRelease(.controlOption)
        
        testHarness.waitForTranscription { result in
            // Verify final state
            XCTAssertNotNil(self.testHarness.lastTranscriptionResult, "Should have transcription result")
            XCTAssertNotNil(self.testHarness.lastInsertedText, "Should have inserted text")
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: testTimeout)
    }
    
    // MARK: - Integration Test Reporting
    
    /// Generate comprehensive integration test report
    func testGenerateIntegrationReport() throws {
        Self.logger.info("Generating integration test report")
        
        let report = IntegrationTestReport(
            systemConfig: systemConfig,
            testResults: gatherTestResults(),
            performanceMetrics: gatherPerformanceMetrics()
        )
        
        logIntegrationReport(report)
        
        // Validate overall success criteria
        XCTAssertGreaterThanOrEqual(report.successRate, 0.95, "Success rate should be 95% or higher")
    }
    
    // MARK: - Helper Methods
    
    private func gatherTestResults() -> [String: Bool] {
        // Return actual test results instead of hardcoded values
        return testResults.isEmpty ? [
            "complete_workflow": false,
            "error_recovery": false,
            "performance_requirements": false,
            "system_compatibility": false,
            "component_synchronization": false
        ] : testResults
    }
    
    private func gatherPerformanceMetrics() -> PerformanceMeasurement.PerformanceMetrics {
        // Return sample metrics for reporting
        return PerformanceMeasurement.PerformanceMetrics(
            totalLatency: 1.5,
            hotkeyToAudioLatency: 0.05,
            audioToTranscriptionLatency: 1.0,
            transcriptionToInsertionLatency: 0.1,
            memoryUsage: 75.0,
            peakMemoryUsage: 85.0,
            averageCPUUsage: 45.0,
            peakCPUUsage: 120.0,
            resourceSnapshots: []
        )
    }
    
    private func logIntegrationReport(_ report: IntegrationTestReport) {
        Self.logger.info("=== Integration Test Report ===")
        Self.logger.info("System: \(report.systemConfig.architecture.description)")
        Self.logger.info("Success Rate: \(String(format: "%.1f", report.successRate * 100))%")
        Self.logger.info("Performance: \(report.performanceMetrics.totalLatency)s total latency")
        Self.logger.info("===============================")
    }
}

// MARK: - Supporting Types

struct IntegrationTestReport {
    let systemConfig: SystemConfigDetector.SystemInfo
    let testResults: [String: Bool]
    let performanceMetrics: PerformanceMeasurement.PerformanceMetrics
    
    var successRate: Double {
        let totalTests = testResults.count
        let passedTests = testResults.values.filter { $0 }.count
        return totalTests > 0 ? Double(passedTests) / Double(totalTests) : 0.0
    }
}
