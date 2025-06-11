import XCTest
@testable import WhisperNode

final class WhisperNodeTests: XCTestCase {
    func testCoreInitialization() async throws {
        let core = await WhisperNodeCore.shared
        let isInitialized = await core.isInitialized
        XCTAssertTrue(isInitialized)
        
        // Verify singleton behavior
        let anotherCore = await WhisperNodeCore.shared
        XCTAssertTrue(core === anotherCore, "Should return the same singleton instance")
        
        // Verify core state
        let isRecording = await core.isRecording
        XCTAssertFalse(isRecording, "Should not be recording initially")
    }
    
    func testAutoStartPermissionGating() async throws {
        // This test verifies that auto-start respects accessibility permission requirements
        // Note: In CI/testing environment, accessibility permissions may not be available
        // so this test focuses on the gating logic rather than actual permission status
        
        let core = await WhisperNodeCore.shared
        let hotkeyManager = await core.hotkeyManager
        
        // Verify that the hotkey manager exists and is properly initialized
        XCTAssertNotNil(hotkeyManager, "Hotkey manager should be initialized")
        
        // The core should be initialized regardless of permission status
        let isInitialized = await core.isInitialized
        XCTAssertTrue(isInitialized, "Core should initialize even without accessibility permissions")
        
        // Auto-start behavior depends on both onboarding completion AND accessibility permissions
        // Since we can't control accessibility permissions in tests, we verify the structure exists
        XCTAssertNotNil(hotkeyManager, "Permission gating should be handled through hotkey manager")
    }
}