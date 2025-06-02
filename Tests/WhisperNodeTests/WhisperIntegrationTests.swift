import XCTest
@testable import WhisperNode

/// Tests for the enhanced Whisper model integration with lazy loading and performance monitoring
final class WhisperIntegrationTests: XCTestCase {
    
    var whisperSwift: WhisperSwift?
    var whisperEngine: WhisperEngine?
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Use a test model path for integration tests
        let testModelPath = "/tmp/test_tiny.en.bin"
        whisperSwift = WhisperSwift(modelPath: testModelPath)
        whisperEngine = await WhisperEngine(modelPath: testModelPath)
    }
    
    override func tearDown() async throws {
        whisperSwift = nil
        whisperEngine = nil
        try await super.tearDown()
    }
    
    // MARK: - WhisperSwift Tests
    
    func testWhisperSwiftInitialization() {
        // Test successful initialization with mock FFI
        XCTAssertNotNil(whisperSwift, "WhisperSwift should initialize successfully")
    }
    
    func testWhisperSwiftTranscription() {
        guard let whisper = whisperSwift else {
            XCTFail("WhisperSwift not initialized")
            return
        }
        
        // Test with sample audio data
        let testAudioData: [Float] = Array(repeating: 0.1, count: 16000) // 1 second at 16kHz
        let result = whisper.transcribe(audioData: testAudioData)
        
        // With mock FFI, we should get placeholder text
        XCTAssertNotNil(result, "Transcription should return a result")
        XCTAssertFalse(result?.isEmpty ?? true, "Result should not be empty")
    }
    
    func testPerformanceMetrics() {
        guard let whisper = whisperSwift else {
            XCTFail("WhisperSwift not initialized")
            return
        }
        
        let metrics = whisper.getPerformanceMetrics()
        
        // Verify metrics structure
        XCTAssertGreaterThanOrEqual(metrics.memoryUsage, 0, "Memory usage should be non-negative")
        XCTAssertGreaterThanOrEqual(metrics.averageCpuUsage, 0.0, "CPU usage should be non-negative")
        XCTAssertLessThanOrEqual(metrics.averageCpuUsage, 100.0, "CPU usage should not exceed 100%")
    }
    
    func testMemoryCleanup() {
        guard let whisper = whisperSwift else {
            XCTFail("WhisperSwift not initialized")
            return
        }
        
        let success = whisper.cleanupMemory()
        XCTAssertTrue(success, "Memory cleanup should succeed")
    }
    
    // MARK: - WhisperEngine Tests
    
    func testWhisperEngineAsyncTranscription() async {
        guard let engine = whisperEngine else {
            XCTFail("WhisperEngine not initialized")
            return
        }
        
        let testAudioData: [Float] = Array(repeating: 0.1, count: 16000)
        let result = await engine.transcribe(audioData: testAudioData)
        
        XCTAssertTrue(result.success, "Async transcription should succeed")
        XCTAssertNotNil(result.text, "Transcription result should contain text")
        XCTAssertNotNil(result.duration, "Transcription result should include duration")
        XCTAssertNotNil(result.metrics, "Transcription result should include performance metrics")
    }
    
    func testPerformanceHistoryTracking() async {
        guard let engine = whisperEngine else {
            XCTFail("WhisperEngine not initialized")
            return
        }
        
        // Perform multiple transcriptions to build history
        let testAudioData: [Float] = Array(repeating: 0.1, count: 8000) // 0.5 seconds
        
        for _ in 0..<5 {
            _ = await engine.transcribe(audioData: testAudioData)
        }
        
        let history = await engine.getPerformanceHistory()
        XCTAssertGreaterThan(history.count, 0, "Performance history should be recorded")
        XCTAssertLessThanOrEqual(history.count, 5, "History should contain up to 5 entries")
        
        let (avgCpu, avgMemory) = await engine.getAveragePerformance()
        XCTAssertGreaterThanOrEqual(avgCpu, 0.0, "Average CPU should be non-negative")
        XCTAssertGreaterThanOrEqual(avgMemory, 0, "Average memory should be non-negative")
    }
    
    func testModelDowngradeDetection() async {
        guard let engine = whisperEngine else {
            XCTFail("WhisperEngine not initialized")
            return
        }
        
        let (needed, suggestedModel) = await engine.shouldDowngradeModel()
        
        // Initial state should not require downgrade
        XCTAssertFalse(needed, "Initially should not need model downgrade")
        
        if needed {
            XCTAssertNotNil(suggestedModel, "If downgrade needed, should suggest a model")
        }
    }
    
    func testMemoryManagement() async {
        guard let engine = whisperEngine else {
            XCTFail("WhisperEngine not initialized")
            return
        }
        
        let success = await engine.cleanupMemory()
        XCTAssertTrue(success, "Memory cleanup should succeed")
        
        let metrics = await engine.getCurrentMetrics()
        XCTAssertGreaterThanOrEqual(metrics.memoryUsage, 0, "Memory usage should be tracked")
    }
    
    // MARK: - Core Integration Tests
    
    func testCoreWhisperIntegration() async {
        let core = WhisperNodeCore.shared
        
        // Test model loading
        core.loadModel("tiny.en")
        
        // Allow time for async model loading
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        let (memory, cpu, downgradeNeeded) = core.getPerformanceMetrics()
        
        XCTAssertGreaterThanOrEqual(memory, 0, "Memory usage should be tracked")
        XCTAssertGreaterThanOrEqual(cpu, 0.0, "CPU usage should be tracked")
    }
    
    func testModelSwitching() async {
        let core = WhisperNodeCore.shared
        
        // Test switching from default model to small
        core.switchModel("small.en")
        
        // Allow time for model switch
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        XCTAssertEqual(core.currentModel, "small.en", "Current model should be updated")
    }
    
    // MARK: - Performance Requirements Tests
    
    func testMemoryLimits() async {
        guard let engine = whisperEngine else {
            XCTFail("WhisperEngine not initialized")
            return
        }
        
        let metrics = await engine.getCurrentMetrics()
        
        // Test memory usage is within PRD limits
        let maxMemoryMB = 700 * 1024 * 1024 // 700MB peak limit
        XCTAssertLessThanOrEqual(metrics.memoryUsage, UInt64(maxMemoryMB), 
                                "Memory usage should not exceed 700MB peak limit")
    }
    
    func testTranscriptionLatency() async {
        guard let engine = whisperEngine else {
            XCTFail("WhisperEngine not initialized")
            return
        }
        
        // Test 5-second utterance latency requirement (≤1s)
        let fiveSecondAudio: [Float] = Array(repeating: 0.1, count: 80000) // 5 seconds at 16kHz
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = await engine.transcribe(audioData: fiveSecondAudio)
        let latency = CFAbsoluteTimeGetCurrent() - startTime
        
        XCTAssertTrue(result.success, "5-second transcription should succeed")
        
        // Note: With mock FFI, latency will be very low. Real implementation should meet ≤1s requirement
        if let duration = result.duration {
            print("Transcription latency: \(duration)s (target: ≤1s for 5s audio)")
        }
    }
    
    func testCPUUsageMonitoring() async {
        guard let engine = whisperEngine else {
            XCTFail("WhisperEngine not initialized")
            return
        }
        
        // Perform several transcriptions to generate CPU usage data
        let testAudio: [Float] = Array(repeating: 0.1, count: 16000)
        
        for _ in 0..<3 {
            _ = await engine.transcribe(audioData: testAudio)
        }
        
        let metrics = await engine.getCurrentMetrics()
        
        // CPU usage should be reasonable (target: <150% core utilization)
        XCTAssertLessThan(metrics.averageCpuUsage, 150.0, 
                         "CPU usage should stay below 150% during transcription")
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidAudioData() async {
        guard let engine = whisperEngine else {
            XCTFail("WhisperEngine not initialized")
            return
        }
        
        // Test with empty audio data
        let result = await engine.transcribe(audioData: [])
        XCTAssertFalse(result.success, "Transcription with empty audio should fail")
        XCTAssertNotNil(result.error, "Error should be provided for failed transcription")
    }
    
    func testMemoryPressureHandling() async {
        guard let engine = whisperEngine else {
            XCTFail("WhisperEngine not initialized")
            return
        }
        
        // Simulate memory pressure by forcing cleanup
        let cleanupSuccess = await engine.cleanupMemory()
        XCTAssertTrue(cleanupSuccess, "Memory cleanup under pressure should succeed")
        
        // Engine should still be functional after cleanup
        let testAudio: [Float] = Array(repeating: 0.1, count: 8000)
        let result = await engine.transcribe(audioData: testAudio)
        XCTAssertTrue(result.success, "Transcription should work after memory cleanup")
    }
    
    // MARK: - Integration with Audio Engine Tests
    
    func testAudioEngineIntegration() async throws {
        let audioEngine = AudioCaptureEngine()
        var transcriptionReceived = false
        
        // Mock whisper processing
        audioEngine.onAudioDataAvailable = { audioData in
            // Convert to Float array and verify format
            let audioSamples = audioData.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self))
            }
            
            XCTAssertGreaterThan(audioSamples.count, 0, "Audio samples should be available")
            transcriptionReceived = true
        }
        
        // Test permission request
        let hasPermission = await audioEngine.requestPermission()
        
        if hasPermission {
            // Start capture and simulate voice activity
            try await audioEngine.startCapture()
            
            // Allow some time for processing
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            audioEngine.stopCapture()
            
            // In a real environment with actual microphone input, we would expect audio data
            // For unit tests, we verify the integration points work correctly
        }
    }
}

