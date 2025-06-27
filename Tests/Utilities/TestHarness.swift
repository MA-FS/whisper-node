import XCTest
import Foundation
import AVFoundation
#if canImport(WhisperNode)
@testable import WhisperNode
#endif

// MARK: - Test Constants

struct TestConstants {
    static let defaultTimeout: TimeInterval = 15.0
    static let shortTimeout: TimeInterval = 5.0
    static let longTimeout: TimeInterval = 30.0
    static let audioSampleRate: Float = 16000.0
    static let defaultTestFrequency: Float = 440.0
}

/// Test Harness for Integration Testing
///
/// Provides comprehensive test setup, teardown, and mocking capabilities
/// for integration testing of the complete WhisperNode workflow.
///
/// ## Features
/// - Mock object creation for external dependencies
/// - Test data management and audio sample loading
/// - Workflow simulation and control
/// - Performance measurement integration
/// - System state management for testing
class TestHarness {
    
    // MARK: - Properties
    
    private var mockAudioEngine: MockAudioCaptureEngine?
    private var mockTranscriptionEngine: MockTranscriptionEngine?
    private var mockTextInsertion: MockTextInsertionEngine?
    private var mockHotkeyManager: MockGlobalHotkeyManager?
    
    private var isSetUp = false
    private var testAudioSamples: [String: [Float]] = [:]
    
    // MARK: - Lifecycle
    
    init() {
        setupTestEnvironment()
    }
    
    deinit {
        tearDown()
    }
    
    // MARK: - Setup and Teardown
    
    func setUp() throws {
        guard !isSetUp else { return }
        
        // Initialize mock components
        mockAudioEngine = MockAudioCaptureEngine()
        mockTranscriptionEngine = MockTranscriptionEngine()
        mockTextInsertion = MockTextInsertionEngine()
        mockHotkeyManager = MockGlobalHotkeyManager()
        
        // Load test audio samples
        try loadTestAudioSamples()
        
        isSetUp = true
    }
    
    func tearDown() {
        guard isSetUp else { return }
        
        // Clean up mock components
        mockAudioEngine?.stopCapture()
        mockAudioEngine = nil
        mockTranscriptionEngine = nil
        mockTextInsertion = nil
        mockHotkeyManager = nil
        
        // Clear test data
        testAudioSamples.removeAll()
        
        isSetUp = false
    }
    
    // MARK: - Mock Component Access
    
    var audioEngine: MockAudioCaptureEngine {
        guard let engine = mockAudioEngine else {
            fatalError("TestHarness not set up. Call setUp() first.")
        }
        return engine
    }
    
    var transcriptionEngine: MockTranscriptionEngine {
        guard let engine = mockTranscriptionEngine else {
            fatalError("TestHarness not set up. Call setUp() first.")
        }
        return engine
    }
    
    var textInsertion: MockTextInsertionEngine {
        guard let insertion = mockTextInsertion else {
            fatalError("TestHarness not set up. Call setUp() first.")
        }
        return insertion
    }
    
    var hotkeyManager: MockGlobalHotkeyManager {
        guard let manager = mockHotkeyManager else {
            fatalError("TestHarness not set up. Call setUp() first.")
        }
        return manager
    }
    
    // MARK: - Test Data Management
    
    func loadTestAudio(_ name: String) -> [Float] {
        return testAudioSamples[name] ?? generateSampleAudio(duration: 1.0)
    }
    
    func generateSampleAudio(duration: TimeInterval, frequency: Float = TestConstants.defaultTestFrequency) -> [Float] {
        let sampleRate: Float = TestConstants.audioSampleRate
        let sampleCount = Int(duration * TimeInterval(sampleRate))
        var samples: [Float] = []
        
        for i in 0..<sampleCount {
            let time = Float(i) / sampleRate
            let sample = sin(2.0 * Float.pi * frequency * time) * 0.1
            samples.append(sample)
        }
        
        return samples
    }
    
    // MARK: - Workflow Simulation
    
    func simulateHotkeyPress(_ combination: HotkeyCombination) {
        hotkeyManager.simulateKeyPress(combination)
    }
    
    func simulateHotkeyRelease(_ combination: HotkeyCombination) {
        hotkeyManager.simulateKeyRelease(combination)
    }
    
    func injectAudioData(_ audioData: [Float]) {
        audioEngine.injectAudioData(audioData)
    }
    
    func waitForTranscription(timeout: TimeInterval = TestConstants.shortTimeout, completion: @escaping (TranscriptionResult) -> Void) {
        transcriptionEngine.waitForResult(timeout: timeout, completion: completion)
    }
    
    // MARK: - State Queries
    
    var isAudioCaptureActive: Bool {
        return audioEngine.isCapturing
    }
    
