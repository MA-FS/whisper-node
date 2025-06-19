# Hotkey Settings Persistence and Validation

**Date**: December 18, 2024  
**Status**: 🔄 NOT STARTED  
**Priority**: MEDIUM  

## Overview

Ensure robust persistence and validation of hotkey settings, with proper handling of modifier-only combinations and seamless updates when hotkey preferences are changed.

## Issues Addressed

### 1. **Modifier-Only Hotkey Persistence**
- **Problem**: Modifier-only combinations may not persist correctly to UserDefaults
- **Root Cause**: `UInt16.max` sentinel value for modifier-only hotkeys may not round-trip properly
- **Impact**: User hotkey preferences lost or corrupted between app sessions

### 2. **Runtime Hotkey Updates**
- **Problem**: Changing hotkey in preferences may not take effect immediately
- **Root Cause**: `updateHotkey()` method may not properly restart listener with new configuration
- **Impact**: User must restart app for hotkey changes to take effect

### 3. **Settings Validation**
- **Problem**: Invalid or corrupted hotkey settings may cause app instability
- **Root Cause**: Insufficient validation when loading settings from UserDefaults
- **Impact**: App crashes or hotkey system fails to initialize

## Technical Requirements

### 1. Robust Persistence
- Ensure modifier-only hotkeys persist correctly using `UInt16.max` sentinel
- Validate settings round-trip correctly to/from UserDefaults
- Handle edge cases and corrupted settings gracefully

### 2. Runtime Configuration Updates
- Implement seamless hotkey updates without app restart
- Ensure proper cleanup of old configuration before applying new
- Validate new configuration before applying changes

### 3. Settings Validation
- Validate hotkey settings on load and before use
- Provide fallback to default settings for corrupted configurations
- Add comprehensive logging for settings operations

## Implementation Plan

### Phase 1: Settings Persistence Review
1. **Current Implementation Analysis**
   - Review `SettingsManager` hotkey storage implementation
   - Test modifier-only hotkey persistence scenarios
   - Document current validation and error handling

2. **Edge Case Identification**
   - Identify scenarios where settings might become corrupted
   - Test with various hotkey combinations and edge cases
   - Document failure modes and recovery requirements

### Phase 2: Enhancement Implementation
1. **Persistence Improvements**
   - Enhance modifier-only hotkey storage and retrieval
   - Add validation and error handling for settings operations
   - Implement settings migration for format changes

2. **Runtime Update System**
   - Improve `updateHotkey()` method for seamless updates
   - Add proper cleanup and validation for configuration changes
   - Implement rollback mechanism for failed updates

### Phase 3: Testing and Validation
1. **Persistence Testing**
   - Test all hotkey combinations for proper persistence
   - Test settings corruption and recovery scenarios
   - Validate settings migration and compatibility

2. **Runtime Update Testing**
   - Test hotkey changes in preferences interface
   - Verify immediate effect without app restart
   - Test error handling for invalid configurations

## Files to Modify

### Settings Management
1. **`Sources/WhisperNode/Managers/SettingsManager.swift`**
   - Enhance hotkey persistence methods
   - Add validation and error handling
   - Implement settings migration support
   - Add comprehensive logging

2. **`Sources/WhisperNode/Core/HotkeyConfiguration.swift`**
   - Add validation methods for hotkey configurations
   - Implement configuration comparison and validation
   - Add utility methods for settings operations

### Hotkey Management
3. **`Sources/WhisperNode/Core/GlobalHotkeyManager.swift`**
   - Enhance `updateHotkey()` method
   - Add configuration validation before applying changes
   - Implement proper cleanup and rollback mechanisms
   - Add settings loading validation

4. **`Sources/WhisperNode/UI/Preferences/ShortcutTab.swift`**
   - Ensure immediate hotkey updates when preferences change
   - Add validation feedback for invalid configurations
   - Implement error handling for update failures

## Detailed Implementation

