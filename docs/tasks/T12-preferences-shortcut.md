# Task 12: Preferences Window - Shortcut Tab

**Status**: ⏳ WIP  
**Priority**: Medium  
**Estimated Hours**: 8  
**Dependencies**: T03, T09  

## Description

Create hotkey customization interface with conflict detection and recording.

## Acceptance Criteria

- [ ] Hotkey recorder interface
- [ ] System shortcut conflict detection
- [ ] Alternative suggestion system
- [ ] Modifier key combination support
- [ ] Reset to default functionality
- [ ] Visual feedback for conflicts

## Implementation Details

### Hotkey Recorder
```swift
struct HotkeyRecorder: View {
    @State private var isRecording = false
    @State private var currentShortcut: KeyboardShortcut?
    @State private var conflictDetected = false
}
```

### Conflict Detection
- Check against system shortcuts
- Scan running applications
- Provide alternative suggestions
- Non-blocking notifications

### Shortcut Validation
- Ensure modifier keys are present
- Validate key combinations
- Prevent single-key shortcuts

## Testing Plan

- [ ] Hotkey recording captures correctly
- [ ] Conflicts are properly detected
- [ ] Suggestions are helpful
- [ ] Reset functionality works

## Tags
`preferences`, `hotkey`, `shortcuts`, `conflicts`