    var lastTranscriptionResult: TranscriptionResult? {
        return transcriptionEngine.lastResult
    }
    
    var lastInsertedText: String? {
        return textInsertion.lastInsertedText
    }
    
    // MARK: - Mock Target Application
    
    func createMockTargetApplication() -> MockTargetApplication {
        return MockTargetApplication()
    }
    
    // MARK: - Private Methods
    
    private func setupTestEnvironment() {
        // Configure test environment settings
    }
    
    private func loadTestAudioSamples() throws {
        // Load predefined test audio samples
        testAudioSamples["sample_speech.wav"] = generateSampleAudio(duration: 2.0, frequency: 440.0)
        testAudioSamples["short_utterance.wav"] = generateSampleAudio(duration: 0.5, frequency: 880.0)
        testAudioSamples["long_utterance.wav"] = generateSampleAudio(duration: 5.0, frequency: 220.0)
        testAudioSamples["silence.wav"] = Array(repeating: 0.0, count: 16000) // 1 second of silence
    }
}

// MARK: - Protocol Interfaces

protocol AudioCaptureEngine {
    var isCapturing: Bool { get }
    func startCapture()
    func stopCapture()
    func injectAudioData(_ data: [Float])
    func getCapturedAudio() -> [Float]
    func clearCapturedAudio()
}

protocol TranscriptionEngine {
    var lastResult: TranscriptionResult? { get }
    func transcribe(_ audioData: [Float]) -> TranscriptionResult
    func waitForResult(timeout: TimeInterval, completion: @escaping (TranscriptionResult) -> Void)
}

protocol TextInsertionEngine {
    var lastInsertedText: String? { get }
    func insertText(_ text: String) -> Bool
    func clearHistory()
}

protocol HotkeyManager {
    func simulateKeyPress(_ combination: HotkeyCombination)
    func simulateKeyRelease(_ combination: HotkeyCombination)
}

// MARK: - Mock Components

class MockAudioCaptureEngine: AudioCaptureEngine {
    private(set) var isCapturing = false
    private var capturedAudio: [Float] = []
    
    func startCapture() {
        isCapturing = true
    }
    
    func stopCapture() {
        isCapturing = false
    }
    
    func injectAudioData(_ data: [Float]) {
        capturedAudio.append(contentsOf: data)
    }
    
    func getCapturedAudio() -> [Float] {
        return capturedAudio
    }
    
    func clearCapturedAudio() {
        capturedAudio.removeAll()
    }
}

class MockTranscriptionEngine: TranscriptionEngine {
    private(set) var lastResult: TranscriptionResult?
    private var pendingCompletion: ((TranscriptionResult) -> Void)?
    
    func transcribe(_ audioData: [Float]) -> TranscriptionResult {
        let result = TranscriptionResult(
            text: "Mock transcription result",
            confidence: 0.95,
            duration: TimeInterval(audioData.count) / 16000.0
        )
        lastResult = result
        
        // Simulate async completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.pendingCompletion?(result)
        }
        
        return result
    }
    
    func waitForResult(timeout: TimeInterval, completion: @escaping (TranscriptionResult) -> Void) {
        pendingCompletion = completion
        
        // Timeout handling
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            if self.pendingCompletion != nil {
                let timeoutResult = TranscriptionResult(
                    text: "",
                    confidence: 0.0,
                    duration: 0.0
                )
                self.pendingCompletion?(timeoutResult)
                self.pendingCompletion = nil
            }
        }
    }
}

class MockTextInsertionEngine: TextInsertionEngine {
    private(set) var lastInsertedText: String?
    private(set) var insertionHistory: [String] = []
    
    func insertText(_ text: String) -> Bool {
        lastInsertedText = text
        insertionHistory.append(text)
        return true
    }
    
    func clearHistory() {
        insertionHistory.removeAll()
        lastInsertedText = nil
    }
}

class MockGlobalHotkeyManager: HotkeyManager {
    private(set) var lastPressedCombination: HotkeyCombination?
    private(set) var lastReleasedCombination: HotkeyCombination?
    
    func simulateKeyPress(_ combination: HotkeyCombination) {
        lastPressedCombination = combination
    }
    
    func simulateKeyRelease(_ combination: HotkeyCombination) {
        lastReleasedCombination = combination
    }
}

class MockTargetApplication {
    private(set) var insertedText: String = ""
    private(set) var isActive: Bool = true
    
    func receiveText(_ text: String) {
        insertedText += text
    }
    
    func clear() {
        insertedText = ""
    }
    
    func setActive(_ active: Bool) {
        isActive = active
    }
}

// MARK: - Supporting Types

struct TranscriptionResult {
    let text: String
    let confidence: Double
    let duration: TimeInterval
}

enum HotkeyCombination {
    case controlOption
    case commandSpace
    case custom(modifiers: [String], key: String)
}
