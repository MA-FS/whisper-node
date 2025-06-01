# Task 10: Preferences Window - Voice Tab

**Status**: ⏳ WIP  
**Priority**: Medium  
**Estimated Hours**: 10  
**Dependencies**: T04, T09  

## Description

Create Voice preferences with microphone selection, input level meter, and audio settings.

## Acceptance Criteria

- [ ] Microphone device selection dropdown
- [ ] Real-time input level meter (60fps)
- [ ] VAD threshold adjustment
- [ ] Audio format display (16kHz mono)
- [ ] Microphone permission status indicator
- [ ] Test recording functionality

## Implementation Details

### Device Selection
```swift
struct MicrophoneSelector: View {
    @State private var devices = AVAudioSession.sharedInstance().availableInputs
    @State private var selectedDevice: AVAudioSessionPortDescription?
}
```

### Input Level Meter
- Real-time audio level visualization
- 60fps update rate
- dB scale with VAD threshold indicator

### Test Recording
- Short test recording functionality
- Playback for audio verification
- Quality assessment feedback

## Testing Plan

- [ ] Device selection works with external mics
- [ ] Level meter responds to audio input
- [ ] VAD threshold adjustment affects detection
- [ ] Test recording provides useful feedback

## Tags
`preferences`, `audio`, `microphone`, `meter`