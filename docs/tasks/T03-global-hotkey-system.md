# Task 03: Global Hotkey System

**Status**: ✅ Done  
**Priority**: High  
**Estimated Hours**: 10  
**Dependencies**: T01  

## Description

Implement system-wide hotkey registration using CGEventTap for press-and-hold voice activation.

## Acceptance Criteria

- [x] CGEventTap implementation for global hotkey capture
- [x] Press-and-hold detection (no click-to-start)
- [x] Customizable hotkey configuration
- [x] Conflict detection with system shortcuts
- [x] Accessibility permissions handling

## Implementation Details

### CGEventTap Setup
- Request accessibility permissions
- Register global event tap with `kCGEventTapOptionDefault`
- Handle key down/up events for press-and-hold

### Hotkey Detection
```swift
func createEventTap() -> CFMachPort? {
    let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
    return CGEvent.tapCreate(...)
}
```

### Conflict Detection
- Check against system shortcuts
- Validate with other running applications
- Provide alternative suggestions

## Testing Plan

- [x] Global hotkey works across all applications
- [x] Press-and-hold timing is accurate
- [x] Conflicts are properly detected
- [x] Accessibility permissions flow works

## Tags
`hotkey`, `cgeventtap`, `input`, `accessibility`