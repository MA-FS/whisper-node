import Foundation

// MARK: - System Health

/// Overall system health status
public enum OverallHealth: String, Codable {
    case healthy
    case warning
    case critical
    
    public var description: String {
        switch self {
        case .healthy:
            return "System is operating normally"
        case .warning:
            return "System has minor issues that should be addressed"
        case .critical:
            return "System has critical issues requiring immediate attention"
        }
    }
    
    public var color: String {
        switch self {
        case .healthy:
            return "green"
        case .warning:
            return "orange"
        case .critical:
            return "red"
        }
    }
}

/// System health container
public struct SystemHealth {
    public var components: [AppComponent: ComponentHealth] = [:]
    public var systemResources: ComponentHealth = ComponentHealth(
        component: .systemResources,
        isHealthy: true,
        issues: [],
        metrics: [:],
        lastChecked: Date()
    )
    public var lastUpdated: Date = Date()
    
    public var overallHealth: OverallHealth {
        let allIssues = components.values.flatMap { $0.issues } + systemResources.issues
        let criticalIssues = allIssues.filter { $0.severity == .critical }
        let warningIssues = allIssues.filter { $0.severity == .warning }
        
        if !criticalIssues.isEmpty {
            return .critical
        } else if !warningIssues.isEmpty {
            return .warning
        } else {
            return .healthy
        }
    }
}

/// Component health status
public struct ComponentHealth {
    public let component: AppComponent
    public var isHealthy: Bool
    public var issues: [HealthIssue]
    public var metrics: [String: Any]
    public var lastChecked: Date
    
    public init(component: AppComponent, isHealthy: Bool, issues: [HealthIssue], metrics: [String: Any], lastChecked: Date) {
        self.component = component
        self.isHealthy = isHealthy
        self.issues = issues
        self.metrics = metrics
        self.lastChecked = lastChecked
    }
}

/// Health issue description
public struct HealthIssue: Identifiable {
    public let id = UUID()
    public let severity: IssueSeverity
    public let component: AppComponent
    public let description: String
    public let recommendation: String
    public let timestamp: Date = Date()
    
    public init(severity: IssueSeverity, component: AppComponent, description: String, recommendation: String) {
        self.severity = severity
        self.component = component
        self.description = description
        self.recommendation = recommendation
    }
}

public enum IssueSeverity: String, Codable {
    case info
    case warning
    case critical
    
    public var displayName: String {
        switch self {
        case .info:
            return "Info"
        case .warning:
            return "Warning"
        case .critical:
            return "Critical"
        }
    }
    
    public var priority: Int {
        switch self {
        case .info:
            return 1
        case .warning:
            return 2
        case .critical:
            return 3
        }
    }
}

// MARK: - Health Check Reports

/// Comprehensive health check report
public struct HealthCheckReport {
    public let timestamp: Date
    public let duration: TimeInterval
    public let overallHealth: OverallHealth
    public let componentHealth: [AppComponent: ComponentHealth]
    public let systemResourceHealth: ComponentHealth
    public let issues: [HealthIssue]
    public let recommendations: [String]
    
    public var criticalIssues: [HealthIssue] {
        return issues.filter { $0.severity == .critical }
    }
    
    public var warningIssues: [HealthIssue] {
        return issues.filter { $0.severity == .warning }
    }
    
    public var infoIssues: [HealthIssue] {
        return issues.filter { $0.severity == .info }
    }
}

// MARK: - System Metrics

/// Real-time system metrics
public struct SystemMetrics: Codable {
    public let timestamp: Date
    public let cpuUsage: Double
    public let memoryUsage: Double
    public let diskUsage: Double
    public let audioLatency: Double
    public let transcriptionLatency: Double
    public let componentStatus: [String: Bool] // Simplified for Codable
    
    public init(timestamp: Date = Date(), cpuUsage: Double = 0, memoryUsage: Double = 0, diskUsage: Double = 0, audioLatency: Double = 0, transcriptionLatency: Double = 0, componentStatus: [AppComponent: Bool] = [:]) {
        self.timestamp = timestamp
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.diskUsage = diskUsage
        self.audioLatency = audioLatency
        self.transcriptionLatency = transcriptionLatency
        self.componentStatus = componentStatus.reduce(into: [String: Bool]()) { result, pair in
            result[pair.key.rawValue] = pair.value
        }
    }
}

/// Performance snapshot for historical tracking
public struct PerformanceSnapshot: Codable {
    public let timestamp: Date
    public let metrics: SystemMetrics
    public let healthScore: Double
    
    public init(timestamp: Date, metrics: SystemMetrics, healthScore: Double) {
        self.timestamp = timestamp
        self.metrics = metrics
        self.healthScore = healthScore
    }
}

// MARK: - Health Alerts

/// Health alert for threshold violations
public struct HealthAlert: Identifiable {
    public let id = UUID()
    public let type: MetricType
    public let severity: IssueSeverity
    public let message: String
    public let threshold: Double
    public let currentValue: Double
    public let recommendation: String
    public let timestamp: Date = Date()
    public var isResolved: Bool = false
    public var resolvedAt: Date?
    
    public init(type: MetricType, severity: IssueSeverity, message: String, threshold: Double, currentValue: Double, recommendation: String) {
        self.type = type
        self.severity = severity
        self.message = message
        self.threshold = threshold
        self.currentValue = currentValue
        self.recommendation = recommendation
    }
}

