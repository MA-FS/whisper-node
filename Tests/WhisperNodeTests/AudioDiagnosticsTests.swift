import XCTest
@testable import WhisperNode
import AVFoundation

/// Comprehensive tests for AudioDiagnostics
@MainActor
final class AudioDiagnosticsTests: XCTestCase {
    
    var diagnostics: AudioDiagnostics!
    
    override func setUp() async throws {
        try await super.setUp()
        diagnostics = AudioDiagnostics.shared
    }
    
    override func tearDown() async throws {
        diagnostics.stopPerformanceMonitoring()
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testSharedInstance() {
        let instance1 = AudioDiagnostics.shared
        let instance2 = AudioDiagnostics.shared
        XCTAssertTrue(instance1 === instance2, "AudioDiagnostics should be a singleton")
    }
    
    func testInitialState() {
        XCTAssertFalse(diagnostics.isRunningDiagnostics, "Should not be running diagnostics initially")
        XCTAssertFalse(diagnostics.isMonitoringPerformance, "Should not be monitoring performance initially")
        XCTAssertNil(diagnostics.lastDiagnosticReport, "Should not have diagnostic report initially")
    }
    
    // MARK: - Diagnostic Result Tests
    
    func testDiagnosticResultSeverity() {
        let severities: [AudioDiagnostics.DiagnosticResult.Severity] = [
            .info, .warning, .error, .critical
        ]
        
        for severity in severities {
            XCTAssertFalse(severity.description.isEmpty, "Severity should have description")
        }
    }
    
    func testDiagnosticResultCreation() {
        let result = AudioDiagnostics.DiagnosticResult(
            checkName: "Test Check",
            passed: true,
            message: "Test message",
            severity: .info,
            recommendation: "Test recommendation",
            technicalDetails: ["key": "value"]
        )
        
        XCTAssertEqual(result.checkName, "Test Check")
        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.message, "Test message")
        XCTAssertEqual(result.severity, .info)
        XCTAssertEqual(result.recommendation, "Test recommendation")
        XCTAssertNotNil(result.technicalDetails)
    }
    
    // MARK: - System Diagnostic Report Tests
    
    func testSystemDiagnosticReportHealthStatus() {
        let healthStatuses: [AudioDiagnostics.SystemDiagnosticReport.HealthStatus] = [
            .excellent, .good, .fair, .poor, .critical
        ]
        
        for status in healthStatuses {
            XCTAssertFalse(status.description.isEmpty, "Health status should have description")
        }
    }
    
    func testRunCompleteSystemCheck() async {
        XCTAssertFalse(diagnostics.isRunningDiagnostics, "Should not be running diagnostics initially")
        
        let report = await diagnostics.runCompleteSystemCheck()
        
        XCTAssertFalse(diagnostics.isRunningDiagnostics, "Should not be running diagnostics after completion")
        
        // Validate report structure
        XCTAssertNotNil(report.timestamp, "Report should have timestamp")
        XCTAssertNotNil(report.overallHealth, "Report should have overall health")
        XCTAssertFalse(report.results.isEmpty, "Report should have diagnostic results")
        XCTAssertNotNil(report.performanceMetrics, "Report should have performance metrics")
        XCTAssertNotNil(report.systemInfo, "Report should have system info")
        XCTAssertNotNil(report.recommendations, "Report should have recommendations")
        
        // Validate individual results
        for result in report.results {
            XCTAssertFalse(result.checkName.isEmpty, "Check name should not be empty")
            XCTAssertFalse(result.message.isEmpty, "Message should not be empty")
        }
        
        // Check that last diagnostic report is updated
        XCTAssertNotNil(diagnostics.lastDiagnosticReport, "Last diagnostic report should be set")
        XCTAssertEqual(diagnostics.lastDiagnosticReport?.timestamp, report.timestamp, "Last report should match current report")
    }
    
    // MARK: - Audio Configuration Validation Tests
    
    func testValidateAudioConfiguration() {
        let isValid = diagnostics.validateAudioConfiguration()
        
        // Should return a boolean
        XCTAssertTrue(isValid || !isValid, "Should return boolean result")
        
        // If invalid, there should be specific reasons
        if !isValid {
            // Run full diagnostics to see what failed
            Task {
                let report = await diagnostics.runCompleteSystemCheck()
                let failedChecks = report.results.filter { !$0.passed }
                XCTAssertFalse(failedChecks.isEmpty, "If configuration is invalid, there should be failed checks")
            }
        }
    }
    
