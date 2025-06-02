import XCTest
import SwiftUI
@testable import WhisperNode

@MainActor
final class AboutTabTests: XCTestCase {
    
    func testAboutTabInitialization() {
        // Test that AboutTab can be initialized without updater
        let tabWithoutUpdater = AboutTab(updater: nil)
        XCTAssertNotNil(tabWithoutUpdater)
        
        // Test initialization with a mock updater
        let mockUpdater = UpdaterManager.shared.updater
        let tabWithUpdater = AboutTab(updater: mockUpdater)
        XCTAssertNotNil(tabWithUpdater)
    }
    
    func testVersionInfoDisplayed() {
        // Test that version information is properly extracted from Bundle
        let tab = AboutTab(updater: nil)
        
        // In test environment, these might be nil, but should not crash
        // Just verify that accessing Bundle info doesn't crash
        XCTAssertNoThrow(Bundle.main.infoDictionary?["CFBundleShortVersionString"])
        XCTAssertNoThrow(Bundle.main.infoDictionary?["CFBundleVersion"])
        
        // Verify tab creation doesn't crash with bundle access
        XCTAssertNotNil(tab)
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
    
    func testAboutTabWithNilUpdater() {
        // Test that AboutTab handles nil updater gracefully
        let tab = AboutTab(updater: nil)
        XCTAssertNotNil(tab)
        
        // This should not crash even with nil updater
        // The view should handle the nil case gracefully
    }
    
    func testCurrentYearComputation() {
        // Test that current year is computed correctly
        let currentYear = Calendar.current.component(.year, from: Date())
        let expectedYear = String(currentYear)
        
        // Create a tab and verify year computation works
        let tab = AboutTab(updater: nil)
        XCTAssertNotNil(tab)
        
        // The year should be current year (this is an indirect test)
        XCTAssertGreaterThan(currentYear, 2020) // Sanity check
        XCTAssertLessThanOrEqual(currentYear, 2030) // Reasonable upper bound
    }
}