import Foundation
import os.log

/// Performance Measurement Utility for Integration Testing
///
/// Provides comprehensive performance measurement capabilities for
/// integration tests, including latency tracking, resource monitoring,
/// and performance regression detection.
///
/// ## Features
/// - High-precision latency measurement
/// - Memory usage tracking
/// - CPU utilization monitoring
/// - Performance regression detection
/// - Comprehensive metrics reporting
class PerformanceMeasurement {
    
    private static let logger = Logger(subsystem: "com.whispernode.tests", category: "performance")
    
    // MARK: - Measurement State
    
    private var startTime: CFAbsoluteTime = 0
    private var endTime: CFAbsoluteTime = 0
    private var isActive = false
    
    private var memoryBaseline: UInt64 = 0
    private var cpuBaseline: Double = 0.0
    
    private var measurements: [String: TimeInterval] = [:]
    private var resourceSnapshots: [ResourceSnapshot] = []
    private var resourceMonitoringTimer: Timer?
    
    // MARK: - Performance Metrics
    
    struct PerformanceMetrics {
        let totalLatency: TimeInterval
        let hotkeyToAudioLatency: TimeInterval
        let audioToTranscriptionLatency: TimeInterval
        let transcriptionToInsertionLatency: TimeInterval
        let memoryUsage: Double // MB
        let peakMemoryUsage: Double // MB
        let averageCPUUsage: Double // Percentage
        let peakCPUUsage: Double // Percentage
        let resourceSnapshots: [ResourceSnapshot]
    }
    
    struct ResourceSnapshot {
        let timestamp: TimeInterval
        let memoryUsage: UInt64 // bytes
        let cpuUsage: Double // percentage
        let activeThreads: Int
    }
    
    // MARK: - Measurement Control
    
    func startMeasuring() {
        guard !isActive else {
            Self.logger.warning("Performance measurement already active")
            return
        }
        
        startTime = CFAbsoluteTimeGetCurrent()
        isActive = true
        
        // Capture baseline metrics
        memoryBaseline = getCurrentMemoryUsage()
        cpuBaseline = getCurrentCPUUsage()
        
        // Clear previous measurements
        measurements.removeAll()
        resourceSnapshots.removeAll()
        
        // Start resource monitoring
        startResourceMonitoring()
        
        Self.logger.info("Performance measurement started")
    }
    
    func stopMeasuring() -> PerformanceMetrics {
        guard isActive else {
            Self.logger.warning("Performance measurement not active")
            return createEmptyMetrics()
        }
        
        endTime = CFAbsoluteTimeGetCurrent()
        isActive = false
        
        // Stop resource monitoring
        stopResourceMonitoring()
        
        // Calculate final metrics
        let metrics = calculateMetrics()
        
        Self.logger.info("Performance measurement completed")
        logMetrics(metrics)
        
        return metrics
    }
    
    // MARK: - Checkpoint Measurement
    
    func markCheckpoint(_ name: String) {
        guard isActive else {
            Self.logger.warning("Cannot mark checkpoint: measurement not active")
            return
        }
        
        let currentTime = CFAbsoluteTimeGetCurrent()
        let elapsed = currentTime - startTime
        measurements[name] = elapsed
        
        // Capture resource snapshot
        captureResourceSnapshot()
        
        Self.logger.debug("Checkpoint '\(name)': \(String(format: "%.4f", elapsed))s")
    }
    
    // MARK: - Specific Latency Measurements
    
    func measureHotkeyToAudioLatency() -> TimeInterval {
        return measurements["audio_start"] ?? 0.0
    }
    
    func measureAudioToTranscriptionLatency() -> TimeInterval {
        let audioStart = measurements["audio_start"] ?? 0.0
        let transcriptionStart = measurements["transcription_start"] ?? 0.0
        return max(0.0, transcriptionStart - audioStart)
    }
    
    func measureTranscriptionToInsertionLatency() -> TimeInterval {
        let transcriptionEnd = measurements["transcription_complete"] ?? 0.0
        let insertionComplete = measurements["text_inserted"] ?? 0.0
        return max(0.0, insertionComplete - transcriptionEnd)
    }
    
    // MARK: - Resource Monitoring
    
