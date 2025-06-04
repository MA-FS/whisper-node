# Task 27: Voice Tab UI Fixes and Audio Input Issues

**Status**: ⏳ WIP  
**Priority**: High  
**Estimated Hours**: 12  
**Dependencies**: T10  

## Description

Fix critical UI and functionality issues in the Voice preferences tab including overlapping UI elements, non-responsive input level meter, and test recording functionality failures.

## Problem Analysis

### Issue 1: UI Element Overlapping
- **Root Cause**: Insufficient spacing and padding in VoiceTab layout
- **Symptoms**: UI elements overlap, particularly in the input level section
- **Impact**: Poor user experience, accessibility issues

### Issue 2: Input Level Meter Not Responding
- **Root Cause**: Audio capture engine not properly initialized or permission issues
- **Symptoms**: Level meter shows no movement despite microphone permission granted
- **Impact**: Users cannot verify microphone functionality

### Issue 3: Test Recording Failure
- **Root Cause**: Test recording runs for only 3 seconds with progress bar disappearing
- **Symptoms**: Progress bar appears briefly then disappears, no feedback provided
- **Impact**: Users cannot test their microphone setup

## Investigation Findings

### Current Implementation Issues

1. **VoiceTab.swift Layout Problems**:
   - Fixed spacing of 20pt may be insufficient for all content
   - Input level meter section lacks proper vertical spacing
   - VAD threshold controls may overlap with level meter

2. **Audio Engine Integration**:
   - `AudioCaptureEngine` initialization may fail silently
   - Level meter timer starts but audio capture may not be active
   - Permission status not properly synchronized with UI state

3. **Test Recording Logic**:
   - Timer-based progress tracking disconnected from actual recording
   - No error handling for recording failures
   - Progress bar animation completes regardless of recording status

### Code Analysis

**VoiceTab.swift Issues**:
- Line 29: `VStack(alignment: .leading, spacing: 20)` - insufficient spacing
- Lines 154-206: Input level section needs better layout structure
- Lines 208-245: Test recording section lacks error handling

**AudioCaptureEngine.swift Issues**:
- Lines 441-468: `startLevelMeterTimer()` may fail silently
- Lines 490-516: Test recording logic is purely UI-based, not connected to actual audio

## Acceptance Criteria

- [ ] Fix UI element overlapping in Voice tab
- [ ] Ensure input level meter responds to microphone input
- [ ] Fix test recording functionality to provide proper feedback
- [ ] Improve error handling and user feedback
- [ ] Ensure proper spacing and padding throughout Voice tab
- [ ] Validate microphone permission flow works correctly

## Implementation Plan

### Phase 1: UI Layout Fixes
1. **Increase spacing and padding**:
   - Update main VStack spacing from 20 to 24
   - Add proper section spacing between components
   - Ensure adequate padding around input level meter

2. **Fix overlapping elements**:
   - Restructure input level section layout
   - Add proper spacing between VAD threshold controls
   - Ensure level meter has adequate height and spacing

### Phase 2: Audio Engine Integration
1. **Fix level meter responsiveness**:
   - Ensure audio capture starts properly in level meter mode
   - Add error handling for audio capture failures
   - Improve permission status synchronization

2. **Enhance error feedback**:
   - Add visual indicators for audio capture status
   - Provide clear error messages for permission issues
   - Add retry mechanisms for failed audio initialization

### Phase 3: Test Recording Fixes
1. **Connect test recording to actual audio**:
   - Implement real audio recording during test
   - Provide audio playback for verification
   - Add proper progress tracking based on actual recording

2. **Improve user feedback**:
   - Add success/failure indicators
   - Provide audio quality assessment
   - Add clear instructions and error messages

## Testing Plan

- [ ] Test UI layout on different screen sizes and accessibility settings
- [ ] Verify input level meter responds to various microphone inputs
- [ ] Test recording functionality with different audio devices
- [ ] Validate error handling for permission denied scenarios
- [ ] Test with external microphones and audio interfaces
- [ ] Verify accessibility compliance and VoiceOver support

## Technical Notes

### UI Layout Constants
```swift
// Improved spacing constants
private static let sectionSpacing: CGFloat = 24
private static let componentSpacing: CGFloat = 16
private static let levelMeterHeight: CGFloat = 32
```

### Audio Engine Error Handling
```swift
// Enhanced error handling for audio capture
private func handleAudioCaptureError(_ error: Error) {
    audioErrorMessage = error.localizedDescription
    showAudioError = true
    permissionStatus = .denied
}
```

## Tags
`voice-tab`, `ui-fixes`, `audio-engine`, `microphone`, `level-meter`, `test-recording`
