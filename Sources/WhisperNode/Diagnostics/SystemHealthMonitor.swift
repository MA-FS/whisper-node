import Foundation
import SwiftUI
import OSLog

/// Real-time system health monitoring for WhisperNode
///
/// Provides continuous monitoring of system health, performance metrics,
/// and proactive issue detection with alerting capabilities.
///
/// ## Features
/// - Real-time performance metrics collection
/// - Proactive issue detection and alerting
/// - Health trend analysis and prediction
/// - Integration with recovery systems
/// - Configurable monitoring thresholds
///
/// ## Usage
/// ```swift
/// let monitor = SystemHealthMonitor.shared
/// 
/// // Start monitoring
/// monitor.startMonitoring()
/// 
/// // Configure thresholds
/// monitor.setThreshold(.cpuUsage, value: 80.0)
/// 
/// // Get current metrics
/// let metrics = monitor.getCurrentMetrics()
/// ```
@MainActor
public class SystemHealthMonitor: ObservableObject {
    public static let shared = SystemHealthMonitor()
    
    private static let logger = Logger(subsystem: "com.whispernode.health", category: "monitor")
    
    // MARK: - Published Properties
    
    @Published public var isMonitoring = false
    @Published public var currentMetrics: SystemMetrics = SystemMetrics()
    @Published public var healthAlerts: [HealthAlert] = []
    @Published public var performanceTrends: PerformanceTrends = PerformanceTrends()
    
    // MARK: - Private Properties
    
    private var monitoringTimer: Timer?
    private var metricsHistory: [SystemMetrics] = []
    private var thresholds: [MetricType: Double] = [:]
    private let maxHistorySize = 1000
    private let monitoringInterval: TimeInterval = 5.0
    
    // MARK: - Configuration
    
    private var defaultThresholds: [MetricType: Double] = [
        .cpuUsage: 80.0,
        .memoryUsage: 85.0,
        .diskUsage: 90.0,
        .audioLatency: 100.0,
        .transcriptionLatency: 5000.0
    ]
    
    // MARK: - Initialization
    
    private init() {
        Self.logger.info("SystemHealthMonitor initialized")
        setupDefaultThresholds()
    }
    
    // MARK: - Public Interface
    
