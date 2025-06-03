import XCTest
@testable import WhisperNode

@MainActor
final class HapticManagerTests: XCTestCase {
    
    func testHapticManagerInitialization() throws {
        let hapticManager = HapticManager.shared
        
        // Verify default settings
        XCTAssertTrue(hapticManager.isEnabled)
        XCTAssertEqual(hapticManager.intensity, 0.3, accuracy: 0.01)
    }
    
    func testHapticSettingsPersistence() throws {
        let hapticManager = HapticManager.shared
        
        // Change settings
        hapticManager.isEnabled = false
        hapticManager.intensity = 0.7
        
        // Verify UserDefaults storage
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "hapticFeedbackEnabled"))
        XCTAssertEqual(UserDefaults.standard.double(forKey: "hapticIntensity"), 0.7, accuracy: 0.01)
        
        // Reset to defaults for other tests
        hapticManager.resetToDefaults()
        XCTAssertTrue(hapticManager.isEnabled)
        XCTAssertEqual(hapticManager.intensity, 0.3, accuracy: 0.01)
    }
    
    func testHapticFeedbackMethods() throws {
        let hapticManager = HapticManager.shared
        
        // These methods should not crash on devices without haptic support
        // The HapticManager gracefully handles unsupported hardware
        XCTAssertNoThrow(hapticManager.recordingStarted())
        XCTAssertNoThrow(hapticManager.recordingStopped())
        XCTAssertNoThrow(hapticManager.errorOccurred())
        XCTAssertNoThrow(hapticManager.textInserted())
        XCTAssertNoThrow(hapticManager.testHaptic())
    }
    
    func testHapticIntensityBounds() throws {
        let hapticManager = HapticManager.shared
        
        // Test bounds
        hapticManager.intensity = -0.5  // Should clamp to minimum
        XCTAssertGreaterThanOrEqual(hapticManager.intensity, 0.0)
        
        hapticManager.intensity = 1.5   // Should clamp to maximum  
        XCTAssertLessThanOrEqual(hapticManager.intensity, 1.0)
        
        // Reset to defaults
        hapticManager.resetToDefaults()
    }
    
    func testAccessibilityRespect() throws {
        // This test verifies that the HapticManager respects accessibility settings
        // The actual behavior depends on system settings and cannot be easily mocked
        // This ensures the method exists and doesn't crash
        let hapticManager = HapticManager.shared
        
        // Should handle accessibility settings gracefully
        XCTAssertNoThrow(hapticManager.recordingStarted())
    }
}