/// Metric types for monitoring
public enum MetricType: String, CaseIterable, Codable {
    case cpuUsage = "cpu_usage"
    case memoryUsage = "memory_usage"
    case diskUsage = "disk_usage"
    case audioLatency = "audio_latency"
    case transcriptionLatency = "transcription_latency"
    
    public var displayName: String {
        switch self {
        case .cpuUsage:
            return "CPU Usage"
        case .memoryUsage:
            return "Memory Usage"
        case .diskUsage:
            return "Disk Usage"
        case .audioLatency:
            return "Audio Latency"
        case .transcriptionLatency:
            return "Transcription Latency"
        }
    }
    
    public var unit: String {
        switch self {
        case .cpuUsage, .memoryUsage, .diskUsage:
            return "%"
        case .audioLatency, .transcriptionLatency:
            return "ms"
        }
    }
}

// MARK: - Performance Trends

/// Performance trend analysis
public struct PerformanceTrends {
    public let cpuTrend: TrendDirection
    public let memoryTrend: TrendDirection
    public let audioLatencyTrend: TrendDirection
    public let transcriptionLatencyTrend: TrendDirection
    public let overallTrend: TrendDirection
    
    public init(cpuTrend: TrendDirection = .stable, memoryTrend: TrendDirection = .stable, audioLatencyTrend: TrendDirection = .stable, transcriptionLatencyTrend: TrendDirection = .stable, overallTrend: TrendDirection = .stable) {
        self.cpuTrend = cpuTrend
        self.memoryTrend = memoryTrend
        self.audioLatencyTrend = audioLatencyTrend
        self.transcriptionLatencyTrend = transcriptionLatencyTrend
        self.overallTrend = overallTrend
    }
}

public enum TrendDirection: String, Codable {
    case increasing
    case decreasing
    case stable
    
    public var displayName: String {
        switch self {
        case .increasing:
            return "Increasing"
        case .decreasing:
            return "Decreasing"
        case .stable:
            return "Stable"
        }
    }
    
    public var symbol: String {
        switch self {
        case .increasing:
            return "↗️"
        case .decreasing:
            return "↘️"
        case .stable:
            return "➡️"
        }
    }
}

// MARK: - Diagnostic Reports

/// Comprehensive diagnostic report for export
public struct DiagnosticReport: Codable {
    public let systemInfo: SystemInfo
    public let appInfo: AppInfo
    public let componentHealth: [String: ComponentHealthCodable] // Simplified for Codable
    public let systemResourceHealth: ComponentHealthCodable
    public let recentErrors: [ErrorRecord]
    public let performanceHistory: [PerformanceSnapshot]
    public let timestamp: Date
    
    public init(systemInfo: SystemInfo, appInfo: AppInfo, componentHealth: [AppComponent: ComponentHealth], systemResourceHealth: ComponentHealth, recentErrors: [ErrorRecord], performanceHistory: [PerformanceSnapshot], timestamp: Date) {
        self.systemInfo = systemInfo
        self.appInfo = appInfo
        self.componentHealth = componentHealth.reduce(into: [String: ComponentHealthCodable]()) { result, pair in
            result[pair.key.rawValue] = ComponentHealthCodable(from: pair.value)
        }
        self.systemResourceHealth = ComponentHealthCodable(from: systemResourceHealth)
        self.recentErrors = recentErrors
        self.performanceHistory = performanceHistory
        self.timestamp = timestamp
    }
}

/// Codable version of ComponentHealth
public struct ComponentHealthCodable: Codable {
    public let component: String
    public let isHealthy: Bool
    public let issueCount: Int
    public let lastChecked: Date
    
    public init(from health: ComponentHealth) {
        self.component = health.component.rawValue
        self.isHealthy = health.isHealthy
        self.issueCount = health.issues.count
        self.lastChecked = health.lastChecked
    }
}

/// System information
public struct SystemInfo: Codable {
    public let operatingSystem: String
    public let systemVersion: OperatingSystemVersion
    public let processorCount: Int
    public let physicalMemory: UInt64
    public let systemUptime: TimeInterval
    
    public init(operatingSystem: String, systemVersion: OperatingSystemVersion, processorCount: Int, physicalMemory: UInt64, systemUptime: TimeInterval) {
        self.operatingSystem = operatingSystem
        self.systemVersion = systemVersion
        self.processorCount = processorCount
        self.physicalMemory = physicalMemory
        self.systemUptime = systemUptime
    }
}

/// Application information
public struct AppInfo: Codable {
    public let version: String
    public let buildNumber: String
    public let bundleIdentifier: String
    
    public init(version: String, buildNumber: String, bundleIdentifier: String) {
        self.version = version
        self.buildNumber = buildNumber
        self.bundleIdentifier = bundleIdentifier
    }
}

// MARK: - Codable Extensions

extension OperatingSystemVersion: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let majorVersion = try container.decode(Int.self, forKey: .majorVersion)
        let minorVersion = try container.decode(Int.self, forKey: .minorVersion)
        let patchVersion = try container.decode(Int.self, forKey: .patchVersion)
        self.init(majorVersion: majorVersion, minorVersion: minorVersion, patchVersion: patchVersion)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(majorVersion, forKey: .majorVersion)
        try container.encode(minorVersion, forKey: .minorVersion)
        try container.encode(patchVersion, forKey: .patchVersion)
    }
    
    private enum CodingKeys: String, CodingKey {
        case majorVersion, minorVersion, patchVersion
    }
}