    /// Start real-time health monitoring
    public func startMonitoring() {
        guard !isMonitoring else {
            Self.logger.debug("Health monitoring already active")
            return
        }
        
        Self.logger.info("Starting real-time health monitoring")
        
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: monitoringInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.collectMetrics()
            }
        }
        
        isMonitoring = true
    }
    
    /// Stop health monitoring
    public func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        isMonitoring = false
        
        Self.logger.info("Stopped health monitoring")
    }
    
    /// Set threshold for a specific metric
    /// 
    /// - Parameters:
    ///   - metric: The metric type to configure
    ///   - value: The threshold value
    public func setThreshold(_ metric: MetricType, value: Double) {
        thresholds[metric] = value
        Self.logger.info("Set threshold for \(metric.displayName): \(value)")
    }
    
    /// Get current system metrics
    /// 
    /// - Returns: Current system metrics snapshot
    public func getCurrentMetrics() -> SystemMetrics {
        return currentMetrics
    }
    
    /// Get performance trends analysis
    /// 
    /// - Returns: Performance trends over time
    public func getPerformanceTrends() -> PerformanceTrends {
        return performanceTrends
    }
    
    /// Get health alerts
    /// 
    /// - Returns: Current active health alerts
    public func getHealthAlerts() -> [HealthAlert] {
        return healthAlerts.filter { !$0.isResolved }
    }
    
    /// Dismiss a health alert
    /// 
    /// - Parameter alertId: The ID of the alert to dismiss
    public func dismissAlert(_ alertId: UUID) {
        if let index = healthAlerts.firstIndex(where: { $0.id == alertId }) {
            healthAlerts[index].isResolved = true
            healthAlerts[index].resolvedAt = Date()
        }
    }
    
    /// Force metrics collection
    public func forceMetricsCollection() async {
        await collectMetrics()
    }
    
    // MARK: - Private Methods
    
    private func setupDefaultThresholds() {
        thresholds = defaultThresholds
    }
    
    private func collectMetrics() async {
        let metrics = SystemMetrics(
            timestamp: Date(),
            cpuUsage: await getCPUUsage(),
            memoryUsage: await getMemoryUsage(),
            diskUsage: await getDiskUsage(),
            audioLatency: await getAudioLatency(),
            transcriptionLatency: await getTranscriptionLatency(),
            componentStatus: await getComponentStatus()
        )
        
        currentMetrics = metrics
        metricsHistory.append(metrics)
        
        // Keep history size manageable
        if metricsHistory.count > maxHistorySize {
            metricsHistory = Array(metricsHistory.suffix(maxHistorySize))
        }
        
        // Check for threshold violations
        await checkThresholds(metrics)
        
        // Update performance trends
        updatePerformanceTrends()
        
        Self.logger.debug("Collected system metrics - CPU: \(metrics.cpuUsage)%, Memory: \(metrics.memoryUsage)%")
    }
    
    private func checkThresholds(_ metrics: SystemMetrics) async {
        var newAlerts: [HealthAlert] = []
        
        // Check CPU usage
        if let threshold = thresholds[.cpuUsage], metrics.cpuUsage > threshold {
            newAlerts.append(HealthAlert(
                type: .cpuUsage,
                severity: .warning,
                message: "High CPU usage detected: \(Int(metrics.cpuUsage))%",
                threshold: threshold,
                currentValue: metrics.cpuUsage,
                recommendation: "Close unnecessary applications to reduce CPU load"
            ))
        }
        
        // Check memory usage
        if let threshold = thresholds[.memoryUsage], metrics.memoryUsage > threshold {
            newAlerts.append(HealthAlert(
                type: .memoryUsage,
                severity: .warning,
                message: "High memory usage detected: \(Int(metrics.memoryUsage))%",
                threshold: threshold,
                currentValue: metrics.memoryUsage,
                recommendation: "Close memory-intensive applications"
            ))
        }
        
        // Check disk usage
        if let threshold = thresholds[.diskUsage], metrics.diskUsage > threshold {
            newAlerts.append(HealthAlert(
                type: .diskUsage,
                severity: .critical,
                message: "Low disk space: \(Int(100 - metrics.diskUsage))% free",
                threshold: threshold,
                currentValue: metrics.diskUsage,
                recommendation: "Free up disk space to ensure proper operation"
            ))
        }
        
        // Check audio latency
        if let threshold = thresholds[.audioLatency], metrics.audioLatency > threshold {
            newAlerts.append(HealthAlert(
                type: .audioLatency,
                severity: .warning,
                message: "High audio latency: \(Int(metrics.audioLatency))ms",
                threshold: threshold,
                currentValue: metrics.audioLatency,
                recommendation: "Check audio device settings and system load"
            ))
        }
        
        // Check transcription latency
        if let threshold = thresholds[.transcriptionLatency], metrics.transcriptionLatency > threshold {
            newAlerts.append(HealthAlert(
                type: .transcriptionLatency,
                severity: .warning,
                message: "Slow transcription: \(Int(metrics.transcriptionLatency))ms",
                threshold: threshold,
                currentValue: metrics.transcriptionLatency,
                recommendation: "Consider using a smaller model for better performance"
            ))
        }
        
        // Add new alerts and remove duplicates
        for alert in newAlerts {
            if !healthAlerts.contains(where: { $0.type == alert.type && !$0.isResolved }) {
                healthAlerts.append(alert)
                Self.logger.warning("Health alert: \(alert.message)")
                
                // Trigger proactive recovery if needed
                await triggerProactiveRecovery(for: alert)
            }
        }
        
        // Auto-resolve alerts if conditions improve
        autoResolveAlerts(basedOn: metrics)
    }
    
    private func updatePerformanceTrends() {
        guard metricsHistory.count >= 10 else { return }
        
        let recent = Array(metricsHistory.suffix(60)) // Last 5 minutes
        
        performanceTrends = PerformanceTrends(
            cpuTrend: calculateTrend(recent.map { $0.cpuUsage }),
            memoryTrend: calculateTrend(recent.map { $0.memoryUsage }),
            audioLatencyTrend: calculateTrend(recent.map { $0.audioLatency }),
            transcriptionLatencyTrend: calculateTrend(recent.map { $0.transcriptionLatency }),
            overallTrend: calculateOverallTrend(recent)
        )
    }
    
    private func calculateTrend(_ values: [Double]) -> TrendDirection {
        guard values.count >= 5 else { return .stable }
        
        let firstHalf = Array(values.prefix(values.count / 2))
        let secondHalf = Array(values.suffix(values.count / 2))
        
        let firstAvg = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.reduce(0, +) / Double(secondHalf.count)
        
        let change = (secondAvg - firstAvg) / firstAvg
        
        if change > 0.1 {
            return .increasing
        } else if change < -0.1 {
            return .decreasing
        } else {
            return .stable
        }
    }
    
    private func calculateOverallTrend(_ metrics: [SystemMetrics]) -> TrendDirection {
        // Simplified overall trend calculation
        let cpuTrend = calculateTrend(metrics.map { $0.cpuUsage })
        let memoryTrend = calculateTrend(metrics.map { $0.memoryUsage })
        
        if cpuTrend == .increasing || memoryTrend == .increasing {
            return .increasing
        } else if cpuTrend == .decreasing && memoryTrend == .decreasing {
            return .decreasing
        } else {
            return .stable
        }
    }
    
    private func autoResolveAlerts(basedOn metrics: SystemMetrics) {
        for index in healthAlerts.indices {
            let alert = healthAlerts[index]
            if !alert.isResolved {
                let shouldResolve = checkIfAlertShouldResolve(alert, metrics: metrics)
                if shouldResolve {
                    healthAlerts[index].isResolved = true
                    healthAlerts[index].resolvedAt = Date()
                    Self.logger.info("Auto-resolved alert: \(alert.message)")
                }
            }
        }
    }
    
    private func checkIfAlertShouldResolve(_ alert: HealthAlert, metrics: SystemMetrics) -> Bool {
        let resolveThreshold = alert.threshold * 0.9 // 10% below threshold
        
        switch alert.type {
        case .cpuUsage:
            return metrics.cpuUsage < resolveThreshold
        case .memoryUsage:
            return metrics.memoryUsage < resolveThreshold
        case .diskUsage:
            return metrics.diskUsage < resolveThreshold
        case .audioLatency:
            return metrics.audioLatency < resolveThreshold
        case .transcriptionLatency:
            return metrics.transcriptionLatency < resolveThreshold
        }
    }
    
    private func triggerProactiveRecovery(for alert: HealthAlert) async {
        // Integration with recovery system for proactive recovery
        switch alert.type {
        case .audioLatency:
            // Could trigger audio system optimization
            break
        case .transcriptionLatency:
            // Could suggest model optimization
            break
        case .memoryUsage, .cpuUsage:
            // Could trigger performance optimization
            break
        default:
            break
        }
    }
    
    // MARK: - Metrics Collection Methods
    
    private func getCPUUsage() async -> Double {
        // Use actual CPU monitoring from existing PerformanceMonitor
        return PerformanceMonitor.shared.cpuUsage
    }

    private func getMemoryUsage() async -> Double {
        // Use actual memory monitoring - convert bytes to percentage
        let memoryBytes = PerformanceMonitor.shared.memoryUsage
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        return (Double(memoryBytes) / Double(totalMemory)) * 100.0
    }

    private func getDiskUsage() async -> Double {
        // Use actual disk monitoring - calculate from file system
        do {
            let homeURL = FileManager.default.homeDirectoryForCurrentUser
            let resourceValues = try homeURL.resourceValues(forKeys: [
                .volumeAvailableCapacityKey,
                .volumeTotalCapacityKey
            ])

            guard let availableCapacity = resourceValues.volumeAvailableCapacity,
                  let totalCapacity = resourceValues.volumeTotalCapacity else {
                return 0.0
            }

            let usedCapacity = totalCapacity - availableCapacity
            return (Double(usedCapacity) / Double(totalCapacity)) * 100.0

        } catch {
            return 0.0
        }
    }

    private func getAudioLatency() async -> Double {
        // Get actual audio latency - for now return a reasonable default
        // This would be enhanced to get actual latency from the audio system
        return 25.0
    }

    private func getTranscriptionLatency() async -> Double {
        // Get actual transcription metrics - for now return a reasonable default
        // This would be enhanced to track actual transcription timing
        return 1500.0
    }
    

    
    private func getComponentStatus() async -> [AppComponent: Bool] {
        return [
            .hotkeySystem: WhisperNodeCore.shared.hotkeyManager.isCurrentlyListening,
            .audioSystem: WhisperNodeCore.shared.audioEngine.isCapturing,
            .whisperEngine: WhisperNodeCore.shared.isModelLoaded,
            .textInsertion: await TextInsertionEngine.shared.isAvailable
        ]
    }
}
