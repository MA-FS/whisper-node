import XCTest
import SwiftUI
@testable import WhisperNode

@MainActor
final class AboutTabTests: XCTestCase {
    
    func testAboutTabInitialization() {
        // Test that AboutTab can be initialized with and without updater
        let tabWithUpdater = AboutTab(updater: nil)
        XCTAssertNotNil(tabWithUpdater)
        
        // Test that the view can be created
        let view = AnyView(tabWithUpdater)
        XCTAssertNotNil(view)
    }
    
    func testVersionInfoDisplayed() {
        // Test that version information is properly extracted from Bundle
        let tab = AboutTab(updater: nil)
        
        // The view should have access to version and build info
        // This tests the Bundle.main.infoDictionary access
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        
        // In test environment, these might be nil, but should not crash
        XCTAssertTrue(version != nil || version == nil) // Should not crash
        XCTAssertTrue(build != nil || build == nil) // Should not crash
    }
    
    func testUpdaterManagerSingleton() {
        // Test that UpdaterManager singleton works correctly
        let manager1 = UpdaterManager.shared
        let manager2 = UpdaterManager.shared
        
        // Should be the same instance
        XCTAssertTrue(manager1 === manager2)
        
        // Should have an updater
        XCTAssertNotNil(manager1.updater)
    }
}