# Global Hotkey Listener Initialization Fixes

**Date**: December 18, 2024  
**Status**: 🔄 NOT STARTED  
**Priority**: HIGH  

## Overview

Fix the initialization of the global hotkey listener to ensure `GlobalHotkeyManager.startListening()` is called at the appropriate times during app startup and after onboarding completion, eliminating the need for app restarts.

## Issues Addressed

### 1. **Hotkey System Not Starting After Onboarding**
- **Problem**: User who just finished onboarding might need to restart the app to activate the hotkey
- **Root Cause**: `startListening()` not called immediately after onboarding completion and permission granting
- **Impact**: Poor user experience requiring manual app restart

### 2. **Missing Runtime Permission Detection**
- **Problem**: If app is already running and permissions become available, event tap doesn't start without restart
- **Root Cause**: No periodic checking of `AXIsProcessTrusted()` status
- **Impact**: User must restart app even after granting permissions

## Technical Requirements

### 1. Onboarding Integration
- Call `startListening()` immediately after user finishes onboarding and grants accessibility permission
- Trigger in onboarding completion step, after setting `hasCompletedOnboarding=true`
- Ensure proper error handling if `startListening()` fails

### 2. Runtime Permission Detection
- Implement periodic checking of `AXIsProcessTrusted()` status
- Check when preferences window is closed
- Check on app becoming active from background
- When permissions become available, automatically call `startListening()`

### 3. Startup Sequence Optimization
- Ensure proper initialization order during app startup
- Verify all dependencies are available before calling `startListening()`
- Add comprehensive logging for debugging initialization issues

## Implementation Plan

### Phase 1: Onboarding Integration
1. **Modify Onboarding Completion Handler**
   - Location: `Sources/WhisperNode/UI/OnboardingView.swift`
   - Add call to `hotkeyManager.startListening()` after setting completion flag
   - Add error handling and user feedback if initialization fails

2. **Update WhisperNodeCore Initialization**
   - Location: `Sources/WhisperNode/Core/WhisperNodeCore.swift`
   - Modify initialization logic to support immediate hotkey activation
   - Ensure proper delegate wiring before calling `startListening()`

### Phase 2: Runtime Permission Detection
1. **Implement Permission Monitoring**
   - Create periodic timer to check `AXIsProcessTrusted()` status
   - Implement app activation observer to check permissions
   - Add preferences window close observer

2. **Automatic Activation Logic**
   - When permissions detected as granted, log message and call `startListening()`
   - Ensure no duplicate event taps are created
   - Update UI state to reflect hotkey system activation

### Phase 3: Startup Sequence
1. **Optimize App Launch**
   - Review and document proper initialization order
   - Ensure all required components are initialized before hotkey system
   - Add startup logging for debugging

2. **Error Recovery**
   - Implement retry logic for failed initialization attempts
   - Provide user feedback for persistent initialization failures
   - Add diagnostic information for troubleshooting

## Files to Modify

### Primary Files
1. **`Sources/WhisperNode/Core/WhisperNodeCore.swift`**
   - Modify initialization sequence
   - Add permission monitoring logic
   - Enhance error handling

2. **`Sources/WhisperNode/UI/OnboardingView.swift`**
   - Add hotkey activation to completion handler
   - Implement user feedback for activation status

3. **`Sources/WhisperNode/Core/GlobalHotkeyManager.swift`**
   - Add logging for initialization attempts
   - Implement duplicate prevention logic
   - Enhance error reporting

### Supporting Files
4. **`Sources/WhisperNode/UI/PreferencesWindow.swift`**
   - Add window close observer for permission checking
   - Implement permission status updates

5. **`Sources/WhisperNode/Managers/SettingsManager.swift`**
   - Add settings for permission monitoring frequency
   - Store initialization state

## Success Criteria

### Functional Requirements
- [ ] Hotkey system activates immediately after onboarding completion
- [ ] No app restart required after granting accessibility permissions
- [ ] Automatic activation when permissions become available at runtime
- [ ] Proper error handling and user feedback for initialization failures

### Technical Requirements
- [ ] Clean initialization sequence with proper dependency management
- [ ] Comprehensive logging for debugging initialization issues
- [ ] No duplicate event taps or resource leaks
- [ ] Graceful handling of permission changes

### User Experience
- [ ] Seamless transition from onboarding to functional hotkey system
- [ ] Clear feedback when hotkey system is activated
- [ ] No confusing restart requirements
- [ ] Intuitive error messages for troubleshooting

## Testing Plan

### Unit Tests
- Test onboarding completion handler with hotkey activation
- Test permission monitoring logic
- Test initialization sequence with various permission states

### Integration Tests
- Test complete onboarding flow with immediate hotkey activation
- Test permission granting while app is running
- Test app restart scenarios to ensure no regression

### User Acceptance Tests
- Complete onboarding flow and verify hotkey works immediately
- Grant permissions while app is running and verify automatic activation
- Test various edge cases (permission revocation, multiple permission changes)

## Risk Assessment

### High Risk
- **Timing Issues**: Race conditions between permission granting and detection
- **Resource Leaks**: Multiple event taps if initialization called repeatedly

### Medium Risk
- **Performance Impact**: Frequent permission checking affecting app performance
- **UI Responsiveness**: Blocking UI during initialization attempts

### Mitigation Strategies
- Implement proper synchronization for permission checking
- Add safeguards against duplicate initialization
- Use background queues for permission monitoring
- Implement timeout mechanisms for initialization attempts

## Dependencies

### Prerequisites
- T29a (Hotkey System Debugging) - for understanding current initialization flow
- Accessibility permission handling improvements
- Error handling system enhancements

### Dependent Tasks
- T29c (Accessibility Permission Handling) - will build on this initialization work
- T29d (Modifier-Only Hotkey Logic) - requires working initialization
- T29e (Key Event Capture Verification) - needs functional hotkey system

## Notes

- This task focuses on the initialization timing and sequence
- Does not address the underlying permission handling UI (covered in T29c)
- Should eliminate the most common user complaint about needing to restart the app
- Critical for achieving "it just works" user experience

## Acceptance Criteria

1. **No Restart Required**: User can complete onboarding and immediately use hotkey functionality
2. **Runtime Activation**: Granting permissions while app is running automatically enables hotkey
3. **Proper Error Handling**: Clear feedback when initialization fails with actionable guidance
4. **Performance**: Permission monitoring doesn't impact app responsiveness
5. **Reliability**: Initialization works consistently across different macOS versions and hardware