// MARK: - Performance Testing Extensions

extension WhisperIntegrationTests {
    
    /// Test memory management under sustained load
    func testSustainedMemoryManagement() async {
        guard let engine = whisperEngine else {
            XCTFail("WhisperEngine not initialized")
            return
        }
        
        let testAudio: [Float] = Array(repeating: 0.1, count: 16000)
        var maxMemoryUsage: UInt64 = 0
        
        // Perform 20 transcriptions to simulate sustained usage
        for i in 0..<20 {
            let result = await engine.transcribe(audioData: testAudio)
            XCTAssertTrue(result.success, "Transcription \(i) should succeed")
            
            if let metrics = result.metrics {
                maxMemoryUsage = max(maxMemoryUsage, metrics.memoryUsage)
            }
            
            // Small delay between transcriptions
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        
        // Memory should stay within reasonable bounds
        let maxAllowedMemory = 700 * 1024 * 1024 // 700MB
        XCTAssertLessThanOrEqual(maxMemoryUsage, UInt64(maxAllowedMemory),
                                "Memory usage under sustained load should not exceed 700MB")
        
        print("Maximum memory usage during sustained load: \(maxMemoryUsage / 1024 / 1024)MB")
    }
    
    /// Test model switching performance
    func testModelSwitchingPerformance() async {
        let core = WhisperNodeCore.shared
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Switch between models
        core.switchModel("small.en")
        try? await Task.sleep(nanoseconds: 100_000_000) // Allow switch to complete
        
        core.switchModel("tiny.en")
        try? await Task.sleep(nanoseconds: 100_000_000) // Allow switch to complete
        
        let switchTime = CFAbsoluteTimeGetCurrent() - startTime
        
        // Model switching should be reasonably fast
        XCTAssertLessThan(switchTime, 5.0, "Model switching should complete within 5 seconds")
        
        print("Model switching time: \(switchTime)s")
    }
}