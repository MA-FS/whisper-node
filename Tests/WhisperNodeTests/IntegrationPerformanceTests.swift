import XCTest
import os.log
@testable import WhisperNode

/// Integration Performance Tests for WhisperNode
///
/// Tests performance characteristics of text insertion across different
/// application contexts to ensure PRD requirements are met.
///
/// ## Performance Requirements (from PRD)
/// - Latency: ≤1ms per character for mapped characters
/// - Memory: ≤100MB idle, ≤700MB peak during transcription
/// - CPU: <150% core utilization during transcription
/// - Battery: Minimal impact with <150% average CPU
///
/// ## Test Coverage
/// - Text insertion speed across applications
/// - Memory usage during bulk text operations
/// - CPU utilization during concurrent insertions
/// - Battery impact simulation
/// - Application switching performance
class IntegrationPerformanceTests: XCTestCase {
    private static let logger = Logger(subsystem: "com.whispernode.tests", category: "integration-performance")
    
    private let textInsertionEngine = TextInsertionEngine()
    private let performanceMonitor = PerformanceMonitor.shared
    
    // Performance test constants
    private let shortTextSample = "Hello, this is a short test message."
    
    // Timing constants for test execution
    private static let memoryStabilizationDelay: UInt64 = 100_000_000 // 0.1s
    private static let memoryCleanupDelay: UInt64 = 500_000_000 // 0.5s
    private static let iterationDelay: UInt64 = 50_000_000 // 0.05s
    private static let cpuMonitoringDelay: UInt64 = 200_000_000 // 0.2s
    private let mediumTextSample = String(repeating: "This is a medium length text sample for performance testing. ", count: 10)
    private let longTextSample = String(repeating: "This is a longer text sample designed to test performance with substantial content insertion across different applications and text input scenarios. ", count: 50)
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Verify accessibility permissions for performance testing
        guard AXIsProcessTrusted() else {
            throw XCTSkip("Accessibility permissions required for integration performance tests")
        }
        
