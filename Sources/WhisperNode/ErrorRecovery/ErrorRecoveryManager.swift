import Foundation
import SwiftUI
import OSLog

/// Comprehensive error recovery manager for WhisperNode
///
/// Provides intelligent error recovery, state management, and user guidance
/// for graceful failure handling across all application components.
///
/// ## Features
/// - Automatic error detection and recovery
/// - Component-specific recovery strategies
/// - Recovery progress tracking and user feedback
/// - State validation and recovery verification
/// - Integration with diagnostics system
///
/// ## Usage
/// ```swift
/// let recoveryManager = ErrorRecoveryManager.shared
/// 
/// // Handle component error with automatic recovery
/// await recoveryManager.handleError(.audioDeviceUnavailable, component: .audioSystem)
/// 
/// // Monitor recovery status
/// recoveryManager.$recoveryStatus.sink { status in
///     // Update UI based on recovery progress
/// }
/// ```
@MainActor
public class ErrorRecoveryManager: ObservableObject {
    public static let shared = ErrorRecoveryManager()
    
    private static let logger = Logger(subsystem: "com.whispernode.recovery", category: "manager")
    
    // MARK: - Published Properties
    
    @Published public var isRecovering = false
    @Published public var recoveryStatus: RecoveryStatus = .idle
    @Published public var lastRecoveryAttempt: Date?
    @Published public var recoveryHistory: [RecoveryRecord] = []
    
    // MARK: - Private Properties
    
    private let componentRecovery = ComponentRecovery()
    private let diagnostics = DiagnosticsManager.shared
    private let maxRecoveryAttempts = 3
    private let recoveryTimeout: TimeInterval = 30.0
    
    // MARK: - Types
    
    public enum RecoveryStatus: Equatable {
        case idle
        case detecting
        case recovering(component: String, progress: Double)
        case completed(success: Bool)
        case failed(error: String)
        
        public var isActive: Bool {
            switch self {
            case .detecting, .recovering:
                return true
            default:
                return false
            }
        }
        
        public var displayMessage: String {
            switch self {
            case .idle:
                return "System ready"
            case .detecting:
                return "Detecting issue..."
            case .recovering(let component, let progress):
                return "Recovering \(component)... \(Int(progress * 100))%"
            case .completed(let success):
                return success ? "Recovery successful" : "Recovery completed with issues"
            case .failed(let error):
                return "Recovery failed: \(error)"
            }
        }
    }
    
    public struct RecoveryRecord: Identifiable, Codable {
        public let id = UUID()
        public let timestamp: Date
        public let error: AppError
        public let component: AppComponent
        public let strategy: RecoveryStrategy
        public let success: Bool
        public let duration: TimeInterval
        public let attempts: Int
        
        public var displayDescription: String {
            let result = success ? "✅ Successful" : "❌ Failed"
            return "\(component.displayName): \(error.displayName) - \(result)"
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        Self.logger.info("ErrorRecoveryManager initialized")
        setupRecoveryMonitoring()
    }
    
    // MARK: - Public Interface
    
    /// Handle error with automatic recovery attempt
    /// 
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - component: The component where the error occurred
    ///   - userInitiated: Whether this recovery was user-initiated
    public func handleError(_ error: AppError, component: AppComponent, userInitiated: Bool = false) async {
        Self.logger.error("Handling error in \(component.displayName): \(error.displayName)")
        
        // Record error in diagnostics
        diagnostics.recordError(error, component: component)
        
        // Check if we should attempt recovery
        guard shouldAttemptRecovery(for: error, component: component) else {
            Self.logger.info("Skipping recovery for \(error.displayName) - not recoverable or too many attempts")
            await showUserErrorGuidance(error: error, component: component)
            return
        }
        
        // Update status
        isRecovering = true
        recoveryStatus = .detecting
        lastRecoveryAttempt = Date()
        
        let startTime = Date()
        let strategy = determineRecoveryStrategy(for: error, component: component)
        
        do {
            try await executeRecovery(strategy: strategy, component: component, error: error)
            
            let duration = Date().timeIntervalSince(startTime)
            let record = RecoveryRecord(
                timestamp: startTime,
                error: error,
                component: component,
                strategy: strategy,
                success: true,
                duration: duration,
                attempts: 1
            )
            
            recoveryHistory.insert(record, at: 0)
            recoveryStatus = .completed(success: true)
            
            Self.logger.info("Recovery successful for \(component.displayName)")
            
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            let appError = AppError.componentFailure("Recovery failed: \(error.localizedDescription)")

            let record = RecoveryRecord(
                timestamp: startTime,
                error: appError,
                component: component,
                strategy: strategy,
                success: false,
                duration: duration,
                attempts: 1
            )

            recoveryHistory.insert(record, at: 0)
            recoveryStatus = .failed(error: error.localizedDescription)

            Self.logger.error("Recovery failed for \(component.displayName): \(error)")

            // Show user guidance for failed recovery
            await showUserErrorGuidance(error: appError, component: component)
        }
        
        // Reset status after delay
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            if !recoveryStatus.isActive {
                isRecovering = false
                recoveryStatus = .idle
            }
        }
    }
    