    private func startResourceMonitoring() {
        // Start periodic resource monitoring
        resourceMonitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self, self.isActive else {
                timer.invalidate()
                return
            }
            self.captureResourceSnapshot()
        }
    }

    private func stopResourceMonitoring() {
        resourceMonitoringTimer?.invalidate()
        resourceMonitoringTimer = nil
    }
    
    private func captureResourceSnapshot() {
        let timestamp = CFAbsoluteTimeGetCurrent() - startTime
        let memoryUsage = getCurrentMemoryUsage()
        let cpuUsage = getCurrentCPUUsage()
        let activeThreads = getActiveThreadCount()
        
        let snapshot = ResourceSnapshot(
            timestamp: timestamp,
            memoryUsage: memoryUsage,
            cpuUsage: cpuUsage,
            activeThreads: activeThreads
        )
        
        resourceSnapshots.append(snapshot)
    }
    
    // MARK: - System Resource Queries
    
    private func getCurrentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        return kerr == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }
    
    private func getCurrentCPUUsage() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        guard result == KERN_SUCCESS, let threads = threadList else {
            return 0.0
        }

        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(threadCount * UInt32(MemoryLayout<thread_t>.size)))
        }

        var totalCPUUsage: Double = 0.0

        for i in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)

            let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                }
            }

            if infoResult == KERN_SUCCESS {
                totalCPUUsage += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }

        return totalCPUUsage
    }
    
    private func getActiveThreadCount() -> Int {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        
        if result == KERN_SUCCESS {
            // Clean up the thread list
            if let list = threadList {
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: list), vm_size_t(threadCount * UInt32(MemoryLayout<thread_t>.size)))
            }
            return Int(threadCount)
        }
        
        return 0
    }
    
    // MARK: - Metrics Calculation
    
    private func calculateMetrics() -> PerformanceMetrics {
        let totalLatency = endTime - startTime
        
        let hotkeyToAudio = measureHotkeyToAudioLatency()
        let audioToTranscription = measureAudioToTranscriptionLatency()
        let transcriptionToInsertion = measureTranscriptionToInsertionLatency()
        
        // Calculate memory metrics
        let memoryUsages = resourceSnapshots.map { Double($0.memoryUsage) / 1024.0 / 1024.0 } // Convert to MB
        let currentMemory = memoryUsages.last ?? 0.0
        let peakMemory = memoryUsages.max() ?? 0.0
        
        // Calculate CPU metrics
        let cpuUsages = resourceSnapshots.map { $0.cpuUsage }
        let averageCPU = cpuUsages.isEmpty ? 0.0 : cpuUsages.reduce(0, +) / Double(cpuUsages.count)
        let peakCPU = cpuUsages.max() ?? 0.0
        
        return PerformanceMetrics(
            totalLatency: totalLatency,
            hotkeyToAudioLatency: hotkeyToAudio,
            audioToTranscriptionLatency: audioToTranscription,
            transcriptionToInsertionLatency: transcriptionToInsertion,
            memoryUsage: currentMemory,
            peakMemoryUsage: peakMemory,
            averageCPUUsage: averageCPU,
            peakCPUUsage: peakCPU,
            resourceSnapshots: resourceSnapshots
        )
    }
    
    private func createEmptyMetrics() -> PerformanceMetrics {
        return PerformanceMetrics(
            totalLatency: 0.0,
            hotkeyToAudioLatency: 0.0,
            audioToTranscriptionLatency: 0.0,
            transcriptionToInsertionLatency: 0.0,
            memoryUsage: 0.0,
            peakMemoryUsage: 0.0,
            averageCPUUsage: 0.0,
            peakCPUUsage: 0.0,
            resourceSnapshots: []
        )
    }
    
    // MARK: - Logging and Reporting
    
    private func logMetrics(_ metrics: PerformanceMetrics) {
        Self.logger.info("Performance Metrics Summary:")
        Self.logger.info("  Total Latency: \(String(format: "%.4f", metrics.totalLatency))s")
        Self.logger.info("  Hotkey→Audio: \(String(format: "%.4f", metrics.hotkeyToAudioLatency))s")
        Self.logger.info("  Audio→Transcription: \(String(format: "%.4f", metrics.audioToTranscriptionLatency))s")
        Self.logger.info("  Transcription→Insertion: \(String(format: "%.4f", metrics.transcriptionToInsertionLatency))s")
        Self.logger.info("  Memory Usage: \(String(format: "%.2f", metrics.memoryUsage)) MB (Peak: \(String(format: "%.2f", metrics.peakMemoryUsage)) MB)")
        Self.logger.info("  CPU Usage: \(String(format: "%.2f", metrics.averageCPUUsage))% (Peak: \(String(format: "%.2f", metrics.peakCPUUsage))%)")
    }
    
    // MARK: - Performance Requirements Validation

    struct PerformanceThresholds {
        let maxTotalLatency: TimeInterval
        let maxHotkeyLatency: TimeInterval
        let maxMemoryUsage: Double
        let maxCPUUsage: Double

        static let `default` = PerformanceThresholds(
            maxTotalLatency: 3.0,
            maxHotkeyLatency: 0.1,
            maxMemoryUsage: 100.0,
            maxCPUUsage: 150.0
        )

        static let relaxed = PerformanceThresholds(
            maxTotalLatency: 5.0,
            maxHotkeyLatency: 0.2,
            maxMemoryUsage: 150.0,
            maxCPUUsage: 200.0
        )
    }

    func validatePerformanceRequirements(_ metrics: PerformanceMetrics, thresholds: PerformanceThresholds = .default) -> ValidationResult {
        var issues: [String] = []

        // Check latency requirements
        if metrics.totalLatency > thresholds.maxTotalLatency {
            issues.append("Total latency (\(String(format: "%.2f", metrics.totalLatency))s) exceeds \(String(format: "%.1f", thresholds.maxTotalLatency))s requirement")
        }

        if metrics.hotkeyToAudioLatency > thresholds.maxHotkeyLatency {
            issues.append("Hotkey to audio latency (\(String(format: "%.3f", metrics.hotkeyToAudioLatency))s) exceeds \(String(format: "%.0f", thresholds.maxHotkeyLatency * 1000))ms requirement")
        }

        // Check memory requirements
        if metrics.peakMemoryUsage > thresholds.maxMemoryUsage {
            issues.append("Peak memory usage (\(String(format: "%.2f", metrics.peakMemoryUsage)) MB) exceeds \(String(format: "%.0f", thresholds.maxMemoryUsage))MB requirement")
        }

        // Check CPU requirements
        if metrics.peakCPUUsage > thresholds.maxCPUUsage {
            issues.append("Peak CPU usage (\(String(format: "%.2f", metrics.peakCPUUsage))%) exceeds \(String(format: "%.0f", thresholds.maxCPUUsage))% requirement")
        }

        return ValidationResult(
            passed: issues.isEmpty,
            issues: issues,
            metrics: metrics
        )
    }
    
    struct ValidationResult {
        let passed: Bool
        let issues: [String]
        let metrics: PerformanceMetrics
    }
}
