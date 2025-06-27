import Foundation
import SwiftUI
import OSLog

/// Comprehensive diagnostics manager for WhisperNode
///
/// Provides system-wide diagnostic data collection, health monitoring,
/// and diagnostic report generation for troubleshooting and support.
///
/// ## Features
/// - Comprehensive diagnostic data collection
/// - System health monitoring and alerting
/// - Diagnostic report generation and export
/// - Performance metrics tracking
/// - Error pattern analysis
///
/// ## Usage
/// ```swift
/// let diagnostics = DiagnosticsManager.shared
/// 
/// // Perform health check
/// let report = await diagnostics.performHealthCheck()
/// 
/// // Export diagnostics
/// if let url = diagnostics.exportDiagnostics() {
///     // Share diagnostic report
/// }
/// ```
@MainActor
public class DiagnosticsManager: ObservableObject {
    public static let shared = DiagnosticsManager()
    
    private static let logger = Logger(subsystem: "com.whispernode.diagnostics", category: "manager")
    
    // MARK: - Published Properties
    
    @Published public var systemHealth: SystemHealth = SystemHealth()
    @Published public var isMonitoring = false
    @Published public var lastHealthCheck: Date?
    @Published public var recentErrors: [ErrorRecord] = []
    
    // MARK: - Private Properties
    
    private var healthMonitorTimer: Timer?
    private var performanceHistory: [PerformanceSnapshot] = []
    private let maxErrorHistory = 50
    private let maxPerformanceHistory = 100
    
    // MARK: - Initialization
    
    private init() {
        Self.logger.info("DiagnosticsManager initialized")
        setupInitialHealth()
    }
    
    // MARK: - Public Interface
    
