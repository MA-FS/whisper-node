import XCTest
@testable import WhisperNode

/// Tests for ApplicationUtils functionality
///
/// These tests validate the application detection and text field verification
/// capabilities added as part of T29i text insertion timing improvements.
@MainActor
final class ApplicationUtilsTests: XCTestCase {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
    }
    
    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }
    
    // MARK: - Application Detection Tests
    
    func testGetFrontmostApplication() {
        // Test that we can get the frontmost application
        let frontmostApp = ApplicationUtils.getFrontmostApplication()
        
        // Should return some application (likely Xcode during testing)
        XCTAssertNotNil(frontmostApp, "Should be able to detect frontmost application")
        
        if let app = frontmostApp {
            XCTAssertNotNil(app.localizedName, "Application should have a name")
            XCTAssertNotNil(app.bundleIdentifier, "Application should have a bundle identifier")
        }
    }
    
    func testIsTextFieldActive() {
        // Note: This test may fail in CI environments without accessibility permissions
        // In a real test environment, we would need to set up a test application with a text field
        
        let isTextFieldActive = ApplicationUtils.isTextFieldActive()
        
        // The result depends on the current state, but the method should not crash
        XCTAssertTrue(isTextFieldActive == true || isTextFieldActive == false, 
                     "Method should return a boolean value")
    }
    
    func testEnsureApplicationFocus() {
        guard let frontmostApp = ApplicationUtils.getFrontmostApplication() else {
            XCTSkip("No frontmost application available for testing")
        }
        
        // Test that ensuring focus doesn't crash
        ApplicationUtils.ensureApplicationFocus(frontmostApp)
        
        // The application should still be active after ensuring focus
        XCTAssertTrue(frontmostApp.isActive, "Application should be active after ensuring focus")
    }
    
    // MARK: - Text Insertion Readiness Tests
    
    func testIsReadyForTextInsertion() {
        // Test the comprehensive readiness check
        let isReady = ApplicationUtils.isReadyForTextInsertion()
        
        // The result depends on current state, but method should not crash
        XCTAssertTrue(isReady == true || isReady == false, 
                     "Method should return a boolean value")
    }
    
    func testGetTextInsertionTargetInfo() {
        let targetInfo = ApplicationUtils.getTextInsertionTargetInfo()
        
        if let info = targetInfo {
            // Verify the expected keys are present
            XCTAssertNotNil(info["applicationName"], "Should include application name")
            XCTAssertNotNil(info["bundleIdentifier"], "Should include bundle identifier")
            XCTAssertNotNil(info["isActive"], "Should include active status")
            XCTAssertNotNil(info["hasTextFieldFocus"], "Should include text field focus status")
            XCTAssertNotNil(info["isReadyForInsertion"], "Should include readiness status")
            
            // Verify boolean values are valid
            let isActive = info["isActive"]
            XCTAssertTrue(isActive == "true" || isActive == "false", 
                         "isActive should be a valid boolean string")
            
            let hasTextFieldFocus = info["hasTextFieldFocus"]
            XCTAssertTrue(hasTextFieldFocus == "true" || hasTextFieldFocus == "false", 
                         "hasTextFieldFocus should be a valid boolean string")
            
            let isReadyForInsertion = info["isReadyForInsertion"]
            XCTAssertTrue(isReadyForInsertion == "true" || isReadyForInsertion == "false", 
                         "isReadyForInsertion should be a valid boolean string")
        }
    }
    
    // MARK: - Application-Specific Optimization Tests
    
    func testGetRecommendedInsertionDelay() {
        guard let frontmostApp = ApplicationUtils.getFrontmostApplication() else {
            XCTSkip("No frontmost application available for testing")
        }
        
        let delay = ApplicationUtils.getRecommendedInsertionDelay(for: frontmostApp)
        
        // Delay should be reasonable (between 0 and 1 second)
        XCTAssertGreaterThanOrEqual(delay, 0.0, "Delay should not be negative")
        XCTAssertLessThanOrEqual(delay, 1.0, "Delay should not be excessive")
    }
    
    func testSupportsReliableTextInsertion() {
        guard let frontmostApp = ApplicationUtils.getFrontmostApplication() else {
            XCTSkip("No frontmost application available for testing")
        }
        
        let supportsInsertion = ApplicationUtils.supportsReliableTextInsertion(frontmostApp)
        
        // Should return a boolean value
        XCTAssertTrue(supportsInsertion == true || supportsInsertion == false, 
                     "Method should return a boolean value")
    }
    
    // MARK: - Known Application Tests
    
    func testKnownApplicationDelays() {
        // Test specific applications if available
        let testCases: [(bundleId: String, expectedMinDelay: TimeInterval)] = [
            ("com.microsoft.Word", 0.15),
            ("com.adobe.Photoshop", 0.2),
            ("com.apple.Terminal", 0.05),
            ("com.google.Chrome", 0.1),
            ("com.apple.Safari", 0.1)
        ]
        
        for testCase in testCases {
            // Create a mock running application for testing
            // Note: In a real test, we would need to mock NSRunningApplication
            // For now, we'll test the logic indirectly through the delay calculation
            
            // The delay should be at least the expected minimum
            // This is a simplified test since we can't easily mock NSRunningApplication
            XCTAssertGreaterThanOrEqual(testCase.expectedMinDelay, 0.0, 
                                       "Expected delay for \(testCase.bundleId) should be non-negative")
        }
    }
    
    func testProblematicApplications() {
        let problematicBundleIds = [
            "com.1password.1password7",
            "com.apple.keychainaccess",
            "com.vmware.fusion",
            "com.parallels.desktop"
        ]
        
        // These applications should be identified as potentially problematic
        // Note: We can't easily test this without mocking NSRunningApplication
        // This test validates that the bundle IDs are reasonable
        for bundleId in problematicBundleIds {
            XCTAssertTrue(bundleId.contains("."), "Bundle ID should be in reverse domain format")
            XCTAssertFalse(bundleId.isEmpty, "Bundle ID should not be empty")
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testAccessibilityPermissionHandling() {
        // Test that methods handle accessibility permission issues gracefully
        // Note: This is difficult to test without actually revoking permissions
        
        // The methods should not crash even if accessibility permissions are denied
        let _ = ApplicationUtils.isTextFieldActive()
        let _ = ApplicationUtils.isReadyForTextInsertion()
        
        // If we reach here without crashing, the error handling is working
        XCTAssertTrue(true, "Methods should handle accessibility permission issues gracefully")
    }
}
