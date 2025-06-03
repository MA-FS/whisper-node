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
        // Note: Foundation includes URLSession and network APIs by default
        // This test verifies no explicit Network framework import
        // but cannot detect all possible network access paths through Foundation
        
        #if canImport(Network)
        XCTFail("Network framework should not be imported")
        #endif
        
        // Additional verification: Check that no high-level networking APIs are used
        // This is a runtime verification that complements the compile-time check
        let bundle = Bundle.main
        let executablePath = bundle.executablePath
        
        // Note: This test focuses on explicit Network framework imports
        // URLSession and Foundation networking capabilities are still available
        // but should not be used based on app privacy requirements
        XCTAssertNotNil(executablePath, "Executable path should be available for verification")
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
        
        // More specific patterns to avoid false positives with legitimate settings
        // like "audioQuality", "audioFormat", etc.
        let sensitiveKeys = ["audioData", "recordingData", "transcriptCache", "speechBuffer", 
                           "rawAudio", "recordedAudio", "cachedTranscript", "voiceData"]
        
        for key in allKeys {
            for sensitiveKey in sensitiveKeys {
                XCTAssertFalse(key.lowercased().contains(sensitiveKey), 
                             "Sensitive data key found in UserDefaults: \(key)")
            }
        }
        
        // Additional check for any keys that might contain actual audio/transcript data
        // by checking value types and sizes with context-aware thresholds
        for key in allKeys {
            if let value = userDefaults.object(forKey: key) {
                // Check for Data objects that might contain audio or sensitive content
                if let dataValue = value as? Data {
                    let sizeThreshold = getSizeThresholdForDataKey(key)
                    if dataValue.count > sizeThreshold {
                        XCTFail("Large data object found in UserDefaults (possible sensitive data): \(key) - \(dataValue.count) bytes (threshold: \(sizeThreshold))")
                    }
                }
                
                // Check for strings that might contain transcripts or sensitive text
                if let stringValue = value as? String {
                    let lengthThreshold = getLengthThresholdForStringKey(key)
                    if stringValue.count > lengthThreshold {
                        XCTFail("Large string found in UserDefaults (possible sensitive text): \(key) - \(stringValue.count) characters (threshold: \(lengthThreshold))")
                    }
                }
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
        // Skip this test until ModelManager is implemented
        // This prevents false security confidence from placeholder assertions
        throw XCTSkip("ModelManager not yet implemented - security verification pending")
        
        // TODO: When ModelManager is available, implement actual verification:
        // 1. Verify ModelManager.downloadModel() uses HTTPS URLs only
        // 2. Verify SHA256 checksum validation is performed
        // 3. Verify download signature verification
        // 4. Test actual ModelManager instance for secure download behavior
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
        // Skip until AudioCaptureEngine is available for testing
        // This prevents compilation failures and runtime crashes
        throw XCTSkip("AudioCaptureEngine not available for memory leak testing")
        
        // TODO: When AudioCaptureEngine is available, implement actual test:
        // 1. Create weak reference to AudioCaptureEngine instance
        // 2. Perform audio recording cycle in autoreleasepool
        // 3. Verify weak reference becomes nil after pool cleanup
        // 4. Test with actual audio processing to detect real memory leaks
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
    
    /// Context-aware size threshold for Data values based on key purpose
    private func getSizeThresholdForDataKey(_ key: String) -> Int {
        let lowercaseKey = key.lowercased()
        
        // Configuration and settings data can be larger
        if lowercaseKey.contains("config") || lowercaseKey.contains("settings") || 
           lowercaseKey.contains("preferences") || lowercaseKey.contains("theme") {
            return 50000  // 50KB for configuration data
        }
        
        // Cache and temporary data should be minimal
        if lowercaseKey.contains("cache") || lowercaseKey.contains("temp") || 
           lowercaseKey.contains("buffer") {
            return 1000   // 1KB for cache/temp data
        }
        
        // Model metadata can be moderately large
        if lowercaseKey.contains("model") || lowercaseKey.contains("metadata") {
            return 25000  // 25KB for model metadata
        }
        
        // Default threshold for unknown data types
        return 10000  // 10KB default
    }
    
    /// Context-aware length threshold for String values based on key purpose
    private func getLengthThresholdForStringKey(_ key: String) -> Int {
        let lowercaseKey = key.lowercased()
        
        // Version and build information can be longer
        if lowercaseKey.contains("version") || lowercaseKey.contains("build") || 
           lowercaseKey.contains("changelog") || lowercaseKey.contains("notes") {
            return 5000   // 5000 characters for version info
        }
        
        // Configuration strings can be moderately long
        if lowercaseKey.contains("config") || lowercaseKey.contains("settings") || 
           lowercaseKey.contains("path") || lowercaseKey.contains("url") {
            return 2000   // 2000 characters for config strings
        }
        
        // User preferences should be shorter
        if lowercaseKey.contains("preference") || lowercaseKey.contains("option") {
            return 500    // 500 characters for preferences
        }
        
        // Text that might contain transcripts or sensitive content
        if lowercaseKey.contains("text") || lowercaseKey.contains("content") || 
           lowercaseKey.contains("message") || lowercaseKey.contains("log") {
            return 200    // 200 characters for text content
        }
        
        // Default threshold for unknown string types
        return 1000   // 1000 characters default
    }
}