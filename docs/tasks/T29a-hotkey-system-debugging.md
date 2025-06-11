# T29a: Critical Hotkey System Debugging and Repair

## Status: 🛂 Blocked - Accessibility Permissions

## Overview
Critical hotkey functionality issues persist after implementing T29 fixes. The hotkey system fails to activate recording despite successful DMG builds and enhanced logging implementation. Console logs indicate accessibility permission failures and lack of hotkey debug output, suggesting the hotkey system is not properly initializing.

## Problem Statement

### Primary Issues
1. **No Hotkey Detection**: Control+Option hotkey combinations do not trigger recording
2. **Missing Debug Output**: Enhanced logging shows no hotkey-related debug messages in console
3. **Accessibility Permissions**: TCC failures for `kTCCServiceAccessibility` prevent global hotkey detection
4. **Hotkey System Not Starting**: Evidence suggests GlobalHotkeyManager.startListening() may not be called

### Symptoms Observed
- Control+Option hotkey assignment appears to work in preferences UI
- No recording orb/visual feedback when pressing configured hotkey
- Console logs show microphone permissions granted but no hotkey activity
- App launches successfully but hotkey detection completely silent

## Investigation Steps Required

### Phase 1: System Initialization Verification
1. **Verify GlobalHotkeyManager Initialization**
   - Check if `GlobalHotkeyManager.startListening()` is being called
   - Verify delegate assignment in WhisperNodeCore.initialize()
   - Confirm hotkey configuration is properly loaded from settings

2. **Accessibility Permissions Audit**
   - Check current TCC database status for accessibility permissions
   - Verify app bundle identifier matches permission grants
   - Test if CGEventTap can be created successfully
   - Debug permission request flow

3. **Enhanced Logging Verification**
   - Confirm logging statements are properly compiled into build
   - Check if log level filtering is preventing debug output
   - Verify logger subsystem and category configuration

### Phase 2: Event Tap System Analysis
1. **CGEventTap Creation**
   - Debug CGEventTapCreate() return values and error codes
   - Check if event tap is successfully enabled
   - Verify event mask includes required key events

2. **Event Callback Function**
   - Confirm event callback function is properly registered
   - Test if any keyboard events reach the callback
   - Debug modifier key detection logic

3. **Hotkey Configuration Validation**
   - Verify hotkey configuration persistence and loading
   - Check if modifier-only detection logic works correctly
   - Test with different hotkey combinations

### Phase 3: UI Integration Testing
1. **Preferences Window Integration**
   - Test hotkey recording in preferences UI
   - Verify hotkey configuration saves correctly
   - Check if preferences window affects hotkey system startup

2. **Menu Bar App Behavior**
   - Test if headless operation affects accessibility permissions
   - Verify app activation policy doesn't block global hotkeys
   - Check if dock icon visibility affects event tap permissions

## Technical Debugging Approach

### Required Console Log Analysis
```bash
# Monitor console for hotkey-related activity
log stream --predicate 'subsystem == "com.whispernode.core" OR subsystem == "com.whispernode.app"' --level debug

# Check TCC accessibility permissions
sudo log stream --predicate 'category == "TCC"' --level debug
```

### Code Inspection Points
1. **WhisperNodeCore.initialize():99-106** - Auto-start logic implementation
2. **GlobalHotkeyManager.startListening()** - Event tap creation and enablement
3. **HotkeyRecorderView** - Preferences UI hotkey detection
4. **SettingsManager.hasCompletedOnboarding** - Onboarding status check

### Permission Verification Commands
```bash
# Check current accessibility permissions
sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db "SELECT * FROM access WHERE service='kTCCServiceAccessibility'"

# Reset accessibility permissions (requires restart)
sudo tccutil reset Accessibility com.whispernode.app
```

## Expected Fix Categories

### 1. Accessibility Permission Flow
- Implement proper permission request UI
- Add fallback for when permissions are denied
- Create permission verification before hotkey system startup

### 2. Event Tap Implementation
- Debug CGEventTap creation failure modes
- Implement error handling for event tap setup
- Add retry logic for permission-based failures

### 3. Initialization Sequence
- Verify hotkey system starts at appropriate application lifecycle point
- Ensure dependencies (settings, onboarding) are ready before hotkey init
- Add explicit initialization confirmation logging

### 4. Menu Bar App Considerations
- Research if accessory app activation policy affects global event taps
- Test if explicit app activation is required for accessibility permissions
- Implement workarounds for headless operation limitations

## Success Criteria

### Minimum Viable Fix
1. Control+Option hotkey triggers recording orb appearance
2. Enhanced debug logging appears in console during hotkey detection
3. Accessibility permissions properly granted and verified
4. Complete hotkey → recording → transcription pipeline functional

### Full Resolution
1. All hotkey combinations work reliably
2. Comprehensive error handling for permission failures
3. User-friendly permission request flow
4. Robust initialization and recovery mechanisms

## Dependencies
- **Blocks**: T30, T31 (UI improvements depend on core functionality)
- **Requires**: macOS accessibility permissions understanding
- **Impacts**: Core app functionality, user onboarding experience

## Priority: CRITICAL
This task blocks all core functionality testing and user experience validation. The app is currently non-functional for its primary use case.

## Next Actions
1. Push current debugging branch to remote
2. Deep dive into macOS accessibility permission system
3. Research menu bar app limitations with global event taps
4. Implement comprehensive permission verification and error handling
5. Test with different app bundle configurations and signing states

---
*Created: 2025-01-06*  
*Last Updated: 2025-01-06*  
*Assigned: Claude Code Analysis*