    /// Start continuous system health monitoring
    /// 
    /// - Parameter interval: Monitoring interval in seconds (default: 30)
    public func startMonitoring(interval: TimeInterval = 30.0) {
        guard !isMonitoring else { return }
        
        Self.logger.info("Starting system health monitoring with \(interval)s interval")
        
        healthMonitorTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performHealthCheck()
            }
        }
        
        isMonitoring = true
    }
    
    /// Stop system health monitoring
    public func stopMonitoring() {
        healthMonitorTimer?.invalidate()
        healthMonitorTimer = nil
        isMonitoring = false
        
        Self.logger.info("Stopped system health monitoring")
    }
    
    /// Perform comprehensive health check
    /// 
    /// - Returns: Complete health check report
    public func performHealthCheck() async -> HealthCheckReport {
        Self.logger.info("Performing comprehensive health check")
        
        let startTime = Date()
        var issues: [HealthIssue] = []
        var componentStatuses: [AppComponent: ComponentHealth] = [:]
        
        // Check each component
        for component in AppComponent.allCases {
            let health = await checkComponentHealth(component)
            componentStatuses[component] = health
            
            if !health.isHealthy {
                issues.append(contentsOf: health.issues)
            }
        }
        
        // Check system resources
        let systemResourceHealth = checkSystemResources()
        if !systemResourceHealth.isHealthy {
            issues.append(contentsOf: systemResourceHealth.issues)
        }
        
        // Update system health
        systemHealth = SystemHealth(
            components: componentStatuses,
            systemResources: systemResourceHealth,
            lastUpdated: Date()
        )
        
        lastHealthCheck = Date()
        
        let report = HealthCheckReport(
            timestamp: startTime,
            duration: Date().timeIntervalSince(startTime),
            overallHealth: determineOverallHealth(from: componentStatuses),
            componentHealth: componentStatuses,
            systemResourceHealth: systemResourceHealth,
            issues: issues,
            recommendations: generateRecommendations(from: issues)
        )
        
        Self.logger.info("Health check completed - Overall health: \(report.overallHealth.description)")
        
        return report
    }
    
    /// Record an error for diagnostic tracking
    /// 
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - component: The component where the error occurred
    ///   - context: Additional context information
    public func recordError(_ error: AppError, component: AppComponent, context: [String: Any] = [:]) {
        let record = ErrorRecord(
            error: error,
            component: component,
            timestamp: Date(),
            context: context,
            resolved: false
        )
        
        recentErrors.insert(record, at: 0)
        
        // Keep only recent errors
        if recentErrors.count > maxErrorHistory {
            recentErrors = Array(recentErrors.prefix(maxErrorHistory))
        }
        
        Self.logger.error("Error recorded - Component: \(component.displayName), Error: \(error.displayName), Context: \(context)")
        
        // Update component health based on error
        updateComponentHealthForError(error, component: component)
    }
    
    /// Mark an error as resolved
    /// 
    /// - Parameter errorId: The ID of the error to mark as resolved
    public func markErrorResolved(_ errorId: UUID) {
        if let index = recentErrors.firstIndex(where: { $0.id == errorId }) {
            recentErrors[index].resolved = true
        }
    }
    
    /// Generate comprehensive diagnostic report
    /// 
    /// - Returns: Complete diagnostic report
    public func generateDiagnosticReport() -> DiagnosticReport {
        return DiagnosticReport(
            systemInfo: collectSystemInfo(),
            appInfo: collectAppInfo(),
            componentHealth: systemHealth.components,
            systemResourceHealth: systemHealth.systemResources,
            recentErrors: recentErrors,
            performanceHistory: performanceHistory,
            timestamp: Date()
        )
    }
    
    /// Export diagnostics to file
    /// 
    /// - Returns: URL of the exported diagnostic file, or nil if export failed
    public func exportDiagnostics() -> URL? {
        let report = generateDiagnosticReport()
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            
            let data = try encoder.encode(report)
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
            let timestamp = formatter.string(from: Date())
            
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("WhisperNode-Diagnostics-\(timestamp).json")
            
            try data.write(to: url)
            
            Self.logger.info("Diagnostics exported to: \(url.path)")
            return url
            
        } catch {
            Self.logger.error("Failed to export diagnostics: \(error)")
            return nil
        }
    }
    
    /// Get error patterns and statistics
    /// 
    /// - Returns: Error analysis report
    public func getErrorAnalysis() -> ErrorAnalysis {
        let errorsByComponent = Dictionary(grouping: recentErrors) { $0.component }
        let errorsByType = Dictionary(grouping: recentErrors) { $0.error }
        
        let mostProblematicComponent = errorsByComponent.max { $0.value.count < $1.value.count }?.key
        let mostCommonError = errorsByType.max { $0.value.count < $1.value.count }?.key
        
        return ErrorAnalysis(
            totalErrors: recentErrors.count,
            resolvedErrors: recentErrors.filter { $0.resolved }.count,
            errorsByComponent: errorsByComponent.mapValues { $0.count },
            errorsByType: errorsByType.mapValues { $0.count },
            mostProblematicComponent: mostProblematicComponent,
            mostCommonError: mostCommonError,
            errorTrends: calculateErrorTrends()
        )
    }
    
    // MARK: - Private Methods
    
    private func setupInitialHealth() {
        systemHealth = SystemHealth()
    }
    
    private func checkComponentHealth(_ component: AppComponent) async -> ComponentHealth {
        var issues: [HealthIssue] = []
        var isHealthy = true
        var metrics: [String: Any] = [:]
        
        switch component {
        case .hotkeySystem:
            let hotkeyManager = WhisperNodeCore.shared.hotkeyManager
            if !hotkeyManager.isCurrentlyListening {
                issues.append(HealthIssue(
                    severity: .warning,
                    component: component,
                    description: "Hotkey system not listening",
                    recommendation: "Restart hotkey monitoring"
                ))
                isHealthy = false
            }
            metrics["isListening"] = hotkeyManager.isCurrentlyListening
            
        case .audioSystem:
            let audioEngine = WhisperNodeCore.shared.audioEngine
            if !audioEngine.isCapturing {
                issues.append(HealthIssue(
                    severity: .warning,
                    component: component,
                    description: "Audio engine not capturing",
                    recommendation: "Check audio system status"
                ))
                // Note: Not capturing is not necessarily unhealthy if not in use
            }
            metrics["isCapturing"] = audioEngine.isCapturing
            metrics["captureState"] = String(describing: audioEngine.captureState)
            
        case .whisperEngine:
            let core = WhisperNodeCore.shared
            if !core.isModelLoaded {
                issues.append(HealthIssue(
                    severity: .critical,
                    component: component,
                    description: "Whisper model not loaded",
                    recommendation: "Reload transcription model"
                ))
                isHealthy = false
            }
            metrics["modelLoaded"] = core.isModelLoaded
            metrics["currentModel"] = core.currentModel
            
        case .textInsertion:
            let textEngine = TextInsertionEngine.shared
            let isAvailable = await textEngine.isAvailable
            if !isAvailable {
                issues.append(HealthIssue(
                    severity: .warning,
                    component: component,
                    description: "Text insertion not available",
                    recommendation: "Check accessibility permissions"
                ))
                isHealthy = false
            }
            metrics["isAvailable"] = isAvailable
        }
        
        return ComponentHealth(
            component: component,
            isHealthy: isHealthy,
            issues: issues,
            metrics: metrics,
            lastChecked: Date()
        )
    }
    
    private func checkSystemResources() -> ComponentHealth {
        var issues: [HealthIssue] = []
        var isHealthy = true
        var metrics: [String: Any] = [:]
        
        // Check memory usage
        let memoryInfo = getMemoryInfo()
        metrics["memoryUsage"] = memoryInfo.used
        metrics["memoryTotal"] = memoryInfo.total
        
        if Double(memoryInfo.used) / Double(memoryInfo.total) > 0.9 {
            issues.append(HealthIssue(
                severity: .warning,
                component: .audioSystem, // Generic component for system issues
                description: "High memory usage detected",
                recommendation: "Close other applications to free memory"
            ))
            isHealthy = false
        }
        
        // Check CPU usage
        let cpuUsage = getCPUUsage()
        metrics["cpuUsage"] = cpuUsage
        
        if cpuUsage > 80.0 {
            issues.append(HealthIssue(
                severity: .warning,
                component: .audioSystem,
                description: "High CPU usage detected",
                recommendation: "Reduce system load for optimal performance"
            ))
        }
        
        // Check disk space
        let diskSpace = getDiskSpace()
        metrics["diskFree"] = diskSpace.free
        metrics["diskTotal"] = diskSpace.total
        
        if diskSpace.free < 1_000_000_000 { // Less than 1GB
            issues.append(HealthIssue(
                severity: .critical,
                component: .whisperEngine,
                description: "Low disk space",
                recommendation: "Free up disk space for model storage"
            ))
            isHealthy = false
        }
        
        return ComponentHealth(
            component: .audioSystem, // Using as generic system component
            isHealthy: isHealthy,
            issues: issues,
            metrics: metrics,
            lastChecked: Date()
        )
    }
    
    private func determineOverallHealth(from componentHealth: [AppComponent: ComponentHealth]) -> OverallHealth {
        let criticalIssues = componentHealth.values.flatMap { $0.issues }.filter { $0.severity == .critical }
        let warningIssues = componentHealth.values.flatMap { $0.issues }.filter { $0.severity == .warning }
        
        if !criticalIssues.isEmpty {
            return .critical
        } else if !warningIssues.isEmpty {
            return .warning
        } else {
            return .healthy
        }
    }
    
    private func generateRecommendations(from issues: [HealthIssue]) -> [String] {
        return issues.map { $0.recommendation }
    }
    
    private func updateComponentHealthForError(_ error: AppError, component: AppComponent) {
        // Update component health based on error occurrence
        // This would integrate with the health monitoring system
    }
    
    private func calculateErrorTrends() -> [String] {
        // Analyze error patterns over time
        // This would provide insights into recurring issues
        return []
    }
    
    // MARK: - System Information Collection
    
    private func collectSystemInfo() -> SystemInfo {
        let processInfo = ProcessInfo.processInfo
        
        return SystemInfo(
            operatingSystem: processInfo.operatingSystemVersionString,
            systemVersion: processInfo.operatingSystemVersion,
            processorCount: processInfo.processorCount,
            physicalMemory: processInfo.physicalMemory,
            systemUptime: processInfo.systemUptime
        )
    }
    
    private func collectAppInfo() -> AppInfo {
        let bundle = Bundle.main
        
        return AppInfo(
            version: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
            buildNumber: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown",
            bundleIdentifier: bundle.bundleIdentifier ?? "Unknown"
        )
    }
    
    private func getMemoryInfo() -> (used: UInt64, total: UInt64) {
        // Simplified memory info - would use actual system APIs
        return (used: 1_000_000_000, total: 8_000_000_000)
    }
    
    private func getCPUUsage() -> Double {
        // Simplified CPU usage - would use actual system APIs
        return 25.0
    }
    
    private func getDiskSpace() -> (free: UInt64, total: UInt64) {
        // Simplified disk space - would use actual file system APIs
        return (free: 50_000_000_000, total: 500_000_000_000)
    }
}
