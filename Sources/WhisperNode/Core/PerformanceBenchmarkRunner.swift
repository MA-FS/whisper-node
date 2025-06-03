import Foundation
import OSLog

/// Automated performance benchmark runner for continuous monitoring
/// Integrates with the performance test suite to validate PRD requirements
public class PerformanceBenchmarkRunner {
    
    private let logger = Logger(subsystem: "com.whispernode.benchmarks", category: "PerformanceBenchmarkRunner")
    private let performanceMonitor: PerformanceMonitor
    
    public struct BenchmarkResult {
        public let testName: String
        public let success: Bool
        public let value: Double
        public let threshold: Double
        public let unit: String
        public let timestamp: Date
        
        public var passed: Bool { success && value <= threshold }
    }
    
    public struct BenchmarkSuite {
        public let name: String
        public let results: [BenchmarkResult]
        public let overallPassed: Bool
        
        public init(name: String, results: [BenchmarkResult]) {
            self.name = name
            self.results = results
            self.overallPassed = results.allSatisfy { $0.passed }
        }
    }
    
    public init(performanceMonitor: PerformanceMonitor = PerformanceMonitor()) {
        self.performanceMonitor = performanceMonitor
    }
    
    // MARK: - Main Benchmark Execution
    
    public func runAllBenchmarks() async -> BenchmarkSuite {
        logger.info("Starting comprehensive performance benchmark suite")
        
        var results: [BenchmarkResult] = []
        
        // Cold Launch Benchmark
        let coldLaunchResult = await benchmarkColdLaunch()
        results.append(coldLaunchResult)
        
        // Transcription Latency Benchmarks
        let latency5sResult = await benchmarkTranscriptionLatency(duration: 5.0, threshold: 1.0)
        results.append(latency5sResult)
        
        let latency15sResult = await benchmarkTranscriptionLatency(duration: 15.0, threshold: 2.0)
        results.append(latency15sResult)
        
        // Memory Usage Benchmarks
        let idleMemoryResult = await benchmarkIdleMemory()
        results.append(idleMemoryResult)
        
        let peakMemoryResult = await benchmarkPeakMemory()
        results.append(peakMemoryResult)
        
        // CPU Utilization Benchmark
        let cpuUtilizationResult = await benchmarkCPUUtilization()
        results.append(cpuUtilizationResult)
        
        // Battery Impact Benchmark
        let batteryImpactResult = await benchmarkBatteryImpact()
        results.append(batteryImpactResult)
        
        let suite = BenchmarkSuite(name: "WhisperNode Performance Validation", results: results)
        
        logger.info("Benchmark suite completed: \(suite.overallPassed ? "PASSED" : "FAILED")")
        logBenchmarkResults(suite)
        
        return suite
    }
    
    // MARK: - Individual Benchmarks
    
    private func benchmarkColdLaunch() async -> BenchmarkResult {
        logger.info("Running cold launch benchmark")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Simulate cold launch
        let core = WhisperNodeCore()
        _ = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let success = core.initialize()
                continuation.resume(returning: success)
            }
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let launchTime = endTime - startTime
        
