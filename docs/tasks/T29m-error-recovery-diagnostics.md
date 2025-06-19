# Error Recovery & Comprehensive Diagnostics System

**Date**: December 18, 2024  
**Status**: 🔄 NOT STARTED  
**Priority**: HIGH  

## Overview

Implement a comprehensive error recovery and diagnostics system to ensure the application can gracefully handle failures, recover from error states, and provide detailed diagnostic information for troubleshooting.

## Issues Addressed

### 1. **Incomplete Error Recovery**
- **Problem**: App may get stuck in broken states after component failures
- **Root Cause**: Limited systematic error recovery across the pipeline
- **Impact**: User must restart app or lose functionality after errors occur

### 2. **Insufficient Diagnostic Information**
- **Problem**: Difficult to troubleshoot issues when they occur
- **Root Cause**: Limited logging and diagnostic data collection
- **Impact**: Support requests difficult to resolve, user frustration

### 3. **Silent Failures**
- **Problem**: Components may fail without user awareness
- **Root Cause**: Inadequate error detection and user notification
- **Impact**: User thinks app is working but functionality is broken

### 4. **Poor Error User Experience**
- **Problem**: Error messages are technical and not actionable
- **Root Cause**: Developer-focused error handling without user-friendly guidance
- **Impact**: Users don't know how to resolve issues

## Technical Requirements

### 1. Comprehensive Error Recovery
- Implement automatic recovery mechanisms for common failure scenarios
- Provide manual recovery options for complex failures
- Ensure clean state restoration after errors

### 2. Advanced Diagnostics System
- Collect comprehensive diagnostic information
- Implement structured logging with appropriate levels
- Provide diagnostic export for support requests

### 3. User-Friendly Error Handling
- Convert technical errors to user-friendly messages
- Provide actionable guidance for error resolution
- Implement progressive error disclosure (simple → detailed)

### 4. System Health Monitoring
- Monitor component health and performance
- Detect degraded states before complete failure
- Provide proactive warnings and suggestions

## Implementation Plan

### Phase 1: Error Recovery Framework
1. **Recovery System Design**
   - Design error recovery architecture
   - Define recovery strategies for different error types
   - Implement recovery state management

2. **Component Recovery Mechanisms**
   - Implement recovery for hotkey system failures
   - Add audio system recovery mechanisms
   - Create transcription engine recovery procedures

### Phase 2: Diagnostics and Monitoring
1. **Diagnostic Data Collection**
   - Implement comprehensive logging system
   - Add performance and health monitoring
   - Create diagnostic data aggregation

2. **User-Friendly Error System**
   - Design user-friendly error messages
   - Implement progressive error disclosure
   - Add actionable guidance system

### Phase 3: Integration and Testing
1. **System Integration**
   - Integrate error recovery across all components
   - Implement diagnostic export functionality
   - Add system health dashboard

2. **Testing and Validation**
   - Test error recovery scenarios
   - Validate diagnostic data collection
   - Test user error experience

## Files to Create

### Error Recovery System
1. **`Sources/WhisperNode/ErrorRecovery/ErrorRecoveryManager.swift`** (New)
   - Central error recovery coordination
   - Recovery strategy implementation
   - State restoration management

2. **`Sources/WhisperNode/ErrorRecovery/ComponentRecovery.swift`** (New)
   - Component-specific recovery mechanisms
   - Recovery procedure definitions
   - Recovery validation and testing

3. **`Sources/WhisperNode/ErrorRecovery/RecoveryStrategies.swift`** (New)
   - Different recovery strategy implementations
   - Automatic vs manual recovery logic
   - Recovery success validation

### Diagnostics System
4. **`Sources/WhisperNode/Diagnostics/DiagnosticsManager.swift`** (New)
   - Diagnostic data collection and management
   - System health monitoring
   - Diagnostic export functionality

5. **`Sources/WhisperNode/Diagnostics/SystemHealthMonitor.swift`** (New)
   - Real-time system health monitoring
   - Performance metrics collection
   - Proactive issue detection

6. **`Sources/WhisperNode/Diagnostics/LoggingSystem.swift`** (New)
   - Structured logging implementation
   - Log level management
   - Log aggregation and filtering