### Enhanced Settings Persistence
```swift
extension SettingsManager {
    func saveHotkeyConfiguration(_ config: HotkeyConfiguration) {
        logger.info("Saving hotkey configuration: \(config)")
        
        // Store key code (UInt16.max for modifier-only)
        UserDefaults.standard.set(config.keyCode, forKey: "hotkeyKeyCode")
        
        // Store modifier flags
        UserDefaults.standard.set(config.modifierFlags.rawValue, forKey: "hotkeyModifierFlags")
        
        // Store additional metadata for validation
        UserDefaults.standard.set(config.isModifierOnly, forKey: "hotkeyIsModifierOnly")
        UserDefaults.standard.set(config.displayString, forKey: "hotkeyDisplayString")
        
        // Validate the save operation
        if let loaded = loadHotkeyConfiguration(), loaded != config {
            logger.error("Hotkey configuration save validation failed")
        }
    }
    
    func loadHotkeyConfiguration() -> HotkeyConfiguration? {
        logger.info("Loading hotkey configuration")
        
        guard UserDefaults.standard.object(forKey: "hotkeyKeyCode") != nil else {
            logger.info("No saved hotkey configuration, using default")
            return HotkeyConfiguration.default
        }
        
        let keyCode = UInt16(UserDefaults.standard.integer(forKey: "hotkeyKeyCode"))
        let modifierFlags = CGEventFlags(rawValue: UInt64(UserDefaults.standard.integer(forKey: "hotkeyModifierFlags")))
        let isModifierOnly = UserDefaults.standard.bool(forKey: "hotkeyIsModifierOnly")
        
        // Validate loaded configuration
        let config = HotkeyConfiguration(keyCode: keyCode, modifierFlags: modifierFlags)
        
        if !config.isValid {
            logger.warning("Loaded hotkey configuration is invalid, using default")
            return HotkeyConfiguration.default
        }
        
        // Cross-validate with stored metadata
        if config.isModifierOnly != isModifierOnly {
            logger.warning("Hotkey configuration metadata mismatch, using default")
            return HotkeyConfiguration.default
        }
        
        logger.info("Loaded hotkey configuration: \(config)")
        return config
    }
}
```

### Configuration Validation
```swift
extension HotkeyConfiguration {
    var isValid: Bool {
        // Validate modifier-only configuration
        if keyCode == UInt16.max {
            // Must have at least one modifier for modifier-only hotkey
            return !modifierFlags.isEmpty
        }
        
        // Validate regular key + modifier configuration
        if keyCode == 0 {
            return false // Invalid key code
        }
        
        // Check for system reserved combinations
        if isSystemReserved {
            return false
        }
        
        return true
    }
    
    var isSystemReserved: Bool {
        // Check against known system shortcuts
        let systemShortcuts: [(UInt16, CGEventFlags)] = [
            (53, .maskCommand), // Cmd+Esc (Force Quit)
            (12, .maskCommand), // Cmd+Q (Quit)
            (13, .maskCommand), // Cmd+W (Close Window)
            // Add more system shortcuts as needed
        ]
        
        return systemShortcuts.contains { $0.0 == keyCode && $0.1 == modifierFlags }
    }
    
    static let `default` = HotkeyConfiguration(
        keyCode: UInt16.max, // Modifier-only
        modifierFlags: [.maskControl, .maskAlternate] // Ctrl+Option
    )
}
```

### Runtime Update Enhancement
```swift
extension GlobalHotkeyManager {
    func updateHotkey(_ newConfig: HotkeyConfiguration) -> Bool {
        logger.info("Updating hotkey configuration to: \(newConfig)")
        
        // Validate new configuration
        guard newConfig.isValid else {
            logger.error("Invalid hotkey configuration provided")
            return false
        }
        
        // Store current configuration for rollback
        let previousConfig = currentConfiguration
        
        // Stop current listener
        let wasListening = isListening
        if wasListening {
            stopListening()
        }
        
        // Update configuration
        currentConfiguration = newConfig
        hotkeyKeyCode = newConfig.keyCode
        hotkeyModifierFlags = newConfig.modifierFlags.rawValue
        
        // Restart listener if it was running
        if wasListening {
            if !startListening() {
                logger.error("Failed to restart hotkey listener with new configuration")
                
                // Rollback to previous configuration
                currentConfiguration = previousConfig
                hotkeyKeyCode = previousConfig.keyCode
                hotkeyModifierFlags = previousConfig.modifierFlags.rawValue
                
                // Attempt to restart with previous configuration
                if !startListening() {
                    logger.error("Failed to rollback to previous hotkey configuration")
                }
                
                return false
            }
        }
        
        // Save new configuration
        settingsManager.saveHotkeyConfiguration(newConfig)
        
        logger.info("Hotkey configuration updated successfully")
        return true
    }
}
```

