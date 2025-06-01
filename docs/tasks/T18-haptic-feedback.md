# Task 18: Haptic Feedback Integration

**Status**: ⏳ WIP  
**Priority**: Low  
**Estimated Hours**: 4  
**Dependencies**: T03, T05  

## Description

Add subtle haptic feedback for supported MacBooks during recording events.

## Acceptance Criteria

- [ ] Force Touch trackpad detection
- [ ] Subtle single tap feedback (intensity 0.3)
- [ ] Recording start/stop haptic events
- [ ] Accessibility preference respect
- [ ] Graceful degradation on unsupported hardware

## Implementation Details

### Haptic Detection
```swift
import CoreHaptics

class HapticManager {
    private var hapticEngine: CHHapticEngine?
    
    func setupHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        // Initialize haptic engine
    }
}
```

### Feedback Events
- Recording start: Single light tap
- Recording stop: Single light tap
- Error states: Brief double tap
- Intensity: 0.3 (subtle)

### Accessibility
- Respect reduced motion preferences
- Optional disable in preferences
- No functionality dependence on haptics

## Testing Plan

- [ ] Haptics work on supported hardware
- [ ] Graceful degradation on unsupported devices
- [ ] Accessibility preferences are respected
- [ ] Feedback timing feels natural

## Tags
`haptics`, `accessibility`, `feedback`, `hardware`