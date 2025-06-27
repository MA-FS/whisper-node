import Foundation

/// Recovery strategy definitions for different error types and components
///
/// Defines the various recovery approaches available for different error scenarios,
/// with automatic vs manual recovery logic and success validation.
///
/// ## Features
/// - Comprehensive recovery strategy enumeration
/// - Strategy selection logic based on error type and component
/// - Recovery priority and fallback mechanisms
/// - Integration with component recovery systems
///
/// ## Usage
/// ```swift
/// let strategy = RecoveryStrategy.determineStrategy(for: error, component: component)
/// let priority = strategy.priority
/// let isAutomatic = strategy.isAutomaticRecovery
/// ```
public enum RecoveryStrategy: CaseIterable, Codable, Equatable, Hashable {
    case requestPermissions
    case resetAudioSystem
    case restartTranscriptionEngine
    case retryTextInsertion
    case componentReset(AppComponent)
    case fullSystemReset
    case userGuidedRecovery
    case gracefulDegradation
    
    // MARK: - Strategy Properties
    
    /// Whether this strategy can be performed automatically
    public var isAutomaticRecovery: Bool {
        switch self {
        case .requestPermissions, .resetAudioSystem, .restartTranscriptionEngine, .retryTextInsertion:
            return true
        case .componentReset, .fullSystemReset:
            return true
        case .userGuidedRecovery, .gracefulDegradation:
            return false
        }
    }
    
    /// Recovery priority (higher number = higher priority)
    public var priority: Int {
        switch self {
        case .retryTextInsertion:
            return 10
        case .restartTranscriptionEngine:
            return 9
        case .resetAudioSystem:
            return 8
        case .requestPermissions:
            return 7
        case .componentReset:
            return 6
        case .userGuidedRecovery:
            return 5
        case .gracefulDegradation:
            return 4
        case .fullSystemReset:
            return 1
        }
    }
    
    /// Estimated recovery time in seconds
    public var estimatedDuration: TimeInterval {
        switch self {
        case .retryTextInsertion:
            return 2.0
        case .restartTranscriptionEngine:
            return 5.0
        case .resetAudioSystem:
            return 3.0
        case .requestPermissions:
            return 10.0
        case .componentReset:
            return 4.0
        case .userGuidedRecovery:
            return 30.0
        case .gracefulDegradation:
            return 1.0
        case .fullSystemReset:
            return 15.0
        }
    }
    
    /// User-friendly description of the recovery action
    public var displayDescription: String {
        switch self {
        case .requestPermissions:
            return "Requesting system permissions"
        case .resetAudioSystem:
            return "Resetting audio system"
        case .restartTranscriptionEngine:
            return "Restarting transcription engine"
        case .retryTextInsertion:
            return "Retrying text insertion"
        case .componentReset(let component):
            return "Resetting \(component.displayName)"
        case .fullSystemReset:
            return "Performing full system reset"
        case .userGuidedRecovery:
            return "Guided recovery assistance"
        case .gracefulDegradation:
            return "Enabling fallback mode"
        }
    }
    
    /// Whether this strategy requires user interaction
    public var requiresUserInteraction: Bool {
        switch self {
        case .requestPermissions, .userGuidedRecovery:
            return true
        case .resetAudioSystem, .restartTranscriptionEngine, .retryTextInsertion, .componentReset, .fullSystemReset, .gracefulDegradation:
            return false
        }
    }
    
    // MARK: - Strategy Selection
    
    /// Determine the best recovery strategy for a given error and component
    /// 
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - component: The component where the error occurred
    ///   - previousAttempts: Number of previous recovery attempts
    /// - Returns: The recommended recovery strategy
    public static func determineStrategy(
        for error: AppError,
        component: AppComponent,
        previousAttempts: Int = 0
    ) -> RecoveryStrategy {
        
        // If we've had multiple failures, escalate to more comprehensive recovery
        if previousAttempts >= 2 {
            return .fullSystemReset
        }
        
        if previousAttempts >= 1 {
            return .componentReset(component)
        }
        
        // Primary strategy based on error type and component
        switch (error, component) {
        case (.permissionDenied, _):
            return .requestPermissions
            
        case (.audioDeviceUnavailable, .audioSystem),
             (.audioCaptureFailure, .audioSystem):
            return .resetAudioSystem
            
        case (.transcriptionFailed, .whisperEngine),
             (.modelLoadFailed, .whisperEngine):
            return .restartTranscriptionEngine
            
        case (.textInsertionFailed, .textInsertion):
            return .retryTextInsertion
            
        case (.hotkeyConflict, .hotkeySystem),
             (.hotkeySystemError, .hotkeySystem):
            return .componentReset(.hotkeySystem)

        case (.systemResourcesExhausted, _):
            return .gracefulDegradation
            
        default:
            return .userGuidedRecovery
        }
    }
    
