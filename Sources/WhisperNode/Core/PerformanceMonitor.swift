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