## Success Criteria

### Persistence Requirements
- [ ] All hotkey combinations persist correctly across app restarts
- [ ] Modifier-only hotkeys using `UInt16.max` sentinel work properly
- [ ] Corrupted settings detected and recovered with default values
- [ ] Settings validation prevents invalid configurations

### Runtime Update Requirements
- [ ] Hotkey changes in preferences take effect immediately
- [ ] No app restart required for hotkey configuration changes
- [ ] Failed updates rollback to previous working configuration
- [ ] User receives feedback for invalid or failed configurations

### Reliability Requirements
- [ ] Settings operations are atomic and consistent
- [ ] Comprehensive logging for all settings operations
- [ ] Graceful handling of UserDefaults failures
- [ ] Proper error reporting and recovery mechanisms

## Testing Plan

### Persistence Tests
- Test all supported hotkey combinations for proper save/load
- Test modifier-only hotkey persistence specifically
- Test settings corruption scenarios and recovery
- Test UserDefaults edge cases and failures

### Runtime Update Tests
- Test hotkey changes through preferences interface
- Test invalid configuration rejection
- Test rollback mechanism for failed updates
- Test concurrent settings operations

### Edge Case Tests
- Test with corrupted UserDefaults
- Test with missing or incomplete settings
- Test settings migration scenarios
- Test system resource exhaustion during settings operations

## Edge Cases to Handle

### Settings Corruption
- **Partial Settings**: Some hotkey settings missing from UserDefaults
- **Invalid Values**: Corrupted numeric values or flags
- **Type Mismatches**: Wrong data types stored in UserDefaults
- **Migration Issues**: Settings from older app versions

### Runtime Updates
- **Concurrent Changes**: Multiple preference changes in rapid succession
- **System Conflicts**: New hotkey conflicts with system shortcuts
- **Permission Issues**: Accessibility permission revoked during update
- **Resource Failures**: System resource exhaustion during listener restart

### Validation Scenarios
- **Invalid Combinations**: Impossible or reserved key combinations
- **System Changes**: macOS updates changing system shortcut behavior
- **Hardware Differences**: Different keyboard layouts or hardware
- **Accessibility Features**: System accessibility features affecting hotkeys

## Risk Assessment

### High Risk
- **Settings Corruption**: Invalid settings causing app crashes or instability
- **Update Failures**: Failed hotkey updates leaving system in broken state

### Medium Risk
- **Performance Impact**: Settings validation overhead affecting app startup
- **User Experience**: Frequent validation errors disrupting user workflow

### Mitigation Strategies
- Comprehensive validation with graceful fallbacks
- Atomic settings operations with rollback capability
- Extensive testing of edge cases and failure scenarios
- Clear user feedback for settings issues

## Dependencies

### Prerequisites
- T29b (Global Hotkey Listener Initialization) - working hotkey system
- T29e (Key Event Capture Verification) - reliable hotkey detection
- Settings management system

### Dependent Tasks
- T29i (Text Insertion Timing) - may use hotkey settings
- T29j (UX Improvements) - builds on reliable settings system
- Future preference enhancements

## Notes

- This task ensures reliability of user preferences
- Should maintain backward compatibility with existing settings
- Consider adding settings export/import functionality
- Document settings format for future maintenance

## Acceptance Criteria

1. **Reliable Persistence**: All hotkey configurations save and load correctly
2. **Immediate Updates**: Preference changes take effect without app restart
3. **Robust Validation**: Invalid configurations detected and handled gracefully
4. **Error Recovery**: Corrupted settings recovered with sensible defaults
5. **User Feedback**: Clear indication of settings status and any issues