    /// Get fallback strategies if the primary strategy fails
    /// 
    /// - Returns: Array of fallback strategies in order of preference
    public func getFallbackStrategies() -> [RecoveryStrategy] {
        switch self {
        case .retryTextInsertion:
            return [.componentReset(.textInsertion), .userGuidedRecovery]
            
        case .restartTranscriptionEngine:
            return [.componentReset(.whisperEngine), .gracefulDegradation]
            
        case .resetAudioSystem:
            return [.componentReset(.audioSystem), .userGuidedRecovery]
            
        case .requestPermissions:
            return [.userGuidedRecovery]
            
        case .componentReset:
            return [.fullSystemReset, .userGuidedRecovery]
            
        case .userGuidedRecovery:
            return [.gracefulDegradation]
            
        case .gracefulDegradation:
            return [.userGuidedRecovery]
            
        case .fullSystemReset:
            return [.userGuidedRecovery, .gracefulDegradation]
        }
    }
    
    /// Check if this strategy is applicable for the given error and component
    /// 
    /// - Parameters:
    ///   - error: The error to check against
    ///   - component: The component to check against
    /// - Returns: True if the strategy is applicable
    public func isApplicable(for error: AppError, component: AppComponent) -> Bool {
        switch self {
        case .requestPermissions:
            return error == .permissionDenied
            
        case .resetAudioSystem:
            switch error {
            case .audioDeviceUnavailable, .audioCaptureFailure:
                return component == .audioSystem
            default:
                return false
            }

        case .restartTranscriptionEngine:
            switch error {
            case .transcriptionFailed, .modelLoadFailed:
                return component == .whisperEngine
            default:
                return false
            }
            
        case .retryTextInsertion:
            return component == .textInsertion && error == .textInsertionFailed
            
        case .componentReset(let targetComponent):
            return component == targetComponent
            
        case .fullSystemReset, .userGuidedRecovery, .gracefulDegradation:
            return true // These are always applicable as fallbacks
        }
    }
}

// MARK: - Recovery Strategy Manager

/// Manages recovery strategy selection and execution coordination
public class RecoveryStrategyManager {
    public static let shared = RecoveryStrategyManager()
    
    private var strategyHistory: [StrategyRecord] = []
    private let maxHistorySize = 100
    
    private init() {}
    
    /// Record a strategy execution for learning and optimization
    /// 
    /// - Parameters:
    ///   - strategy: The strategy that was executed
    ///   - error: The error it was applied to
    ///   - component: The component it was applied to
    ///   - success: Whether the strategy was successful
    ///   - duration: How long the strategy took to execute
    public func recordStrategyExecution(
        strategy: RecoveryStrategy,
        error: AppError,
        component: AppComponent,
        success: Bool,
        duration: TimeInterval
    ) {
        let record = StrategyRecord(
            strategy: strategy,
            error: error,
            component: component,
            success: success,
            duration: duration,
            timestamp: Date()
        )
        
        strategyHistory.insert(record, at: 0)
        
        // Keep history size manageable
        if strategyHistory.count > maxHistorySize {
            strategyHistory = Array(strategyHistory.prefix(maxHistorySize))
        }
    }
    
    /// Get the success rate for a specific strategy
    /// 
    /// - Parameter strategy: The strategy to analyze
    /// - Returns: Success rate between 0.0 and 1.0
    public func getSuccessRate(for strategy: RecoveryStrategy) -> Double {
        let records = strategyHistory.filter { $0.strategy == strategy }
        guard !records.isEmpty else { return 0.0 }
        
        let successCount = records.filter { $0.success }.count
        return Double(successCount) / Double(records.count)
    }
    
    /// Get recommended strategy based on historical performance
    /// 
    /// - Parameters:
    ///   - error: The error to recover from
    ///   - component: The component with the error
    /// - Returns: The recommended strategy
    public func getRecommendedStrategy(for error: AppError, component: AppComponent) -> RecoveryStrategy {
        let primaryStrategy = RecoveryStrategy.determineStrategy(for: error, component: component)
        
        // Check if we have enough data to make an informed decision
        let relevantRecords = strategyHistory.filter { record in
            record.error == error && record.component == component
        }
        
        if relevantRecords.count >= 3 {
            // Find the strategy with the best success rate
            let strategyPerformance = Dictionary(grouping: relevantRecords) { $0.strategy }
                .mapValues { records in
                    let successCount = records.filter { $0.success }.count
                    return Double(successCount) / Double(records.count)
                }
            
            if let bestStrategy = strategyPerformance.max(by: { $0.value < $1.value })?.key {
                return bestStrategy
            }
        }
        
        return primaryStrategy
    }
}

// MARK: - Supporting Types

private struct StrategyRecord {
    let strategy: RecoveryStrategy
    let error: AppError
    let component: AppComponent
    let success: Bool
    let duration: TimeInterval
    let timestamp: Date
}

// MARK: - Codable Support

extension RecoveryStrategy {
    public static var allCases: [RecoveryStrategy] {
        return [
            .requestPermissions,
            .resetAudioSystem,
            .restartTranscriptionEngine,
            .retryTextInsertion,
            .componentReset(.hotkeySystem),
            .componentReset(.audioSystem),
            .componentReset(.whisperEngine),
            .componentReset(.textInsertion),
            .componentReset(.systemResources),
            .fullSystemReset,
            .userGuidedRecovery,
            .gracefulDegradation
        ]
    }
}
