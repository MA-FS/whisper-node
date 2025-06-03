import XCTest
import Foundation
import AVFoundation
@testable import WhisperNode

/// Comprehensive performance testing suite validating PRD requirements
/// 
/// Performance Requirements from PRD:
/// - Cold launch: ≤2s
/// - Transcription latency: ≤1s for 5s utterances, ≤2s for 15s utterances  
/// - Memory usage: ≤100MB idle, ≤700MB peak with small.en model
/// - CPU utilization: <150% during transcription
/// - Accuracy: ≥95% WER on Librispeech test subset
class PerformanceTestSuite: XCTestCase {
    
    private var core: WhisperNodeCore!
    private var performanceMonitor: PerformanceMonitor!
    private var modelManager: ModelManager!
    
    override func setUp() {
        super.setUp()
        core = WhisperNodeCore()
        performanceMonitor = PerformanceMonitor()
        modelManager = ModelManager()
    }
    
    override func tearDown() {
        core = nil
        performanceMonitor = nil
        modelManager = nil
        super.tearDown()
    }
    
    // MARK: - Cold Launch Performance
    
    func testColdLaunchTime() {
        let launchStartTime = CFAbsoluteTimeGetCurrent()
        
        measure(metrics: [XCTClockMetric()]) {
            let startTime = CFAbsoluteTimeGetCurrent()
            
            // Simulate cold launch initialization
            let core = WhisperNodeCore()
            _ = core.initialize()
            
            let endTime = CFAbsoluteTimeGetCurrent()
            let launchTime = endTime - startTime
            
            // PRD requirement: ≤2s cold launch
            XCTAssertLessThanOrEqual(launchTime, 2.0, 
                "Cold launch time (\(launchTime)s) exceeds 2s requirement")
        }
    }
    
    // MARK: - Transcription Latency Testing
    
    func testTranscriptionLatency5Seconds() {
        guard let audioData = generateTestAudio(duration: 5.0) else {
            XCTFail("Failed to generate 5s test audio")
            return
        }
        
        measure(metrics: [XCTClockMetric()]) {
            let startTime = CFAbsoluteTimeGetCurrent()
            
            let expectation = XCTestExpectation(description: "5s transcription")
            
            core.processAudio(audioData) { result in
                let endTime = CFAbsoluteTimeGetCurrent()
                let latency = endTime - startTime
                
                // PRD requirement: ≤1s for 5s utterances
                XCTAssertLessThanOrEqual(latency, 1.0,
                    "5s transcription latency (\(latency)s) exceeds 1s requirement")
                
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 3.0)
        }
    }
    
    func testTranscriptionLatency15Seconds() {
        guard let audioData = generateTestAudio(duration: 15.0) else {
            XCTFail("Failed to generate 15s test audio")
            return
        }
        
        measure(metrics: [XCTClockMetric()]) {
            let startTime = CFAbsoluteTimeGetCurrent()
            
            let expectation = XCTestExpectation(description: "15s transcription")
            
            core.processAudio(audioData) { result in
                let endTime = CFAbsoluteTimeGetCurrent()
                let latency = endTime - startTime
                
                // PRD requirement: ≤2s for 15s utterances
                XCTAssertLessThanOrEqual(latency, 2.0,
                    "15s transcription latency (\(latency)s) exceeds 2s requirement")
                
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 4.0)
        }
    }
    
    // MARK: - Memory Usage Validation
    
    func testIdleMemoryUsage() {
        // Initialize app and let it settle
        _ = core.initialize()
        sleep(2)
        
        let idleMemory = getMemoryUsage()
        
        // PRD requirement: ≤100MB idle
        let maxIdleMemoryMB = 100.0
        XCTAssertLessThanOrEqual(idleMemory, maxIdleMemoryMB,
            "Idle memory usage (\(idleMemory)MB) exceeds 100MB requirement")
    }
    
    func testPeakMemoryUsage() {
        // Load small.en model and process audio to trigger peak usage
        let expectation = XCTestExpectation(description: "Peak memory test")
        
        modelManager.loadModel(.small) { [weak self] success in
            guard success, let self = self else {
                XCTFail("Failed to load small.en model")
                expectation.fulfill()
                return
            }
            
            // Generate intensive workload
            guard let audioData = self.generateTestAudio(duration: 15.0) else {
                XCTFail("Failed to generate test audio")
                expectation.fulfill()
                return
            }
            
            // Start memory monitoring
            var peakMemory: Double = 0
            let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                let currentMemory = self.getMemoryUsage()
                peakMemory = max(peakMemory, currentMemory)
            }
            
            self.core.processAudio(audioData) { result in
                timer.invalidate()
                
                // PRD requirement: ≤700MB peak with small.en model
                let maxPeakMemoryMB = 700.0
                XCTAssertLessThanOrEqual(peakMemory, maxPeakMemoryMB,
                    "Peak memory usage (\(peakMemory)MB) exceeds 700MB requirement")
                
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    // MARK: - CPU Utilization Measurement
    
    func testCPUUtilizationDuringTranscription() {
        guard let audioData = generateTestAudio(duration: 10.0) else {
            XCTFail("Failed to generate test audio")
            return
        }
        
        let expectation = XCTestExpectation(description: "CPU utilization test")
        
        // Start CPU monitoring
        var maxCPUUsage: Double = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            let currentCPU = self.getCPUUsage()
            maxCPUUsage = max(maxCPUUsage, currentCPU)
        }
        
        core.processAudio(audioData) { result in
            timer.invalidate()
            
            // PRD requirement: <150% during transcription
            let maxCPUPercent = 150.0
            XCTAssertLessThan(maxCPUUsage, maxCPUPercent,
                "CPU usage (\(maxCPUUsage)%) exceeds 150% requirement")
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 8.0)
    }
    
    // MARK: - Battery Impact Assessment
    
    func testBatteryImpactDuringOperation() {
        // Test continuous operation for battery impact
        let testDuration: TimeInterval = 60.0 // 1 minute test
        let expectation = XCTestExpectation(description: "Battery impact test")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        var totalCPUTime: Double = 0
        var sampleCount = 0
        
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            let currentTime = CFAbsoluteTimeGetCurrent()
            let elapsed = currentTime - startTime
            
            if elapsed >= testDuration {
                timer.invalidate()
                
                let averageCPU = totalCPUTime / Double(sampleCount)
                
                // PRD requirement: <150% average CPU for battery efficiency
                XCTAssertLessThan(averageCPU, 150.0,
                    "Average CPU usage (\(averageCPU)%) too high for battery efficiency")
                
                expectation.fulfill()
                return
            }
            
            // Simulate periodic transcription
            if let audioData = self.generateTestAudio(duration: 3.0) {
                self.core.processAudio(audioData) { _ in }
            }
            
            totalCPUTime += self.getCPUUsage()
            sampleCount += 1
        }
        
        wait(for: [expectation], timeout: testDuration + 5.0)
    }
    
