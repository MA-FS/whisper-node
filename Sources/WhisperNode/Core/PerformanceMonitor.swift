import Foundation
import IOKit.ps
import mach
import os.log

/// Configuration struct for performance monitoring thresholds
public struct PerformanceThresholds {
    let cpuThrottleThreshold: Double
    let lowBatteryThreshold: Float
    let thermalThrottleStates: Set<ProcessInfo.ThermalState>
    
    public static let `default` = PerformanceThresholds(
        cpuThrottleThreshold: 80.0,
        lowBatteryThreshold: 0.15,
        thermalThrottleStates: [.serious, .critical]
    )
    
    public init(cpuThrottleThreshold: Double, lowBatteryThreshold: Float, thermalThrottleStates: Set<ProcessInfo.ThermalState>) {
        self.cpuThrottleThreshold = cpuThrottleThreshold
        self.lowBatteryThreshold = lowBatteryThreshold
        self.thermalThrottleStates = thermalThrottleStates
    }
}

@MainActor
public class PerformanceMonitor: ObservableObject {
    private static let logger = Logger(subsystem: "com.whispernode.core", category: "PerformanceMonitor")
    
    // Published properties for UI binding
    @Published public private(set) var cpuUsage: Double = 0
    @Published public private(set) var memoryUsage: UInt64 = 0
    @Published public private(set) var isThrottling = false
    @Published public private(set) var batteryLevel: Float = 1.0
    @Published public private(set) var isOnBattery = false
    @Published public private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    
    // Performance monitoring state
    private var monitoringTimer: Timer?
    private let monitoringInterval: TimeInterval = 2.0
    private var cpuHistory: [Double] = []
    private let maxHistorySize = 10
    
    // Performance thresholds
    private let thresholds: PerformanceThresholds
    
    public static let shared = PerformanceMonitor()
    
    private init(thresholds: PerformanceThresholds = .default) {
        self.thresholds = thresholds
        Self.logger.info("PerformanceMonitor initializing...")
        loadBenchmarkHistory()
        startMonitoring()
    }
    
    deinit {
        // stopMonitoring will be called automatically when the object is deallocated
        // Cannot call @MainActor methods from deinit
    }
    
    // MARK: - Monitoring Control
    
