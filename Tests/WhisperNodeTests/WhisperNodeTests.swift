import XCTest
@testable import WhisperNode

final class WhisperNodeTests: XCTestCase {
    func testCoreInitialization() throws {
        let core = WhisperNodeCore.shared
        XCTAssertTrue(core.isInitialized)
    }
}