    // MARK: - Accuracy Testing with Librispeech
    
    func testAccuracyWithLibrispeechSubset() {
        // Note: In a real implementation, this would load actual Librispeech test data
        let expectation = XCTestExpectation(description: "Accuracy test")
        
        // Simulate Librispeech test subset
        let testCases = generateLibrispeechTestCases()
        var correctTranscriptions = 0
        let totalTests = testCases.count
        
        var completedTests = 0
        
        for testCase in testCases {
            core.processAudio(testCase.audioData) { result in
                switch result {
                case .success(let transcription):
                    let wer = self.calculateWordErrorRate(
                        reference: testCase.expectedText,
                        hypothesis: transcription
                    )
                    
                    // Count as correct if WER is acceptable
                    if wer >= 0.95 { // 95% accuracy requirement
                        correctTranscriptions += 1
                    }
                    
                case .failure:
                    break // Count as incorrect
                }
                
                completedTests += 1
                if completedTests == totalTests {
                    let accuracy = Double(correctTranscriptions) / Double(totalTests)
                    
                    // PRD requirement: ≥95% WER on Librispeech test subset
                    XCTAssertGreaterThanOrEqual(accuracy, 0.95,
                        "Accuracy (\(accuracy * 100)%) below 95% requirement")
                    
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    // MARK: - Helper Methods
    
    private func generateTestAudio(duration: TimeInterval) -> Data? {
        // Generate synthetic audio data for testing
        let sampleRate: Double = 16000
        let samples = Int(duration * sampleRate)
        var audioData = Data()
        
        for i in 0..<samples {
            let sample = sin(2.0 * Double.pi * 440.0 * Double(i) / sampleRate)
            let scaledSample = Int16(sample * 16384)
            audioData.append(Data(bytes: &scaledSample, count: MemoryLayout<Int16>.size))
        }
        
        return audioData
    }
    
    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        guard kerr == KERN_SUCCESS else { return 0 }
        
        return Double(info.resident_size) / 1024.0 / 1024.0 // Convert to MB
    }
    
    private func getCPUUsage() -> Double {
        var info = processor_info_array_t.allocate(capacity: 1)
        var numCpusU: natural_t = 0
        
        let result = host_processor_info(mach_host_self(),
                                       PROCESSOR_CPU_LOAD_INFO,
                                       &numCpusU,
                                       &info,
                                       nil)
        
        guard result == KERN_SUCCESS else { return 0 }
        
        let cpuLoadInfo = info.bindMemory(to: processor_cpu_load_info.self, capacity: Int(numCpusU))
        
        var totalUsage: Double = 0
        for i in 0..<Int(numCpusU) {
            let cpu = cpuLoadInfo[i]
            let total = Double(cpu.cpu_ticks.0 + cpu.cpu_ticks.1 + cpu.cpu_ticks.2 + cpu.cpu_ticks.3)
            let idle = Double(cpu.cpu_ticks.3)
            let usage = (total - idle) / total * 100.0
            totalUsage += usage
        }
        
        info.deallocate()
        return totalUsage / Double(numCpusU)
    }
    
    private struct LibrispeechTestCase {
        let audioData: Data
        let expectedText: String
    }
    
    private func generateLibrispeechTestCases() -> [LibrispeechTestCase] {
        // In a real implementation, this would load actual Librispeech data
        // For testing purposes, we'll generate synthetic test cases
        var testCases: [LibrispeechTestCase] = []
        
        let sampleTexts = [
            "The quick brown fox jumps over the lazy dog",
            "How are you doing today",
            "This is a test of the whisper speech recognition system",
            "Please transcribe this audio accurately",
            "Performance testing is important for quality assurance"
        ]
        
        for text in sampleTexts {
            if let audioData = generateTestAudio(duration: 3.0) {
                testCases.append(LibrispeechTestCase(audioData: audioData, expectedText: text))
            }
        }
        
        return testCases
    }
    
    private func calculateWordErrorRate(reference: String, hypothesis: String) -> Double {
        let refWords = reference.lowercased().components(separatedBy: .whitespaces)
        let hypWords = hypothesis.lowercased().components(separatedBy: .whitespaces)
        
        // Simplified WER calculation (in real implementation, use proper edit distance)
        let maxLength = max(refWords.count, hypWords.count)
        guard maxLength > 0 else { return 1.0 }
        
        var matches = 0
        let minLength = min(refWords.count, hypWords.count)
        
        for i in 0..<minLength {
            if refWords[i] == hypWords[i] {
                matches += 1
            }
        }
        
        return Double(matches) / Double(maxLength)
    }
}