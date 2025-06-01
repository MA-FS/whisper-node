import XCTest
@testable import WhisperNode

final class WhisperNodeTests: XCTestCase {
    func testCoreInitialization() throws {
        XCTAssertNoThrow(WhisperNodeCore.initialize())
    }
}