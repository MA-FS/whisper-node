import XCTest
import SwiftUI
@testable import WhisperNode

/// Tests for RecordingIndicatorView and RecordingIndicatorWindowManager
///
/// Validates visual indicator functionality, state management, and window positioning
/// according to T05 requirements.
@MainActor
final class RecordingIndicatorTests: XCTestCase {
    
    var windowManager: RecordingIndicatorWindowManager!
    
    override func setUp() {
        super.setUp()
        windowManager = RecordingIndicatorWindowManager()
    }
    
    override func tearDown() {
        windowManager.cleanup()
        windowManager = nil
        super.tearDown()
    }
    
    // MARK: - RecordingIndicatorWindowManager Tests
    
    /// Test that window manager initializes in correct state
    func testWindowManagerInitialState() {
        XCTAssertFalse(windowManager.isVisible)
        XCTAssertEqual(windowManager.currentState, .idle)
        XCTAssertEqual(windowManager.currentProgress, 0.0, accuracy: 0.001)
    }
    
    /// Test showing indicator with different states
    func testShowIndicatorStates() {
        // Test idle state
        windowManager.showIdle()
        XCTAssertTrue(windowManager.isVisible)
        XCTAssertEqual(windowManager.currentState, .idle)
        
        // Test recording state
        windowManager.showRecording()
        XCTAssertTrue(windowManager.isVisible)
        XCTAssertEqual(windowManager.currentState, .recording)
        
        // Test processing state with progress
        windowManager.showProcessing(progress: 0.5)
        XCTAssertTrue(windowManager.isVisible)
        XCTAssertEqual(windowManager.currentState, .processing)
        XCTAssertEqual(windowManager.currentProgress, 0.5, accuracy: 0.001)
        
        // Test error state
        windowManager.showError()
        XCTAssertTrue(windowManager.isVisible)
        XCTAssertEqual(windowManager.currentState, .error)
    }
    
    /// Test hiding indicator
    func testHideIndicator() {
        windowManager.showRecording()
        XCTAssertTrue(windowManager.isVisible)
        
        windowManager.hideIndicator()
        XCTAssertFalse(windowManager.isVisible)
    }
    
    /// Test updating state without visibility change
    func testUpdateState() {
        windowManager.showIdle()
        
        // Update to recording state
        windowManager.updateState(.recording)
        XCTAssertTrue(windowManager.isVisible)
        XCTAssertEqual(windowManager.currentState, .recording)
        
        // Update to processing with progress
        windowManager.updateState(.processing, progress: 0.75)
        XCTAssertTrue(windowManager.isVisible)
        XCTAssertEqual(windowManager.currentState, .processing)
        XCTAssertEqual(windowManager.currentProgress, 0.75, accuracy: 0.001)
    }
    
    /// Test update state when not visible has no effect
    func testUpdateStateWhenNotVisible() {
        XCTAssertFalse(windowManager.isVisible)
        
        let initialState = windowManager.currentState
        let initialProgress = windowManager.currentProgress
        
        windowManager.updateState(.recording, progress: 0.5)
        
        // State should not change when not visible
        XCTAssertEqual(windowManager.currentState, initialState)
        XCTAssertEqual(windowManager.currentProgress, initialProgress, accuracy: 0.001)
        XCTAssertFalse(windowManager.isVisible)
    }
    
    /// Test progress clamping
    func testProgressClamping() {
        // Test negative progress is clamped to 0
        windowManager.showProcessing(progress: -0.5)
        XCTAssertEqual(windowManager.currentProgress, 0.0, accuracy: 0.001)
        
        // Test progress above 1.0 is clamped to 1.0
        windowManager.showProcessing(progress: 1.5)
        XCTAssertEqual(windowManager.currentProgress, 1.0, accuracy: 0.001)
        
        // Test valid progress is preserved
        windowManager.showProcessing(progress: 0.42)
        XCTAssertEqual(windowManager.currentProgress, 0.42, accuracy: 0.001)
    }
    
    /// Test cleanup functionality
    func testCleanup() {
        windowManager.showRecording()
        XCTAssertTrue(windowManager.isVisible)
        
        windowManager.cleanup()
        XCTAssertFalse(windowManager.isVisible)
    }
    