        return BenchmarkResult(
            testName: "Cold Launch Time",
            success: true,
            value: launchTime,
            threshold: 2.0, // PRD requirement: ≤2s
            unit: "seconds",
            timestamp: Date()
        )
    }
    
    private func benchmarkTranscriptionLatency(duration: TimeInterval, threshold: TimeInterval) async -> BenchmarkResult {
        logger.info("Running transcription latency benchmark for \(duration)s audio")
        
        guard let audioData = generateTestAudio(duration: duration) else {
            return BenchmarkResult(
                testName: "Transcription Latency (\(duration)s)",
                success: false,
                value: Double.infinity,
                threshold: threshold,
                unit: "seconds",
                timestamp: Date()
            )
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let core = WhisperNodeCore()
        _ = core.initialize()
        
        let transcriptionSuccess = await withCheckedContinuation { continuation in
            core.processAudio(audioData) { result in
                continuation.resume(returning: result.isSuccess)
            }
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let latency = endTime - startTime
        
        return BenchmarkResult(
            testName: "Transcription Latency (\(duration)s)",
            success: transcriptionSuccess,
            value: latency,
            threshold: threshold,
            unit: "seconds",
            timestamp: Date()
        )
    }
    
    private func benchmarkIdleMemory() async -> BenchmarkResult {
        logger.info("Running idle memory usage benchmark")
        
        let core = WhisperNodeCore()
        _ = core.initialize()
        
        // Let the app settle
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        let memoryUsage = getCurrentMemoryUsage()
        
        return BenchmarkResult(
            testName: "Idle Memory Usage",
            success: true,
            value: memoryUsage,
            threshold: 100.0, // PRD requirement: ≤100MB idle
            unit: "MB",
            timestamp: Date()
        )
    }
    
    private func benchmarkPeakMemory() async -> BenchmarkResult {
        logger.info("Running peak memory usage benchmark")
        
        let core = WhisperNodeCore()
        _ = core.initialize()
        
        // Load model and process intensive audio to trigger peak usage
        let modelManager = ModelManager()
        let modelLoaded = await withCheckedContinuation { continuation in
            modelManager.loadModel(.small) { success in
                continuation.resume(returning: success)
            }
        }
        
        guard modelLoaded else {
            return BenchmarkResult(
                testName: "Peak Memory Usage",
                success: false,
                value: Double.infinity,
                threshold: 700.0,
                unit: "MB",
                timestamp: Date()
            )
        }
        
        var peakMemory: Double = 0
        let monitoringTask = Task {
            while !Task.isCancelled {
                let currentMemory = getCurrentMemoryUsage()
                peakMemory = max(peakMemory, currentMemory)
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
        }
        
        // Generate intensive workload
        if let audioData = generateTestAudio(duration: 15.0) {
            let _ = await withCheckedContinuation { continuation in
                core.processAudio(audioData) { result in
                    continuation.resume(returning: result.isSuccess)
                }
            }
        }
        
        monitoringTask.cancel()
        
        return BenchmarkResult(
            testName: "Peak Memory Usage",
            success: true,
            value: peakMemory,
            threshold: 700.0, // PRD requirement: ≤700MB peak with small.en
            unit: "MB",
            timestamp: Date()
        )
    }
    
    private func benchmarkCPUUtilization() async -> BenchmarkResult {
        logger.info("Running CPU utilization benchmark")
        
        let core = WhisperNodeCore()
        _ = core.initialize()
        
        var maxCPU: Double = 0
        let monitoringTask = Task {
            while !Task.isCancelled {
                let currentCPU = getCurrentCPUUsage()
                maxCPU = max(maxCPU, currentCPU)
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
        }
        
        // Process audio to measure CPU during transcription
        if let audioData = generateTestAudio(duration: 10.0) {
            let _ = await withCheckedContinuation { continuation in
                core.processAudio(audioData) { result in
                    continuation.resume(returning: result.isSuccess)
                }
            }
        }
        
        monitoringTask.cancel()
        
        return BenchmarkResult(
            testName: "CPU Utilization During Transcription",
            success: true,
            value: maxCPU,
            threshold: 150.0, // PRD requirement: <150% during transcription
            unit: "%",
            timestamp: Date()
        )
    }
    
    private func benchmarkBatteryImpact() async -> BenchmarkResult {
        logger.info("Running battery impact benchmark")
        
        let core = WhisperNodeCore()
        _ = core.initialize()
        
        let testDuration: TimeInterval = 30.0 // 30 second test for CI
        var totalCPU: Double = 0
        var sampleCount = 0
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let monitoringTask = Task {
            while !Task.isCancelled {
                let currentTime = CFAbsoluteTimeGetCurrent()
                if currentTime - startTime >= testDuration {
                    break
                }
                
                // Simulate periodic transcription
                if let audioData = generateTestAudio(duration: 3.0) {
                    core.processAudio(audioData) { _ in }
                }
                
                totalCPU += getCurrentCPUUsage()
                sampleCount += 1
                
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }
        
        await monitoringTask.value
        
        let averageCPU = sampleCount > 0 ? totalCPU / Double(sampleCount) : 0
        
        return BenchmarkResult(
            testName: "Average CPU During Operation",
            success: true,
            value: averageCPU,
            threshold: 150.0, // PRD requirement: <150% average for battery efficiency
            unit: "%",
            timestamp: Date()
        )
    }
    
    // MARK: - Helper Methods
    
    private func generateTestAudio(duration: TimeInterval) -> Data? {
        // First try to load real test audio data
        if let realAudioData = loadRealTestAudio(duration: duration) {
            logger.info("Using real test audio for duration: \(duration)s")
            return realAudioData
        }
        
        // Fallback to synthetic audio with warning
        logger.warning("Real test audio not available for \(duration)s, using synthetic audio. This may affect accuracy testing.")
        return generateSyntheticAudio(duration: duration)
    }
    
    private func loadRealTestAudio(duration: TimeInterval) -> Data? {
        // Try to load from test bundle first
        if let bundle = Bundle(for: type(of: self)) {
            let resourceName = "test_audio_\(Int(duration))s"
            if let audioPath = bundle.path(forResource: resourceName, ofType: "wav") {
                do {
                    let audioData = try Data(contentsOf: URL(fileURLWithPath: audioPath))
                    return validateAndConvertAudioData(audioData, expectedDuration: duration)
                } catch {
                    logger.warning("Failed to load test audio \(resourceName).wav: \(error)")
                }
            }
        }
        
        // Try to load from project test resources directory
        let projectPath = FileManager.default.currentDirectoryPath
        let testResourcesPath = "\(projectPath)/Tests/WhisperNodeTests/TestResources"
        let resourceName = "test_audio_\(Int(duration))s.wav"
        let audioPath = "\(testResourcesPath)/\(resourceName)"
        
        if FileManager.default.fileExists(atPath: audioPath) {
            do {
                let audioData = try Data(contentsOf: URL(fileURLWithPath: audioPath))
                return validateAndConvertAudioData(audioData, expectedDuration: duration)
            } catch {
                logger.warning("Failed to load test audio from \(audioPath): \(error)")
            }
        }
        
        return nil
    }
    
    private func validateAndConvertAudioData(_ data: Data, expectedDuration: TimeInterval) -> Data? {
        // Basic validation - ensure we have enough data for the expected duration
        // For 16kHz mono 16-bit: duration * 16000 * 2 bytes per sample
        let expectedBytes = Int(expectedDuration * 16000 * 2)
        let minBytes = Int(Double(expectedBytes) * 0.8) // Allow 20% variance
        let maxBytes = Int(Double(expectedBytes) * 1.2)
        
        guard data.count >= minBytes && data.count <= maxBytes else {
            logger.warning("Audio data size (\(data.count) bytes) outside expected range (\(minBytes)-\(maxBytes) bytes)")
            return nil
        }
        
        // TODO: Add more sophisticated validation for sample rate, channels, etc.
        // For now, assume the audio file is in correct format
        return data
    }
    
    private func generateSyntheticAudio(duration: TimeInterval) -> Data? {
        let sampleRate: Double = 16000
        let samples = Int(duration * sampleRate)
        var audioData = Data()
        
        // Generate more realistic audio pattern (speech-like formants)
        for i in 0..<samples {
            let t = Double(i) / sampleRate
            
            // Create speech-like formants with varying amplitude
            let fundamental = 200.0 // Base frequency
            let formant1 = sin(2.0 * Double.pi * fundamental * t)
            let formant2 = sin(2.0 * Double.pi * fundamental * 2.5 * t) * 0.6
            let formant3 = sin(2.0 * Double.pi * fundamental * 4.0 * t) * 0.3
            
            // Add some amplitude modulation to simulate speech patterns
            let ampMod = 0.5 + 0.5 * sin(2.0 * Double.pi * 5.0 * t) // 5Hz modulation
            
            let sample = (formant1 + formant2 + formant3) * ampMod * 0.3
            let scaledSample = Int16(sample * 16384)
            
            withUnsafeBytes(of: scaledSample) { bytes in
                audioData.append(contentsOf: bytes)
            }
        }
        
        return audioData
    }
    
    private func getCurrentMemoryUsage() -> Double {
        let task = mach_task_self_
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(task, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else { 
            logger.warning("Failed to get accurate memory usage, falling back to basic measurement")
            // Fallback to basic measurement if task_vm_info fails
            var basicInfo = mach_task_basic_info()
            var basicCount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
            
            let basicResult = withUnsafeMutablePointer(to: &basicInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    task_info(task, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &basicCount)
                }
            }
            
            guard basicResult == KERN_SUCCESS else { return 0 }
            return Double(basicInfo.resident_size) / 1024.0 / 1024.0
        }
        
        // Use physical footprint for accurate RSS measurement (Apple Technical Note TN2434)
        return Double(info.phys_footprint) / 1024.0 / 1024.0 // Convert to MB
    }
    
    private func getCurrentCPUUsage() -> Double {
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
            if total > 0 {
                let usage = (total - idle) / total * 100.0
                totalUsage += usage
            }
        }
        
        info.deallocate()
        return totalUsage
    }
    
    private func logBenchmarkResults(_ suite: BenchmarkSuite) {
        logger.info("=== BENCHMARK RESULTS ===")
        logger.info("Suite: \(suite.name)")
        logger.info("Overall: \(suite.overallPassed ? "PASSED" : "FAILED")")
        logger.info("")
        
        for result in suite.results {
            let status = result.passed ? "PASS" : "FAIL"
            logger.info("[\(status)] \(result.testName): \(result.value) \(result.unit) (threshold: \(result.threshold) \(result.unit))")
        }
        
        logger.info("========================")
    }
}

// MARK: - Result Extensions

extension Result {
    var isSuccess: Bool {
        switch self {
        case .success: return true
        case .failure: return false
        }
    }
}