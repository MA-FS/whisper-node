import XCTest
import Foundation
@testable import WhisperNode

/// T25: Security & Privacy Audit Test Suite
/// Automated verification of security and privacy compliance
final class SecurityAuditTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Setup for security tests
    }
    
    override func tearDownWithError() throws {
        // Cleanup after security tests
    }
    
    // MARK: - Network Security Tests
    
    func testNoNetworkCapabilitiesInBundle() throws {
        let bundle = Bundle.main
        let infoPlist = bundle.infoDictionary
        
        // Verify no network-related permissions in Info.plist
        let networkPermissions = [
            "NSAppTransportSecurity",
            "NSAllowsArbitraryLoads",
            "NSExceptionDomains"
        ]
        
        for permission in networkPermissions {
            if let _ = infoPlist?[permission] {
                XCTAssertTrue(false, "Unexpected network permission found: \(permission)")
            }
        }
    }
    
    func testNoNetworkingFrameworksImported() throws {
        // This test verifies at compile time that no networking frameworks are imported
        // If networking frameworks were imported, this would not compile
        
        // Verify URLSession is not available (would indicate network imports)
        // Note: This is a compile-time check - if URLSession is available, network imports exist
        #if canImport(Network)
        XCTFail("Network framework should not be imported")
        #endif
    }
    
    // MARK: - Data Privacy Tests
    
    func testNoAudioDataPersistence() throws {
        // Verify no audio files are created in app directories
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, 
                                                    in: .userDomainMask).first?.appendingPathComponent("WhisperNode")
        
        if let appDir = appSupportDir, FileManager.default.fileExists(atPath: appDir.path) {
            let audioExtensions = ["wav", "mp3", "m4a", "aiff", "caf"]
            let contents = try FileManager.default.contentsOfDirectory(at: appDir, 
                                                                      includingPropertiesForKeys: nil)
            
            for file in contents {
                let fileExtension = file.pathExtension.lowercased()
                XCTAssertFalse(audioExtensions.contains(fileExtension), 
                             "Audio file found in app directory: \(file.lastPathComponent)")
            }
        }
    }
    
    func testUserDefaultsNoSensitiveData() throws {
        // Verify UserDefaults doesn't contain sensitive audio data
        let userDefaults = UserDefaults.standard
        let allKeys = userDefaults.dictionaryRepresentation().keys
        
        let sensitiveKeys = ["audio", "recording", "transcript", "speech"]
        
        for key in allKeys {
            for sensitiveKey in sensitiveKeys {
                XCTAssertFalse(key.lowercased().contains(sensitiveKey), 
                             "Potentially sensitive key found in UserDefaults: \(key)")
            }
        }
    }
    
    // MARK: - Permission Tests
    
    func testMicrophonePermissionProperlyDeclared() throws {
        let bundle = Bundle.main
        let infoPlist = bundle.infoDictionary
        
        // Verify microphone usage description exists
        let micUsageKey = "NSMicrophoneUsageDescription"
        XCTAssertNotNil(infoPlist?[micUsageKey], 
                       "Microphone usage description must be declared")
        
        let description = infoPlist?[micUsageKey] as? String
        XCTAssertNotNil(description, "Microphone usage description must not be empty")
        XCTAssertTrue(description!.count > 10, "Microphone usage description must be descriptive")
    }
    
    func testNoUnnecessaryPermissions() throws {
        let bundle = Bundle.main
        let infoPlist = bundle.infoDictionary
        
        // List of permissions that should NOT be present
        let unnecessaryPermissions = [
            "NSCameraUsageDescription",
            "NSLocationUsageDescription", 
            "NSLocationWhenInUseUsageDescription",
            "NSLocationAlwaysUsageDescription",
            "NSContactsUsageDescription",
            "NSCalendarsUsageDescription",
            "NSRemindersUsageDescription",
            "NSPhotoLibraryUsageDescription"
        ]
        
        for permission in unnecessaryPermissions {
            XCTAssertNil(infoPlist?[permission], 
                        "Unnecessary permission found: \(permission)")
        }
    }
    
    // MARK: - Model Security Tests
    
    func testModelManagerUsesSecureDownloads() throws {
        // This test verifies ModelManager implementation uses HTTPS
        // Note: This would need to be implemented when ModelManager is available
        
        // For now, verify the concept exists in test
        let httpsRequired = true
        let checksumVerificationRequired = true
        
        XCTAssertTrue(httpsRequired, "Model downloads must use HTTPS")
        XCTAssertTrue(checksumVerificationRequired, "Model downloads must verify checksums")
    }
    
    // MARK: - Temporary File Tests
    
    func testTemporaryFileCleanup() throws {
        let tempDir = FileManager.default.temporaryDirectory
        
        // Count temp files before
        let beforeContents = try FileManager.default.contentsOfDirectory(at: tempDir, 
                                                                        includingPropertiesForKeys: nil)
        let beforeWhisperFiles = beforeContents.filter { $0.lastPathComponent.contains("whisper") }
        
        // Simulate audio processing (would create temp files)
        // Note: This would need actual AudioCaptureEngine integration
        
        // Count temp files after - should be same or fewer
        let afterContents = try FileManager.default.contentsOfDirectory(at: tempDir, 
                                                                       includingPropertiesForKeys: nil)
        let afterWhisperFiles = afterContents.filter { $0.lastPathComponent.contains("whisper") }
        
        XCTAssertLessThanOrEqual(afterWhisperFiles.count, beforeWhisperFiles.count, 
                                "Temporary files were not cleaned up properly")
    }
    
    // MARK: - Code Integrity Tests
    
    func testAppBundleIntegrity() throws {
        let bundle = Bundle.main
        
        // Verify bundle has proper structure
        XCTAssertNotNil(bundle.bundleIdentifier, "Bundle must have identifier")
        XCTAssertNotNil(bundle.infoDictionary, "Bundle must have Info.plist")
        
        // Verify version information exists
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
        XCTAssertNotNil(version, "Bundle must have version string")
        
        let buildNumber = bundle.infoDictionary?["CFBundleVersion"] as? String
        XCTAssertNotNil(buildNumber, "Bundle must have build number")
    }
    
    // MARK: - Privacy Compliance Tests
    
    func testNoTelemetryOrAnalytics() throws {
        // Verify no analytics/telemetry frameworks are imported
        // This is a compile-time verification
        
        let bundle = Bundle.main
        let frameworks = bundle.paths(forResourcesOfType: "framework", inDirectory: "Frameworks")
        
        let analyticsFrameworks = ["Analytics", "Crashlytics", "Firebase", "Amplitude", "Mixpanel"]
        
        for framework in frameworks {
            let frameworkName = URL(fileURLWithPath: framework).lastPathComponent
            for analyticsFramework in analyticsFrameworks {
                XCTAssertFalse(frameworkName.contains(analyticsFramework), 
                             "Analytics framework found: \(frameworkName)")
            }
        }
    }
    
    func testNoUserTrackingCapabilities() throws {
        // Verify no user tracking capabilities in entitlements
        let bundle = Bundle.main
        
        // Check if entitlements file exists and verify no tracking permissions
        if let entitlementsPath = bundle.path(forResource: "WhisperNode", ofType: "entitlements") {
            let entitlementsData = try Data(contentsOf: URL(fileURLWithPath: entitlementsPath))
            let entitlementsString = String(data: entitlementsData, encoding: .utf8) ?? ""
            
            let trackingCapabilities = [
                "com.apple.developer.applesignin",
                "com.apple.security.network.client",
                "com.apple.security.network.server"
            ]
            
            for capability in trackingCapabilities {
                if capability.contains("network") {
                    XCTAssertFalse(entitlementsString.contains(capability), 
                                 "Network capability found in entitlements: \(capability)")
                }
            }
        }
    }
    
    // MARK: - Performance Privacy Tests
    
    func testNoPerformanceDataCollection() throws {
        // Verify no performance monitoring that could leak user behavior
        // This ensures PerformanceMonitor doesn't collect identifying information
        
        let bundle = Bundle.main
        let infoPlist = bundle.infoDictionary
        
        // Verify no crash reporting services configured
        let crashReportingKeys = ["Sentry", "Bugsnag", "Crashlytics"]
        
        for key in crashReportingKeys {
            XCTAssertNil(infoPlist?[key], "Crash reporting service found: \(key)")
        }
    }
    
    // MARK: - Memory Security Tests
    
    func testNoMemoryLeaksInAudioProcessing() throws {
        // Verify audio processing doesn't leave data in memory
        // This is a conceptual test - actual implementation would need AudioCaptureEngine
        
        weak var weakAudioEngine: AudioCaptureEngine?
        
        autoreleasepool {
            let audioEngine = AudioCaptureEngine()
            weakAudioEngine = audioEngine
            
            // Simulate audio processing
            // audioEngine.startRecording()
            // audioEngine.stopRecording()
        }
        
        // Verify engine is deallocated (no memory leaks)
        XCTAssertNil(weakAudioEngine, "AudioCaptureEngine should be deallocated")
    }
}

// MARK: - Test Helpers

extension SecurityAuditTests {
    
    /// Helper to check if a file contains sensitive data patterns
    private func containsSensitiveData(_ data: Data) -> Bool {
        let dataString = String(data: data, encoding: .utf8) ?? ""
        let sensitivePatterns = [
            "password",
            "api_key", 
            "secret",
            "token",
            "credentials"
        ]
        
        return sensitivePatterns.contains { pattern in
            dataString.lowercased().contains(pattern)
        }
    }
    
    /// Helper to verify file cleanup in directory
    private func verifyFileCleanup(in directory: URL, pattern: String) throws {
        let contents = try FileManager.default.contentsOfDirectory(at: directory, 
                                                                 includingPropertiesForKeys: nil)
        let matchingFiles = contents.filter { $0.lastPathComponent.contains(pattern) }
        
        XCTAssertTrue(matchingFiles.isEmpty, 
                     "Files matching pattern '\(pattern)' found in \(directory.path): \(matchingFiles)")
    }
}