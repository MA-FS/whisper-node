# Task 03: Global Hotkey System

**Status**: ⏳ WIP  
**Priority**: High  
**Estimated Hours**: 10  
**Dependencies**: T01  

## Description

Implement system-wide hotkey registration using CGEventTap for press-and-hold voice activation.

## Acceptance Criteria

- [ ] CGEventTap implementation for global hotkey capture
- [ ] Press-and-hold detection (no click-to-start)
- [ ] Customizable hotkey configuration
- [ ] Conflict detection with system shortcuts
- [ ] Accessibility permissions handling

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

- [ ] Global hotkey works across all applications
- [ ] Press-and-hold timing is accurate
- [ ] Conflicts are properly detected
- [ ] Accessibility permissions flow works

## Tags
`hotkey`, `cgeventtap`, `input`, `accessibility`