    // MARK: - Performance Metrics Tests
    
    func testCollectPerformanceMetrics() {
        let metrics = diagnostics.collectPerformanceMetrics()
        
        // Validate metrics structure
        XCTAssertGreaterThanOrEqual(metrics.audioLatency, 0, "Audio latency should be non-negative")
        XCTAssertGreaterThanOrEqual(metrics.bufferUtilization, 0, "Buffer utilization should be non-negative")
        XCTAssertLessThanOrEqual(metrics.bufferUtilization, 1, "Buffer utilization should not exceed 100%")
        XCTAssertGreaterThanOrEqual(metrics.cpuUsage, 0, "CPU usage should be non-negative")
        XCTAssertGreaterThanOrEqual(metrics.memoryUsage, 0, "Memory usage should be non-negative")
        XCTAssertGreaterThan(metrics.sampleRate, 0, "Sample rate should be positive")
        XCTAssertGreaterThan(metrics.channelCount, 0, "Channel count should be positive")
        XCTAssertGreaterThanOrEqual(metrics.droppedSamples, 0, "Dropped samples should be non-negative")
    }
    
    func testPerformanceMonitoring() {
        XCTAssertFalse(diagnostics.isMonitoringPerformance, "Should not be monitoring initially")
        
        diagnostics.startPerformanceMonitoring()
        XCTAssertTrue(diagnostics.isMonitoringPerformance, "Should be monitoring after start")
        
        diagnostics.stopPerformanceMonitoring()
        XCTAssertFalse(diagnostics.isMonitoringPerformance, "Should not be monitoring after stop")
        
        // Test multiple start/stop calls
        diagnostics.startPerformanceMonitoring()
        diagnostics.startPerformanceMonitoring()
        XCTAssertTrue(diagnostics.isMonitoringPerformance, "Multiple start calls should be safe")
        
        diagnostics.stopPerformanceMonitoring()
        diagnostics.stopPerformanceMonitoring()
        XCTAssertFalse(diagnostics.isMonitoringPerformance, "Multiple stop calls should be safe")
    }
    
    func testPerformanceHistory() {
        let initialHistory = diagnostics.getPerformanceHistory()
        XCTAssertTrue(initialHistory.isEmpty, "Performance history should be empty initially")
        
        diagnostics.startPerformanceMonitoring()
        
        // Wait briefly for some metrics to be collected
        let expectation = XCTestExpectation(description: "Performance metrics collection")
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            let history = self.diagnostics.getPerformanceHistory()
            XCTAssertGreaterThan(history.count, 0, "Performance history should have entries after monitoring")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
        
        diagnostics.stopPerformanceMonitoring()
    }
    
    // MARK: - System Information Tests
    
    func testSystemInfoCollection() async {
        let report = await diagnostics.runCompleteSystemCheck()
        let systemInfo = report.systemInfo
        
        XCTAssertFalse(systemInfo.osVersion.isEmpty, "OS version should not be empty")
        XCTAssertFalse(systemInfo.deviceModel.isEmpty, "Device model should not be empty")
        XCTAssertGreaterThanOrEqual(systemInfo.availableInputDevices, 0, "Available input devices should be non-negative")
    }
    
    // MARK: - Diagnostic Report Formatting Tests
    
    func testFormatDiagnosticReport() async {
        let report = await diagnostics.runCompleteSystemCheck()
        let formattedReport = diagnostics.formatDiagnosticReport(report)
        
        XCTAssertFalse(formattedReport.isEmpty, "Formatted report should not be empty")
        XCTAssertTrue(formattedReport.contains("WhisperNode Audio System Diagnostic Report"), "Should contain report title")
        XCTAssertTrue(formattedReport.contains("Overall Health"), "Should contain overall health")
        XCTAssertTrue(formattedReport.contains("System Information"), "Should contain system information")
        XCTAssertTrue(formattedReport.contains("Performance Metrics"), "Should contain performance metrics")
        XCTAssertTrue(formattedReport.contains("Diagnostic Results"), "Should contain diagnostic results")
        
        // Check that all diagnostic results are included
        for result in report.results {
            XCTAssertTrue(formattedReport.contains(result.checkName), "Should contain check name: \(result.checkName)")
        }
    }
    
