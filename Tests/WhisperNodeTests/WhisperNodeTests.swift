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
}