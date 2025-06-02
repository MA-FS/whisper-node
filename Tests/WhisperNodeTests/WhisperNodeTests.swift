import XCTest
@testable import WhisperNode

final class WhisperNodeTests: XCTestCase {
    func testCoreInitialization() throws {
        let core = WhisperNodeCore.shared
        XCTAssertTrue(core.isInitialized)
        
        // Verify singleton behavior
        let anotherCore = WhisperNodeCore.shared
        XCTAssertTrue(core === anotherCore, "Should return the same singleton instance")
        
        // Verify core state
        XCTAssertFalse(core.isRecording, "Should not be recording initially")
    }
}