### User Experience
7. **`Sources/WhisperNode/UI/ErrorHandling/UserErrorManager.swift`** (New)
   - User-friendly error message generation
   - Error guidance and resolution steps
   - Progressive error disclosure

8. **`Sources/WhisperNode/UI/ErrorHandling/DiagnosticsView.swift`** (New)
   - System health dashboard
   - Diagnostic information display
   - Error history and resolution tracking

## Detailed Implementation

### Error Recovery Manager
```swift
import Foundation

class ErrorRecoveryManager: ObservableObject {
    @Published var isRecovering = false
    @Published var recoveryStatus: RecoveryStatus = .idle
    
    private let componentRecovery = ComponentRecovery()
    private let diagnostics = DiagnosticsManager.shared
    
    enum RecoveryStatus {
        case idle
        case detecting
        case recovering(component: String, progress: Double)
        case completed(success: Bool)
        case failed(error: Error)
    }
    
    func handleError(_ error: AppError, component: AppComponent) async {
        logger.error("Error in \(component): \(error)")
        diagnostics.recordError(error, component: component)
        
        await MainActor.run {
            isRecovering = true
            recoveryStatus = .detecting
        }
        
        let strategy = determineRecoveryStrategy(for: error, component: component)
        
        do {
            await executeRecovery(strategy: strategy, component: component)
            await MainActor.run {
                recoveryStatus = .completed(success: true)
                isRecovering = false
            }
        } catch {
            logger.error("Recovery failed: \(error)")
            await MainActor.run {
                recoveryStatus = .failed(error: error)
                isRecovering = false
            }
            
            // Show user-friendly error guidance
            await showUserErrorGuidance(originalError: error, recoveryError: error)
        }
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
            
        default:
            return .fullSystemReset
        }
    }
    
    private func executeRecovery(strategy: RecoveryStrategy, component: AppComponent) async throws {
        await MainActor.run {
            recoveryStatus = .recovering(component: component.displayName, progress: 0.0)
        }
        
        switch strategy {
        case .requestPermissions:
            try await componentRecovery.recoverPermissions()
            
        case .resetAudioSystem:
            try await componentRecovery.resetAudioSystem()
            
        case .restartTranscriptionEngine:
            try await componentRecovery.restartTranscriptionEngine()
            
        case .retryTextInsertion:
            try await componentRecovery.retryTextInsertion()
            
        case .fullSystemReset:
            try await componentRecovery.performFullSystemReset()
        }
        
        await MainActor.run {
            recoveryStatus = .recovering(component: component.displayName, progress: 1.0)
        }
        
        // Validate recovery success
        try await validateRecovery(component: component)
    }
    
    private func validateRecovery(component: AppComponent) async throws {
        switch component {
        case .hotkeySystem:
            guard WhisperNodeCore.shared.hotkeyManager.isListening else {
                throw RecoveryError.validationFailed("Hotkey system not responding")
            }
            
        case .audioSystem:
            guard WhisperNodeCore.shared.audioEngine.isAvailable else {
                throw RecoveryError.validationFailed("Audio system not available")
            }
            
        case .whisperEngine:
            // Test transcription with sample audio
            try await testTranscriptionEngine()
            
        case .textInsertion:
            // Test text insertion capability
            try await testTextInsertion()
        }
    }
}

enum RecoveryStrategy {
    case requestPermissions
    case resetAudioSystem
    case restartTranscriptionEngine
    case retryTextInsertion
    case fullSystemReset
}

enum AppComponent {
    case hotkeySystem
    case audioSystem
    case whisperEngine
    case textInsertion
    
    var displayName: String {
        switch self {
        case .hotkeySystem: return "Hotkey System"
        case .audioSystem: return "Audio System"
        case .whisperEngine: return "Transcription Engine"
        case .textInsertion: return "Text Insertion"
        }
    }
}
```