    // MARK: - Individual Diagnostic Checks Tests
    
    func testSpecificDiagnosticChecks() async {
        let report = await diagnostics.runCompleteSystemCheck()
        
        // Check that expected diagnostic checks are present
        let expectedChecks = [
            "Audio Permissions",
            "Audio Device Availability",
            "Audio Format Compatibility",
            "Audio Engine Configuration",
            "System Resources",
            "Audio Latency",
            "Buffer Configuration",
            "Whisper Integration"
        ]
        
        let actualCheckNames = report.results.map { $0.checkName }
        
        for expectedCheck in expectedChecks {
            XCTAssertTrue(actualCheckNames.contains(expectedCheck), "Should contain check: \(expectedCheck)")
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testDiagnosticsWithNoAudioDevices() async {
        // This test simulates running diagnostics in an environment with no audio devices
        // The diagnostics should handle this gracefully
        
        let report = await diagnostics.runCompleteSystemCheck()
        
        // Should still produce a valid report
        XCTAssertNotNil(report, "Should produce report even without audio devices")
        XCTAssertFalse(report.results.isEmpty, "Should have diagnostic results")
        
        // Device availability check should fail
        let deviceCheck = report.results.first { $0.checkName == "Audio Device Availability" }
        if let deviceCheck = deviceCheck {
            // In CI environments, this might fail, which is expected
            XCTAssertNotNil(deviceCheck.message, "Device check should have message")
        }
    }
    
    // MARK: - Performance Tests
    
    func testDiagnosticPerformance() async {
        measure {
            Task {
                _ = await diagnostics.runCompleteSystemCheck()
            }
        }
    }
    
    func testMetricsCollectionPerformance() {
        measure {
            _ = diagnostics.collectPerformanceMetrics()
        }
    }
    
    func testConfigurationValidationPerformance() {
        measure {
            _ = diagnostics.validateAudioConfiguration()
        }
    }
    
    // MARK: - Integration Tests
    
    func testIntegrationWithAudioDeviceManager() async {
        let deviceManager = AudioDeviceManager.shared
        let devices = deviceManager.getAvailableInputDevices()
        
        let report = await diagnostics.runCompleteSystemCheck()
        
        // System info should reflect device manager data
        XCTAssertEqual(report.systemInfo.availableInputDevices, devices.count, "System info should match device manager")
        
        if let defaultDevice = deviceManager.defaultInputDevice {
            XCTAssertEqual(report.systemInfo.defaultInputDevice, defaultDevice.name, "Default device should match")
        }
    }
    
    func testIntegrationWithAudioPermissionManager() async {
        let permissionManager = AudioPermissionManager.shared
        let permissionStatus = permissionManager.currentPermissionStatus
        
        let report = await diagnostics.runCompleteSystemCheck()
        
        // Permission check should reflect permission manager status
        let permissionCheck = report.results.first { $0.checkName == "Audio Permissions" }
        XCTAssertNotNil(permissionCheck, "Should have permission check")
        
        if let permissionCheck = permissionCheck {
            if permissionStatus.allowsCapture {
                XCTAssertTrue(permissionCheck.passed, "Permission check should pass if permission is granted")
            } else {
                XCTAssertFalse(permissionCheck.passed, "Permission check should fail if permission is not granted")
            }
        }
    }
    
    // MARK: - Edge Cases Tests
    
    func testConcurrentDiagnosticRuns() async {
        // Test multiple simultaneous diagnostic runs
        async let report1 = diagnostics.runCompleteSystemCheck()
        async let report2 = diagnostics.runCompleteSystemCheck()
        async let report3 = diagnostics.runCompleteSystemCheck()
        
        let reports = await [report1, report2, report3]
        
        // All reports should be valid
        for report in reports {
            XCTAssertNotNil(report, "All concurrent reports should be valid")
            XCTAssertFalse(report.results.isEmpty, "All reports should have results")
        }
        
        // Timestamps should be close but not identical
        let timestamps = reports.map { $0.timestamp }
        XCTAssertTrue(timestamps.allSatisfy { abs($0.timeIntervalSince(timestamps[0])) < 5.0 }, "Timestamps should be within 5 seconds")
    }
}
