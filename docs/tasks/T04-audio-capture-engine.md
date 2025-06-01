# Task 04: Audio Capture Engine

**Status**: ⏳ WIP  
**Priority**: High  
**Estimated Hours**: 14  
**Dependencies**: T01  

## Description

Build audio capture system using AVAudioEngine with 16kHz mono circular buffer for real-time voice input.

## Acceptance Criteria

- [ ] AVAudioEngine configured for 16kHz mono capture
- [ ] Circular buffer implementation (1024-sample chunks)
- [ ] VAD threshold detection at -40dB
- [ ] Microphone permission handling
- [ ] Input device selection support
- [ ] Live input level monitoring

## Implementation Details

### AVAudioEngine Configuration
```swift
let audioEngine = AVAudioEngine()
let inputNode = audioEngine.inputNode
let recordingFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)
```

### Circular Buffer
- Ring buffer for continuous audio capture
- 1024-sample chunks for processing
- Thread-safe read/write operations

### Voice Activity Detection (VAD)
- Threshold: -40dB
- Prevents processing silence
- Automatic speech detection

### Permission Handling
- Request microphone access on first use
- Handle denied permissions gracefully
- System Preferences deeplink for setup

## Testing Plan

- [ ] Audio capture works on various devices
- [ ] VAD correctly detects speech vs silence
- [ ] Permissions flow works correctly
- [ ] No audio dropouts or buffer overruns

## Tags
`audio`, `avaudioengine`, `capture`, `permissions`