    /// Manually trigger recovery for a specific component
    /// 
    /// - Parameter component: The component to recover
    public func recoverComponent(_ component: AppComponent) async {
        let syntheticError = AppError.componentFailure(component.displayName)
        await handleError(syntheticError, component: component, userInitiated: true)
    }
    
    /// Get recovery statistics
    /// 
    /// - Returns: Recovery statistics summary
    public func getRecoveryStatistics() -> RecoveryStatistics {
        let total = recoveryHistory.count
        let successful = recoveryHistory.filter { $0.success }.count
        let averageDuration = recoveryHistory.isEmpty ? 0 : recoveryHistory.map { $0.duration }.reduce(0, +) / Double(total)
        
        return RecoveryStatistics(
            totalAttempts: total,
            successfulRecoveries: successful,
            successRate: total > 0 ? Double(successful) / Double(total) : 0,
            averageDuration: averageDuration,
            lastRecovery: recoveryHistory.first?.timestamp
        )
    }
    
    // MARK: - Private Methods
    
    private func setupRecoveryMonitoring() {
        // Monitor system health and trigger proactive recovery
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performProactiveHealthCheck()
            }
        }
    }
    
    private func shouldAttemptRecovery(for error: AppError, component: AppComponent) -> Bool {
        // Check if error is recoverable
        guard error.isRecoverable else { return false }
        
        // Check recent recovery attempts for this component
        let recentAttempts = recoveryHistory.filter { record in
            record.component == component &&
            record.timestamp.timeIntervalSinceNow > -300 // Last 5 minutes
        }
        
        return recentAttempts.count < maxRecoveryAttempts
    }
    
    private func determineRecoveryStrategy(for error: AppError, component: AppComponent) -> RecoveryStrategy {
        switch (error, component) {
        case (.permissionDenied, .hotkeySystem):
            return .requestPermissions
        case (.audioDeviceUnavailable, .audioSystem):
            return .resetAudioSystem
        case (.transcriptionFailed, .whisperEngine):
            return .restartTranscriptionEngine
        case (.textInsertionFailed, .textInsertion):
            return .retryTextInsertion
        case (.componentFailure, _):
            return .componentReset(component)
        default:
            return .fullSystemReset
        }
    }
    
    private func executeRecovery(strategy: RecoveryStrategy, component: AppComponent, error: AppError) async throws {
        recoveryStatus = .recovering(component: component.displayName, progress: 0.0)
        
        try await withTimeout(recoveryTimeout) {
            switch strategy {
            case .requestPermissions:
                try await self.componentRecovery.recoverPermissions()
            case .resetAudioSystem:
                try await self.componentRecovery.resetAudioSystem()
            case .restartTranscriptionEngine:
                try await self.componentRecovery.restartTranscriptionEngine()
            case .retryTextInsertion:
                try await self.componentRecovery.retryTextInsertion()
            case .componentReset(let comp):
                try await self.componentRecovery.resetComponent(comp)
            case .fullSystemReset:
                try await self.componentRecovery.performFullSystemReset()
            case .userGuidedRecovery:
                // User-guided recovery requires manual intervention
                throw RecoveryError.validationFailed("User guidance required")
            case .gracefulDegradation:
                // Graceful degradation doesn't require active recovery
                break
            }
        }
        
        recoveryStatus = .recovering(component: component.displayName, progress: 1.0)
        
        // Validate recovery success
        try await validateRecovery(component: component)
    }
    
    private func validateRecovery(component: AppComponent) async throws {
        // Component-specific validation logic will be implemented in ComponentRecovery
        try await componentRecovery.validateComponent(component)
    }
    
    private func performProactiveHealthCheck() async {
        // Proactive health monitoring will be implemented
        let healthReport = await diagnostics.performHealthCheck()
        
        for issue in healthReport.criticalIssues {
            Self.logger.warning("Proactive health check detected issue: \(issue.description)")
            // Could trigger preemptive recovery here
        }
    }
    
    private func showUserErrorGuidance(error: AppError, component: AppComponent) async {
        // Integration with help system for user guidance
        let guidance = ErrorGuidanceProvider.shared.getGuidance(for: error, component: component)
        
        // This would integrate with the UI to show user-friendly guidance
        NotificationCenter.default.post(
            name: .showErrorGuidance,
            object: nil,
            userInfo: ["guidance": guidance]
        )
    }
}

// MARK: - Supporting Types

public struct RecoveryStatistics {
    public let totalAttempts: Int
    public let successfulRecoveries: Int
    public let successRate: Double
    public let averageDuration: TimeInterval
    public let lastRecovery: Date?
}

// MARK: - Timeout Helper

private func withTimeout<T>(_ timeout: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            return try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw RecoveryError.timeout
        }
        
        guard let result = try await group.next() else {
            throw RecoveryError.timeout
        }
        
        group.cancelAll()
        return result
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showErrorGuidance = Notification.Name("showErrorGuidance")
}