        Self.logger.info("Starting integration performance tests")
    }
    
    override func tearDownWithError() throws {
        Self.logger.info("Completed integration performance tests")
        try super.tearDownWithError()
    }
    
    // MARK: - Latency Tests
    
    /// Test character insertion latency meets PRD requirement (≤1ms per character)
    func testCharacterInsertionLatency() async throws {
        let testString = "Testing character latency performance"
        let characterCount = testString.count
        
        let startTime = CFAbsoluteTimeGetCurrent()
        await textInsertionEngine.insertText(testString)
        let endTime = CFAbsoluteTimeGetCurrent()
        
        let totalTime = endTime - startTime
        let timePerCharacter = totalTime / Double(characterCount)
        
        Self.logger.info("Character insertion: \(characterCount) chars in \(String(format: "%.3f", totalTime))s (\(String(format: "%.4f", timePerCharacter * 1000))ms per char)")
        
        // PRD requirement: ≤1ms per character
        XCTAssertLessThanOrEqual(timePerCharacter * 1000, 1.0, "Character insertion latency should be ≤1ms per character")
    }
    
    /// Test bulk text insertion performance
    func testBulkTextInsertionPerformance() async throws {
        let measurements = await measure("Bulk Text Insertion") {
            await textInsertionEngine.insertText(mediumTextSample)
        }
        
        let averageTime = measurements.reduce(0, +) / Double(measurements.count)
        let charactersPerSecond = Double(mediumTextSample.count) / averageTime
        
        Self.logger.info("Bulk insertion: \(String(format: "%.0f", charactersPerSecond)) chars/second")
        
        // Should achieve reasonable throughput (>100 chars/second)
        XCTAssertGreaterThan(charactersPerSecond, 100, "Should achieve >100 characters per second")
    }
    
    /// Test performance with special characters and Unicode
    func testUnicodeInsertionPerformance() async throws {
        let unicodeText = "Unicode test: 🌟 émojis café naïve résumé äöü ñ"
        
        let startTime = CFAbsoluteTimeGetCurrent()
        await textInsertionEngine.insertText(unicodeText)
        let endTime = CFAbsoluteTimeGetCurrent()
        
        let totalTime = endTime - startTime
        
        Self.logger.info("Unicode insertion: \(unicodeText.count) chars in \(String(format: "%.3f", totalTime))s")
        
        // Unicode insertion should complete within reasonable time
        // Based on ~50 characters and 1ms/char requirement, allow 2x margin = 100ms
        XCTAssertLessThan(totalTime, 0.1, "Unicode text insertion should complete within 100ms")
    }
    
    // MARK: - Memory Performance Tests
    
    /// Test memory usage during text insertion operations
    func testMemoryUsageStability() async throws {
        let initialMemory = getCurrentMemoryUsage()
        
        // Perform multiple text insertions
        for i in 0..<10 {
            await textInsertionEngine.insertText("Memory test iteration \(i): \(shortTextSample)")
            
            // Small delay to allow for memory monitoring
            try await Task.sleep(nanoseconds: Self.memoryStabilizationDelay)
        }
        
        // Allow for cleanup
        try await Task.sleep(nanoseconds: Self.memoryCleanupDelay)
        
        let finalMemory = getCurrentMemoryUsage()
        let memoryIncrease = finalMemory - initialMemory
        
        Self.logger.info("Memory usage: Initial \(initialMemory)MB, Final \(finalMemory)MB, Increase \(memoryIncrease)MB")
        
        // Memory increase should be minimal (≤10MB for these operations)
        XCTAssertLessThan(memoryIncrease, 10.0, "Memory increase should be minimal during text insertion")
    }
    
    /// Test memory usage with large text insertions
    func testLargeTextMemoryEfficiency() async throws {
        let initialMemory = getCurrentMemoryUsage()
        
        // Insert large text sample
        await textInsertionEngine.insertText(longTextSample)
        
        let peakMemory = getCurrentMemoryUsage()
        let memoryIncrease = peakMemory - initialMemory
        
        Self.logger.info("Large text memory: \(longTextSample.count) chars, Memory increase \(memoryIncrease)MB")
        
        // Memory usage should remain reasonable even for large text
        XCTAssertLessThan(memoryIncrease, 50.0, "Memory usage should remain efficient for large text")
    }
    
    // MARK: - CPU Performance Tests
    
    /// Test CPU utilization during text insertion
    func testCPUUtilizationEfficiency() async throws {
        let performanceMetrics = await performanceMonitor.getCurrentMetrics()
        let initialCPU = performanceMetrics.cpuUsage
        
        // Perform intensive text insertion operations
        let intensiveOperations = Array(0..<5).map { index in
            "Intensive CPU test \(index): \(mediumTextSample)"
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for text in intensiveOperations {
            await textInsertionEngine.insertText(text)
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05s between operations
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let operationTime = endTime - startTime
        
        // Monitor CPU usage after operations
        try await Task.sleep(nanoseconds: Self.cpuMonitoringDelay)
        let finalMetrics = await performanceMonitor.getCurrentMetrics()
        let peakCPU = finalMetrics.cpuUsage
        
        Self.logger.info("CPU utilization: Initial \(String(format: "%.1f", initialCPU))%, Peak \(String(format: "%.1f", peakCPU))%, Duration \(String(format: "%.3f", operationTime))s")
        
        // CPU utilization should remain reasonable (≤150% as per PRD)
        XCTAssertLessThan(peakCPU, 150.0, "CPU utilization should remain ≤150% during text insertion")
    }
    
    /// Test concurrent text insertion performance
    func testConcurrentInsertionPerformance() async throws {
        let concurrentTexts = [
            "Concurrent test 1: \(shortTextSample)",
            "Concurrent test 2: \(shortTextSample)",
            "Concurrent test 3: \(shortTextSample)"
        ]
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Note: TextInsertionEngine is an actor, so these will be serialized
        // This tests the actor's ability to handle rapid sequential calls
        await withTaskGroup(of: Void.self) { group in
            for text in concurrentTexts {
                group.addTask {
                    await self.textInsertionEngine.insertText(text)
                }
            }
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let totalTime = endTime - startTime
        
        Self.logger.info("Concurrent insertion: 3 operations in \(String(format: "%.3f", totalTime))s")
        
        // Concurrent operations should complete efficiently
        XCTAssertLessThan(totalTime, 2.0, "Concurrent text insertion should complete within 2 seconds")
    }
    
    // MARK: - Application Switching Performance
    
    /// Test performance impact of rapid application context switching
    func testApplicationSwitchingPerformance() async throws {
        // Simulate application switching by varying insertion patterns
        let switchingScenarios = [
            ("Short burst", shortTextSample),
            ("Medium content", String(mediumTextSample.prefix(100))),
            ("Unicode content", "Test with émojis 🌟 and accénts"),
            ("Punctuation heavy", "Test! With? Lots. Of: Punctuation; Here, Right?"),
            ("Numbers and symbols", "Order #123: $45.67 (15% off) = $38.82")
        ]
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for (scenario, text) in switchingScenarios {
            Self.logger.debug("Testing scenario: \(scenario)")
            await textInsertionEngine.insertText(text)
            
            // Brief pause to simulate app switching
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let totalTime = endTime - startTime
        
        Self.logger.info("Application switching simulation: \(switchingScenarios.count) scenarios in \(String(format: "%.3f", totalTime))s")
        
        // App switching should not significantly impact performance
        XCTAssertLessThan(totalTime, 5.0, "Application switching scenarios should complete efficiently")
    }
    
    // MARK: - Performance Regression Tests
    
    /// Test performance consistency over multiple iterations
    func testPerformanceConsistency() async throws {
        var insertionTimes: [Double] = []
        let testText = "Performance consistency test iteration"
        
        // Perform multiple iterations
        for i in 0..<10 {
            let iterationText = "\(testText) \(i)"
            
            let startTime = CFAbsoluteTimeGetCurrent()
            await textInsertionEngine.insertText(iterationText)
            let endTime = CFAbsoluteTimeGetCurrent()
            
            insertionTimes.append(endTime - startTime)
            
            // Brief pause between iterations
            try await Task.sleep(nanoseconds: Self.iterationDelay)
        }
        
        let averageTime = insertionTimes.reduce(0, +) / Double(insertionTimes.count)
        let maxTime = insertionTimes.max() ?? 0
        let minTime = insertionTimes.min() ?? 0
        let variance = maxTime - minTime
        
        Self.logger.info("Performance consistency: Avg \(String(format: "%.4f", averageTime))s, Min \(String(format: "%.4f", minTime))s, Max \(String(format: "%.4f", maxTime))s, Variance \(String(format: "%.4f", variance))s")
        
        // Performance should be consistent (variance ≤100ms)
        XCTAssertLessThan(variance, 0.1, "Performance variance should be ≤100ms")
        
        // Average performance should meet baseline expectations
        XCTAssertLessThan(averageTime, 0.05, "Average insertion time should be ≤50ms for short text")
    }
    
    // MARK: - Helper Methods
    
    /// Measure execution time of async operations
    @discardableResult
    private func measure<T>(_ name: String, iterations: Int = 5, operation: () async throws -> T) async rethrows -> [Double] {
        var measurements: [Double] = []
        
        for _ in 0..<iterations {
            let startTime = CFAbsoluteTimeGetCurrent()
            _ = try await operation()
            let endTime = CFAbsoluteTimeGetCurrent()
            
            measurements.append(endTime - startTime)
            
            // Brief pause between iterations
            try await Task.sleep(nanoseconds: Self.iterationDelay)
        }
        
        let average = measurements.reduce(0, +) / Double(measurements.count)
        Self.logger.debug("\(name) - Average: \(String(format: "%.4f", average))s over \(iterations) iterations")
        
        return measurements
    }
    
    /// Get current memory usage in MB
    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            Self.logger.warning("Failed to get memory usage: kern_return_t = \(result)")
            return 0.0
        }
        
        return Double(info.resident_size) / 1024.0 / 1024.0 // Convert to MB
    }
}