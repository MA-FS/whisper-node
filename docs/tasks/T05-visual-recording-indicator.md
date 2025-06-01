# Task 05: Visual Recording Indicator

**Status**: ⏳ WIP  
**Priority**: High  
**Estimated Hours**: 16  
**Dependencies**: T01  

## Description

Create floating orb UI with animations, positioning, and state management for recording feedback.

## Acceptance Criteria

- [ ] 80pt diameter orb with NSVisualEffectView blur
- [ ] Positioning: 24pt from bottom-right screen edge
- [ ] State colors: systemBlue (idle/recording), systemRed (error)
- [ ] Animations: 0.3s fade in/out, 1.2s pulse during recording
- [ ] Progress ring for processing state
- [ ] Theme support (light/dark/high contrast)
- [ ] Reduced motion accessibility support

## Implementation Details

### Orb Design Specifications
- **Dimensions**: 80pt diameter (160pt on Retina)
- **Positioning**: 24pt from bottom-right edge
- **Material**: NSVisualEffectView with `.hudWindow`

### State Colors
- Idle: `systemBlue` with 70% opacity (#007AFF70)
- Recording: `systemBlue` with 85% opacity + pulse
- Processing: Progress ring in `systemBlue`
- Error: `systemRed` with 70% opacity (#FF3B3070)

### Animations
```swift
// Fade in/out
.animation(.easeInOut(duration: 0.3))

// Pulse during recording
.scaleEffect(isRecording ? 1.1 : 1.0)
.animation(.easeInOut(duration: 1.2).repeatForever())
```

### Accessibility
- VoiceOver: "Recording indicator"
- High contrast: 90% opacity
- Reduced motion: Static color changes only

## Testing Plan

- [ ] Orb appears/disappears correctly
- [ ] All state transitions work
- [ ] Animations respect accessibility settings
- [ ] Theme changes work properly

## Tags
`ui`, `swiftui`, `animations`, `accessibility`, `orb`