    public func startMonitoring() {
        stopMonitoring()
        
        Self.logger.info("Starting performance monitoring")
        
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: monitoringInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePerformanceMetrics()
            }
        }
        
        // Initial update
        updatePerformanceMetrics()
    }
    
    public func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        Self.logger.info("Stopped performance monitoring")
    }
    
    // MARK: - Performance Metrics Collection
    
    private func updatePerformanceMetrics() {
        updateCPUUsage()
        updateMemoryUsage()
        updateBatteryStatus()
        updateThermalState()
        updateThrottlingState()
        
        logPerformanceMetrics()
    }
    
    private func updateCPUUsage() {
        let usage = getCurrentCPUUsage()
        cpuUsage = usage
        
        // Update CPU history for trend analysis
        cpuHistory.append(usage)
        if cpuHistory.count > maxHistorySize {
            cpuHistory.removeFirst()
        }
    }
    
    private func updateMemoryUsage() {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            memoryUsage = UInt64(taskInfo.resident_size)
        }
    }
    
    private func updateBatteryStatus() {
        // Get battery status using IOKit
        guard let powerSource = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let powerSources = IOPSCopyPowerSourcesList(powerSource)?.takeRetainedValue() as? [CFTypeRef] else {
            return
        }
        
        for powerSourceRef in powerSources {
            guard let powerSourceDict = IOPSGetPowerSourceDescription(powerSource, powerSourceRef)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            
            // Check if this is the main battery
            if let type = powerSourceDict[kIOPSTypeKey] as? String,
               type == kIOPSInternalBatteryType {
                
                // Update battery level
                if let capacity = powerSourceDict[kIOPSCurrentCapacityKey] as? Int,
                   let maxCapacity = powerSourceDict[kIOPSMaxCapacityKey] as? Int,
                   maxCapacity > 0 {
                    batteryLevel = Float(capacity) / Float(maxCapacity)
                }
                
                // Update power source status
                if let powerState = powerSourceDict[kIOPSPowerSourceStateKey] as? String {
                    isOnBattery = (powerState == kIOPSBatteryPowerValue)
                }
                
                break
            }
        }
    }
    
    private func updateThermalState() {
        thermalState = ProcessInfo.processInfo.thermalState
    }
    
    private func updateThrottlingState() {
        let previousThrottling = isThrottling
        
        // Determine if we should throttle based on multiple factors
        let cpuThrottling = cpuUsage > thresholds.cpuThrottleThreshold
        let thermalThrottling = thresholds.thermalThrottleStates.contains(thermalState)
        let batteryThrottling = isOnBattery && batteryLevel < thresholds.lowBatteryThreshold
        
        isThrottling = cpuThrottling || thermalThrottling || batteryThrottling
        
        if self.isThrottling != previousThrottling {
            Self.logger.info("Throttling state changed: \(self.isThrottling) (CPU: \(cpuThrottling), Thermal: \(thermalThrottling), Battery: \(batteryThrottling))")
        }
    }
    
    // MARK: - System CPU Usage Calculation
    
    private func getCurrentCPUUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard kerr == KERN_SUCCESS else {
            return 0.0
        }
        
        // Get system-wide CPU info
        var cpuInfo: processor_info_array_t!
        var cpuMsgCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0
        
        let result = host_processor_info(mach_host_self(),
                                       PROCESSOR_CPU_LOAD_INFO,
                                       &cpuCount,
                                       &cpuInfo,
                                       &cpuMsgCount)
        
        guard result == KERN_SUCCESS else {
            return 0.0
        }
        
        defer {
            let deallocResult = vm_deallocate(mach_task_self_, 
                                            vm_address_t(bitPattern: cpuInfo), 
                                            vm_size_t(UInt32(cpuMsgCount) * UInt32(MemoryLayout<integer_t>.size)))
            if deallocResult != KERN_SUCCESS {
                Self.logger.error("Failed to deallocate CPU info memory: \(deallocResult)")
            }
        }
        
        // Calculate CPU usage percentage
        var totalTicks: UInt32 = 0
        var totalIdleTicks: UInt32 = 0
        
        for i in 0..<Int(cpuCount) {
            let cpuLoadInfo = cpuInfo.advanced(by: i * Int(CPU_STATE_MAX)).pointee
            let userTicks = UInt32(cpuLoadInfo)
            let systemTicks = UInt32(cpuInfo.advanced(by: i * Int(CPU_STATE_MAX) + 1).pointee)
            let idleTicks = UInt32(cpuInfo.advanced(by: i * Int(CPU_STATE_MAX) + 2).pointee)
            let niceTicks = UInt32(cpuInfo.advanced(by: i * Int(CPU_STATE_MAX) + 3).pointee)
            
            let coreTotalTicks = userTicks + systemTicks + idleTicks + niceTicks
            totalTicks += coreTotalTicks
            totalIdleTicks += idleTicks
        }
        
        guard totalTicks > 0 else { 
            Self.logger.warning("Invalid CPU state: totalTicks is zero")
            return 0.0 
        }
        
        let usage = Double(totalTicks - totalIdleTicks) / Double(totalTicks) * 100.0
        return min(max(usage, 0.0), 100.0)
    }
    
    // MARK: - Performance Analysis
    
    public func getAverageCPUUsage() -> Double {
        guard !cpuHistory.isEmpty else { return 0.0 }
        return cpuHistory.reduce(0, +) / Double(cpuHistory.count)
    }
    
    public func shouldReducePerformance() -> Bool {
        return isThrottling
    }
    
    public func getRecommendedModelDowngrade() -> String? {
        guard isThrottling else { return nil }
        
        // Simple model downgrade logic
        let currentModel = WhisperNodeCore.shared.currentModel
        
        switch currentModel {
        case "large.en", "large":
            return "medium.en"
        case "medium.en", "medium":
            return "small.en"
        case "small.en", "small":
            return "tiny.en"
        default:
            return nil
        }
    }
    
    public func getBatteryOptimizedSettings() -> [String: Any] {
        var settings: [String: Any] = [:]
        
        if isOnBattery {
            settings["preferFasterModel"] = batteryLevel > 0.5
            settings["reducedMonitoringFrequency"] = batteryLevel < 0.3
            settings["enablePowerSaving"] = batteryLevel < 0.2
        }
        
        return settings
    }
    
    // MARK: - Logging
    
    private func logPerformanceMetrics() {
        let memoryMB = Double(memoryUsage) / 1024.0 / 1024.0
        
        Self.logger.debug("""
            Performance Metrics - CPU: \(String(format: "%.1f", self.cpuUsage))%, \
            Memory: \(String(format: "%.1f", memoryMB))MB, \
            Battery: \(String(format: "%.0f", self.batteryLevel * 100))% \
            (\(self.isOnBattery ? "battery" : "AC")), \
            Thermal: \(self.thermalState.rawValue), \
            Throttling: \(self.isThrottling)
            """)
    }
    
    // MARK: - Performance Regression Detection
    
    private var historicalBenchmarks: [PerformanceBenchmark] = []
    private let maxBenchmarkHistory = 50
    private let regressionThreshold = 0.15 // 15% performance degradation threshold
    
    public struct PerformanceBenchmark: Codable {
        public let testName: String
        public let value: Double
        public let unit: String
        public let timestamp: Date
        public let gitCommit: String?
        public let buildConfiguration: String
        
        public init(testName: String, value: Double, unit: String, timestamp: Date = Date(), gitCommit: String? = nil, buildConfiguration: String = "release") {
            self.testName = testName
            self.value = value
            self.unit = unit
            self.timestamp = timestamp
            self.gitCommit = gitCommit
            self.buildConfiguration = buildConfiguration
        }
    }
    
    public struct RegressionAnalysis {
        public let testName: String
        public let currentValue: Double
        public let baselineValue: Double
        public let percentageChange: Double
        public let isRegression: Bool
        public let severity: RegressionSeverity
        
        public enum RegressionSeverity {
            case none
            case minor      // 5-15% degradation
            case moderate   // 15-30% degradation
            case severe     // >30% degradation
            
            var description: String {
                switch self {
                case .none: return "No regression"
                case .minor: return "Minor regression"
                case .moderate: return "Moderate regression"
                case .severe: return "Severe regression"
                }
            }
        }
    }
    
    public func recordBenchmark(_ benchmark: PerformanceBenchmark) {
        historicalBenchmarks.append(benchmark)
        
        // Maintain history size limit
        if historicalBenchmarks.count > maxBenchmarkHistory {
            historicalBenchmarks.removeFirst()
        }
        
        // Save to disk for persistence
        saveBenchmarkHistory()
        
        Self.logger.info("Recorded benchmark: \(benchmark.testName) = \(benchmark.value) \(benchmark.unit)")
    }
    
    public func analyzeRegression(for testName: String, currentValue: Double) -> RegressionAnalysis? {
        let relevantBenchmarks = historicalBenchmarks.filter { $0.testName == testName }
        
        guard !relevantBenchmarks.isEmpty else {
            Self.logger.warning("No historical data for test: \(testName)")
            return nil
        }
        
        // Calculate baseline from recent stable measurements (last 10 results)
        let recentBenchmarks = Array(relevantBenchmarks.suffix(10))
        let baselineValue = recentBenchmarks.map { $0.value }.reduce(0, +) / Double(recentBenchmarks.count)
        
        let percentageChange = ((currentValue - baselineValue) / baselineValue) * 100.0
        let isRegression = percentageChange > (regressionThreshold * 100.0)
        
        let severity: RegressionAnalysis.RegressionSeverity
        if percentageChange <= 5.0 {
            severity = .none
        } else if percentageChange <= 15.0 {
            severity = .minor
        } else if percentageChange <= 30.0 {
            severity = .moderate
        } else {
            severity = .severe
        }
        
        let analysis = RegressionAnalysis(
            testName: testName,
            currentValue: currentValue,
            baselineValue: baselineValue,
            percentageChange: percentageChange,
            isRegression: isRegression,
            severity: severity
        )
        
        if isRegression {
            Self.logger.warning("Performance regression detected: \(testName) - \(String(format: "%.1f", percentageChange))% degradation (\(severity.description))")
        }
        
        return analysis
    }
    
    public func validatePerformanceRequirements(benchmarks: [PerformanceBenchmark]) -> [String: Bool] {
        let prdRequirements: [String: Double] = [
            "Cold Launch Time": 2.0,
            "Transcription Latency (5s)": 1.0,
            "Transcription Latency (15s)": 2.0,
            "Idle Memory Usage": 100.0,
            "Peak Memory Usage": 700.0,
            "CPU Utilization During Transcription": 150.0,
            "Average CPU During Operation": 150.0
        ]
        
        var results: [String: Bool] = [:]
        
        for (requirement, threshold) in prdRequirements {
            if let benchmark = benchmarks.first(where: { $0.testName.contains(requirement) }) {
                let passes = benchmark.value <= threshold
                results[requirement] = passes
                
                if !passes {
                    Self.logger.error("PRD requirement failed: \(requirement) = \(benchmark.value) (threshold: \(threshold))")
                }
            } else {
                results[requirement] = false
                Self.logger.warning("No benchmark data for PRD requirement: \(requirement)")
            }
        }
        
        return results
    }
    
    private func saveBenchmarkHistory() {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            Self.logger.error("Could not access documents directory")
            return
        }
        
        let benchmarkFile = documentsPath.appendingPathComponent("performance_history.json")
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            
            let data = try encoder.encode(historicalBenchmarks)
            try data.write(to: benchmarkFile)
        } catch {
            Self.logger.error("Failed to save benchmark history: \(error)")
        }
    }
    
    private func loadBenchmarkHistory() {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let benchmarkFile = documentsPath.appendingPathComponent("performance_history.json")
        
        guard FileManager.default.fileExists(atPath: benchmarkFile.path) else {
            Self.logger.info("No existing benchmark history found")
            return
        }
        
        do {
            let data = try Data(contentsOf: benchmarkFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            historicalBenchmarks = try decoder.decode([PerformanceBenchmark].self, from: data)
            Self.logger.info("Loaded \(historicalBenchmarks.count) historical benchmarks")
        } catch {
            Self.logger.error("Failed to load benchmark history: \(error)")
        }
    }
    
    // MARK: - Continuous Performance Monitoring
    
    public func enableContinuousMonitoring(for operations: [String]) {
        // TODO: Implement continuous monitoring for specific operations
        // This would track performance during actual usage and detect regressions in real-time
        Self.logger.info("Continuous monitoring enabled for operations: \(operations)")
    }
    
    public func generatePerformanceReport() -> String {
        var report = "# Performance Monitor Report\n\n"
        report += "**Generated**: \(Date())\n"
        report += "**Total Benchmarks**: \(historicalBenchmarks.count)\n\n"
        
        // Current system status
        report += "## Current System Status\n\n"
        report += "- CPU Usage: \(String(format: "%.1f", cpuUsage))%\n"
        report += "- Memory Usage: \(String(format: "%.1f", Double(memoryUsage) / 1024.0 / 1024.0))MB\n"
        report += "- Battery Level: \(String(format: "%.0f", batteryLevel * 100))%\n"
        report += "- Power Source: \(isOnBattery ? "Battery" : "AC Power")\n"
        report += "- Thermal State: \(thermalState.description)\n"
        report += "- Throttling: \(isThrottling ? "Active" : "None")\n\n"
        
        // Recent benchmark summary
        if !historicalBenchmarks.isEmpty {
            report += "## Recent Benchmarks\n\n"
            let recentBenchmarks = Array(historicalBenchmarks.suffix(10))
            
            for benchmark in recentBenchmarks {
                report += "- \(benchmark.testName): \(benchmark.value) \(benchmark.unit) (\(benchmark.timestamp))\n"
            }
        }
        
        return report
    }
    
    // MARK: - Public Performance Metrics
    
    public struct PerformanceSnapshot {
        public let cpuUsage: Double
        public let memoryUsage: UInt64
        public let batteryLevel: Float
        public let isOnBattery: Bool
        public let thermalState: ProcessInfo.ThermalState
        public let isThrottling: Bool
        public let timestamp: Date
        
        public var memoryUsageMB: Double {
            return Double(memoryUsage) / 1024.0 / 1024.0
        }
    }
    
    public func getCurrentSnapshot() -> PerformanceSnapshot {
        return PerformanceSnapshot(
            cpuUsage: cpuUsage,
            memoryUsage: memoryUsage,
            batteryLevel: batteryLevel,
            isOnBattery: isOnBattery,
            thermalState: thermalState,
            isThrottling: isThrottling,
            timestamp: Date()
        )
    }
}

// MARK: - ProcessInfo.ThermalState Extension

extension ProcessInfo.ThermalState {
    var description: String {
        switch self {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }
}