### Diagnostics Manager
```swift
class DiagnosticsManager: ObservableObject {
    static let shared = DiagnosticsManager()
    
    @Published var systemHealth: SystemHealth = .unknown
    @Published var recentErrors: [ErrorRecord] = []
    
    private let healthMonitor = SystemHealthMonitor()
    private let logger = LoggingSystem.shared
    
    struct SystemHealth {
        let overall: HealthStatus
        let components: [ComponentHealth]
        let lastUpdated: Date
        
        static let unknown = SystemHealth(
            overall: .unknown,
            components: [],
            lastUpdated: Date()
        )
    }
    
    enum HealthStatus {
        case healthy
        case degraded
        case critical
        case unknown
        
        var color: NSColor {
            switch self {
            case .healthy: return .systemGreen
            case .degraded: return .systemYellow
            case .critical: return .systemRed
            case .unknown: return .systemGray
            }
        }
    }
    
    struct ComponentHealth {
        let component: AppComponent
        let status: HealthStatus
        let metrics: [String: Any]
        let lastCheck: Date
    }
    
    struct ErrorRecord {
        let id = UUID()
        let error: AppError
        let component: AppComponent
        let timestamp: Date
        let context: [String: Any]
        let resolved: Bool
    }
    
    func startMonitoring() {
        healthMonitor.startMonitoring { [weak self] health in
            DispatchQueue.main.async {
                self?.systemHealth = health
            }
        }
    }
    
    func recordError(_ error: AppError, component: AppComponent, context: [String: Any] = [:]) {
        let record = ErrorRecord(
            error: error,
            component: component,
            timestamp: Date(),
            context: context,
            resolved: false
        )
        
        recentErrors.insert(record, at: 0)
        
        // Keep only recent errors
        if recentErrors.count > 50 {
            recentErrors = Array(recentErrors.prefix(50))
        }
        
        logger.error("Error recorded", metadata: [
            "component": component.displayName,
            "error": error.localizedDescription,
            "context": context
        ])
    }
    
    func generateDiagnosticReport() -> DiagnosticReport {
        return DiagnosticReport(
            systemInfo: collectSystemInfo(),
            appInfo: collectAppInfo(),
            componentHealth: systemHealth.components,
            recentErrors: recentErrors,
            logs: logger.getRecentLogs(),
            timestamp: Date()
        )
    }
    
    func exportDiagnostics() -> URL? {
        let report = generateDiagnosticReport()
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            
            let data = try encoder.encode(report)
            
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("WhisperNode-Diagnostics-\(Date().timeIntervalSince1970).json")
            
            try data.write(to: url)
            return url
            
        } catch {
            logger.error("Failed to export diagnostics: \(error)")
            return nil
        }
    }
    
    private func collectSystemInfo() -> SystemInfo {
        return SystemInfo(
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: ProcessInfo.processInfo.machineArchitecture,
            memorySize: ProcessInfo.processInfo.physicalMemory,
            cpuCount: ProcessInfo.processInfo.processorCount
        )
    }
    
    private func collectAppInfo() -> AppInfo {
        return AppInfo(
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown",
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "Unknown"
        )
    }
}

struct DiagnosticReport: Codable {
    let systemInfo: SystemInfo
    let appInfo: AppInfo
    let componentHealth: [DiagnosticsManager.ComponentHealth]
    let recentErrors: [DiagnosticsManager.ErrorRecord]
    let logs: [LogEntry]
    let timestamp: Date
}

struct SystemInfo: Codable {
    let macOSVersion: String
    let architecture: String
    let memorySize: UInt64
    let cpuCount: Int
}

struct AppInfo: Codable {
    let version: String
    let buildNumber: String
    let bundleIdentifier: String
}
```