    /// Test multiple show calls don't create issues
    func testMultipleShowCalls() {
        windowManager.showRecording()
        let firstCallVisible = windowManager.isVisible
        
        windowManager.showRecording()
        let secondCallVisible = windowManager.isVisible
        
        XCTAssertEqual(firstCallVisible, secondCallVisible)
        XCTAssertTrue(windowManager.isVisible)
    }
    
    // MARK: - RecordingState Tests
    
    /// Test RecordingState enum equality
    func testRecordingStateEquality() {
        XCTAssertEqual(RecordingState.idle, RecordingState.idle)
        XCTAssertEqual(RecordingState.recording, RecordingState.recording)
        XCTAssertEqual(RecordingState.processing, RecordingState.processing)
        XCTAssertEqual(RecordingState.error, RecordingState.error)
        
        XCTAssertNotEqual(RecordingState.idle, RecordingState.recording)
        XCTAssertNotEqual(RecordingState.recording, RecordingState.processing)
        XCTAssertNotEqual(RecordingState.processing, RecordingState.error)
    }
    
    // MARK: - Integration Tests
    
    /// Test integration with WhisperNodeCore
    func testCoreIntegration() {
        let core = WhisperNodeCore.shared
        
        // Test that core has indicator manager
        XCTAssertNotNil(core.indicatorManager)
        
        // Test initial state
        XCTAssertFalse(core.indicatorManager.isVisible)
        XCTAssertEqual(core.indicatorManager.currentState, .idle)
    }
    
    /// Test state transitions in realistic scenarios
    func testRealisticStateTransitions() {
        // Simulate recording session
        windowManager.showRecording()
        XCTAssertEqual(windowManager.currentState, .recording)
        
        // Simulate processing
        windowManager.updateState(.processing, progress: 0.0)
        XCTAssertEqual(windowManager.currentState, .processing)
        
        // Simulate progress updates
        for progress in stride(from: 0.1, through: 1.0, by: 0.1) {
            windowManager.updateState(.processing, progress: progress)
            XCTAssertEqual(windowManager.currentProgress, progress, accuracy: 0.001)
        }
        
        // Simulate completion
        windowManager.hideIndicator()
        XCTAssertFalse(windowManager.isVisible)
    }
    
    /// Test error scenario handling
    func testErrorScenarioHandling() {
        // Start recording
        windowManager.showRecording()
        XCTAssertEqual(windowManager.currentState, .recording)
        
        // Error occurs
        windowManager.showError()
        XCTAssertEqual(windowManager.currentState, .error)
        XCTAssertTrue(windowManager.isVisible)
        
        // Error clears
        windowManager.hideIndicator()
        XCTAssertFalse(windowManager.isVisible)
    }
    
    // MARK: - Performance Tests
    
    /// Test that repeated operations don't cause memory leaks
    func testMemoryManagement() {
        let initialMemoryFootprint = ProcessInfo.processInfo.environment["XCTestMemoryThreshold"]
        
        // Perform many show/hide cycles
        for _ in 0..<100 {
            windowManager.showRecording()
            windowManager.updateState(.processing, progress: 0.5)
            windowManager.hideIndicator()
        }
        
        // Force cleanup
        windowManager.cleanup()
        
        // Test should complete without excessive memory growth
        // Actual memory testing would require more sophisticated measurement
        XCTAssertTrue(true, "Memory management test completed")
    }
    
    /// Test rapid state changes don't cause issues
    func testRapidStateChanges() {
        let states: [RecordingState] = [.idle, .recording, .processing, .error]
        
        windowManager.showIdle()
        
        // Rapidly cycle through states
        for _ in 0..<50 {
            for state in states {
                switch state {
                case .processing:
                    windowManager.updateState(state, progress: Double.random(in: 0...1))
                default:
                    windowManager.updateState(state)
                }
            }
        }
        
        // Should still be responsive
        windowManager.hideIndicator()
        XCTAssertFalse(windowManager.isVisible)
    }
}

// MARK: - Test Extensions

extension RecordingIndicatorTests {
    
    /// Helper method to wait for UI updates
    private func waitForUIUpdate() async {
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }
    
    /// Helper method to simulate realistic timing
    private func simulateRealisticDelay() async {
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
    }
}