### User Error Manager
```swift
class UserErrorManager {
    static let shared = UserErrorManager()
    
    func showUserFriendlyError(_ error: AppError, component: AppComponent) {
        let userError = convertToUserError(error, component: component)
        
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = userError.title
            alert.informativeText = userError.message
            alert.alertStyle = userError.severity.alertStyle
            
            // Add action buttons
            for action in userError.actions {
                alert.addButton(withTitle: action.title)
            }
            
            let response = alert.runModal()
            
            // Handle user response
            if response.rawValue >= NSApplication.ModalResponse.alertFirstButtonReturn.rawValue {
                let actionIndex = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                if actionIndex < userError.actions.count {
                    userError.actions[actionIndex].handler()
                }
            }
        }
    }
    
    private func convertToUserError(_ error: AppError, component: AppComponent) -> UserError {
        switch (error, component) {
        case (.permissionDenied, .hotkeySystem):
            return UserError(
                title: "Accessibility Permission Required",
                message: "WhisperNode needs accessibility permission to detect global hotkeys. Would you like to open System Preferences to grant this permission?",
                severity: .warning,
                actions: [
                    UserAction(title: "Open System Preferences") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    },
                    UserAction(title: "Cancel") { }
                ]
            )
            
        case (.audioDeviceUnavailable, .audioSystem):
            return UserError(
                title: "Microphone Not Available",
                message: "WhisperNode cannot access your microphone. Please check that your microphone is connected and that WhisperNode has microphone permission.",
                severity: .error,
                actions: [
                    UserAction(title: "Check Audio Settings") {
                        // Open audio preferences
                    },
                    UserAction(title: "Retry") {
                        Task {
                            await ErrorRecoveryManager().handleError(.audioDeviceUnavailable, component: .audioSystem)
                        }
                    }
                ]
            )
            
        default:
            return UserError(
                title: "Something Went Wrong",
                message: "WhisperNode encountered an unexpected error. You can try restarting the app or contact support if the problem persists.",
                severity: .error,
                actions: [
                    UserAction(title: "Restart App") {
                        NSApplication.shared.terminate(nil)
                    },
                    UserAction(title: "Contact Support") {
                        // Open support contact
                    }
                ]
            )
        }
    }
}

struct UserError {
    let title: String
    let message: String
    let severity: Severity
    let actions: [UserAction]
    
    enum Severity {
        case info
        case warning
        case error
        
        var alertStyle: NSAlert.Style {
            switch self {
            case .info: return .informational
            case .warning: return .warning
            case .error: return .critical
            }
        }
    }
}

struct UserAction {
    let title: String
    let handler: () -> Void
}
```

## Success Criteria

### Error Recovery
- [ ] Automatic recovery for common failure scenarios
- [ ] Manual recovery options for complex failures
- [ ] Clean state restoration after all error types
- [ ] Recovery validation and success confirmation

### Diagnostics
- [ ] Comprehensive diagnostic data collection
- [ ] Structured logging with appropriate levels
- [ ] Diagnostic export functionality for support
- [ ] System health monitoring and reporting

### User Experience
- [ ] User-friendly error messages with actionable guidance
- [ ] Progressive error disclosure (simple to detailed)
- [ ] Clear recovery instructions and options
- [ ] Proactive warnings for degraded states

### System Health
- [ ] Real-time component health monitoring
- [ ] Performance metrics collection and analysis
- [ ] Proactive issue detection and warnings
- [ ] Health dashboard for system status

## Testing Plan

### Error Recovery Testing
- Test automatic recovery for all error types
- Test manual recovery procedures
- Test recovery validation mechanisms
- Test error recovery under stress conditions

### Diagnostics Testing
- Test diagnostic data collection accuracy
- Test diagnostic export functionality
- Test logging system performance
- Test health monitoring accuracy

### User Experience Testing
- Test error message clarity and usefulness
- Test recovery guidance effectiveness
- Test user action responsiveness
- Test progressive disclosure functionality

## Risk Assessment

### High Risk
- **Recovery Complexity**: Complex recovery procedures may introduce new errors
- **Performance Impact**: Comprehensive monitoring may affect app performance

### Medium Risk
- **User Confusion**: Too much diagnostic information may overwhelm users
- **Privacy Concerns**: Diagnostic data collection may raise privacy issues

### Mitigation Strategies
- Extensive testing of recovery procedures
- Performance monitoring of diagnostic systems
- Clear privacy policy for diagnostic data
- User control over diagnostic data collection

## Dependencies

### Prerequisites
- All core functionality tasks (T29b-T29j) - to understand what needs recovery
- Logging and error handling infrastructure
- UI components for error display

### Dependent Tasks
- T29k (Integration Testing) - will test error recovery scenarios
- Future support and maintenance tasks

## Notes

- This task provides the safety net for all other functionality
- Should be implemented after core functionality is working
- Consider privacy implications of diagnostic data collection
- Design for both automatic and manual recovery scenarios

## Acceptance Criteria

1. **Comprehensive Recovery**: All identified error scenarios have recovery procedures
2. **User-Friendly Errors**: All errors converted to actionable user guidance
3. **Diagnostic Capability**: Complete diagnostic information available for troubleshooting
4. **System Health**: Real-time monitoring of all critical components
5. **Recovery Validation**: All recovery procedures validated and tested
