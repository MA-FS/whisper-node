# Audio System Verification & Enhancement

**Date**: December 18, 2024  
**Status**: 🔄 NOT STARTED  
**Priority**: HIGH  

## Overview

Verify and enhance the audio capture system to ensure reliable microphone access, proper audio device management, and seamless integration with the Whisper transcription engine.

## Issues Addressed

### 1. **Microphone Permission Management**
- **Problem**: Microphone permissions may not be properly requested or handled
- **Root Cause**: Focus on accessibility permissions without verifying microphone access
- **Impact**: Audio capture fails silently even when hotkey system works

### 2. **Audio Device Selection and Management**
- **Problem**: App may not handle audio device changes or selection properly
- **Root Cause**: Insufficient audio device management and user control
- **Impact**: Audio capture fails when default device changes or is unavailable

### 3. **Audio Format Compatibility**
- **Problem**: Audio format mismatch between capture engine and Whisper transcription
- **Root Cause**: Assumptions about audio format compatibility without validation
- **Impact**: Transcription fails or produces poor results due to format issues

### 4. **Core Audio Integration**
- **Problem**: Low-level audio system integration may have reliability issues
- **Root Cause**: Complex Core Audio setup without comprehensive error handling
- **Impact**: Audio capture becomes unreliable under various system conditions

## Technical Requirements

### 1. Microphone Permission System
- Implement comprehensive microphone permission detection and request
- Provide clear user guidance for granting microphone access
- Handle permission changes during app runtime

### 2. Audio Device Management
- Detect and manage available audio input devices
- Handle device changes and disconnections gracefully
- Provide user control over audio device selection

### 3. Audio Format Validation
- Ensure audio format compatibility between capture and transcription
- Implement format conversion if necessary
- Validate audio quality and sample rates

### 4. Core Audio Reliability
- Enhance error handling for Core Audio operations
- Implement proper cleanup and resource management
- Add comprehensive logging for audio system diagnostics

## Implementation Plan

### Phase 1: Audio System Assessment
1. **Current Implementation Review**
   - Analyze existing AudioCaptureEngine implementation
   - Document current audio format handling
   - Identify potential reliability issues

2. **Permission System Audit**
   - Review microphone permission handling
   - Test permission request and denial scenarios
   - Document current user guidance system

### Phase 2: Core Enhancements
1. **Permission Management Enhancement**
   - Implement comprehensive microphone permission system
   - Add user-friendly permission request flow
   - Handle runtime permission changes

2. **Audio Device Management**
   - Implement device detection and selection
   - Add device change monitoring
   - Provide user control interface

### Phase 3: Integration and Validation
1. **Format Compatibility**
   - Validate audio format compatibility with Whisper
   - Implement format conversion if needed
   - Test with various audio configurations

2. **Reliability Testing**
   - Test under various system conditions
   - Validate error handling and recovery
   - Performance testing and optimization

## Files to Modify

### Core Audio System
1. **`Sources/WhisperNode/Audio/AudioCaptureEngine.swift`**
   - Enhance microphone permission handling
   - Add audio device management
   - Improve error handling and logging
   - Validate audio format compatibility

2. **`Sources/WhisperNode/Audio/AudioDeviceManager.swift`** (New)
   - Audio device detection and management
   - Device change monitoring
   - User device selection interface

3. **`Sources/WhisperNode/Audio/AudioPermissionManager.swift`** (New)
   - Microphone permission detection and request
   - Permission status monitoring
   - User guidance for permission granting

### Integration Components
4. **`Sources/WhisperNode/Core/WhisperNodeCore.swift`**
   - Integrate audio permission checking
   - Add audio device status monitoring
   - Enhance audio system error handling

5. **`Sources/WhisperNode/UI/Preferences/VoiceTab.swift`**
   - Add audio device selection interface
   - Display audio permission status
   - Provide audio system diagnostics

6. **`Sources/WhisperNode/Utils/AudioFormatValidator.swift`** (New)
   - Audio format compatibility checking
   - Format conversion utilities
   - Audio quality validation

## Detailed Implementation

### Enhanced Audio Permission Management
```swift
import AVFoundation

class AudioPermissionManager: ObservableObject {
    @Published var permissionStatus: AVAudioSession.RecordPermission = .undetermined
    @Published var hasPermission: Bool = false
    
    func checkPermissions() {
        permissionStatus = AVAudioSession.sharedInstance().recordPermission
        hasPermission = (permissionStatus == .granted)
        
        logger.info("Audio permission status: \(permissionStatus)")
    }
    
    func requestPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    self.permissionStatus = granted ? .granted : .denied
                    self.hasPermission = granted
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    func showPermissionGuidance() {
        let alert = NSAlert()
        alert.messageText = "Microphone Access Required"
        alert.informativeText = """
        WhisperNode needs microphone access to capture your voice for transcription.
        
        To enable microphone access:
        1. Open System Preferences
        2. Go to Security & Privacy
        3. Click the Privacy tab
        4. Select Microphone from the list
        5. Check the box next to WhisperNode
        
        After granting permission, the app will automatically detect the change.
        """
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }
}
```

### Audio Device Management
```swift
import CoreAudio

class AudioDeviceManager: ObservableObject {
    @Published var availableDevices: [AudioDevice] = []
    @Published var selectedDevice: AudioDevice?
    @Published var defaultDevice: AudioDevice?
    
    private var deviceChangeListener: AudioObjectPropertyListenerProc?
    
    func initialize() {
        refreshDeviceList()
        setupDeviceChangeMonitoring()
    }
    
    func refreshDeviceList() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else {
            logger.error("Failed to get audio device list size: \(status)")
            return
        }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        
        guard status == noErr else {
            logger.error("Failed to get audio device list: \(status)")
            return
        }
        
        availableDevices = deviceIDs.compactMap { deviceID in
            AudioDevice(deviceID: deviceID)
        }.filter { $0.hasInputChannels }
        
        updateDefaultDevice()
        
        logger.info("Found \(availableDevices.count) audio input devices")
    }
    
    private func setupDeviceChangeMonitoring() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        deviceChangeListener = { (objectID, numAddresses, addresses, clientData) in
            DispatchQueue.main.async {
                if let manager = Unmanaged<AudioDeviceManager>.fromOpaque(clientData!).takeUnretainedValue() as? AudioDeviceManager {
                    manager.refreshDeviceList()
                }
            }
            return noErr
        }
        
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            deviceChangeListener!,
            selfPointer
        )
    }
    
    func selectDevice(_ device: AudioDevice) {
        selectedDevice = device
        logger.info("Selected audio device: \(device.name)")
        
        // Notify audio capture engine of device change
        NotificationCenter.default.post(
            name: .audioDeviceChanged,
            object: device
        )
    }
}

struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let hasInputChannels: Bool
    let sampleRate: Double
    
    init?(deviceID: AudioDeviceID) {
        self.id = deviceID
        
        // Get device name
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr else { return nil }
        
        var deviceName: CFString?
        status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &deviceName)
        guard status == noErr, let name = deviceName as String? else { return nil }
        
        self.name = name
        
        // Check for input channels
        propertyAddress.mSelector = kAudioDevicePropertyStreamConfiguration
        propertyAddress.mScope = kAudioDevicePropertyScopeInput
        
        status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr else { return nil }
        
        let bufferList = AudioBufferList.allocate(maximumBuffers: Int(dataSize) / MemoryLayout<AudioBuffer>.size)
        defer { bufferList.deallocate() }
        
        status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferList.unsafeMutablePointer)
        guard status == noErr else { return nil }
        
        self.hasInputChannels = bufferList.unsafePointer.pointee.mNumberBuffers > 0
        
        // Get sample rate
        propertyAddress.mSelector = kAudioDevicePropertyNominalSampleRate
        propertyAddress.mScope = kAudioObjectPropertyScopeGlobal
        
        var sampleRateValue: Float64 = 0
        dataSize = UInt32(MemoryLayout<Float64>.size)
        status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &sampleRateValue)
        
        self.sampleRate = status == noErr ? sampleRateValue : 44100.0
    }
}
```

### Audio Format Validation
```swift
class AudioFormatValidator {
    static let whisperRequiredFormat = AudioFormat(
        sampleRate: 16000,
        channels: 1,
        bitDepth: 16,
        format: .pcm
    )
    
    static func validateCaptureFormat(_ format: AudioFormat) -> ValidationResult {
        var issues: [String] = []
        var canConvert = true
        
        // Check sample rate
        if format.sampleRate != whisperRequiredFormat.sampleRate {
            issues.append("Sample rate \(format.sampleRate) Hz, Whisper requires \(whisperRequiredFormat.sampleRate) Hz")
        }
        
        // Check channel count
        if format.channels != whisperRequiredFormat.channels {
            issues.append("Channel count \(format.channels), Whisper requires \(whisperRequiredFormat.channels)")
        }
        
        // Check if conversion is possible
        if format.sampleRate > 48000 || format.channels > 2 {
            canConvert = false
            issues.append("Format cannot be converted to Whisper requirements")
        }
        
        return ValidationResult(
            isValid: issues.isEmpty,
            canConvert: canConvert,
            issues: issues
        )
    }
    
    static func createConverter(from sourceFormat: AudioFormat, to targetFormat: AudioFormat) -> AudioConverter? {
        // Implementation for audio format conversion
        // This would use Core Audio's AudioConverter APIs
        return nil // Placeholder
    }
}

struct ValidationResult {
    let isValid: Bool
    let canConvert: Bool
    let issues: [String]
}

struct AudioFormat {
    let sampleRate: Double
    let channels: UInt32
    let bitDepth: UInt32
    let format: AudioFormatType
}

enum AudioFormatType {
    case pcm
    case float
    case compressed
}
```

## Success Criteria

### Permission Management
- [ ] Microphone permissions properly detected and requested
- [ ] Clear user guidance for permission granting
- [ ] Runtime permission changes handled gracefully
- [ ] Permission status visible in preferences

### Device Management
- [ ] All available audio input devices detected
- [ ] Device changes monitored and handled
- [ ] User can select preferred audio device
- [ ] Default device automatically selected

### Audio Quality
- [ ] Audio format compatibility with Whisper validated
- [ ] Format conversion implemented if needed
- [ ] Audio quality meets transcription requirements
- [ ] Sample rate and channel configuration optimized

### Reliability
- [ ] Robust error handling for all audio operations
- [ ] Proper resource cleanup and management
- [ ] Comprehensive logging for diagnostics
- [ ] Stable operation under various conditions

## Testing Plan

### Permission Testing
- Test permission request flow
- Test permission denial handling
- Test runtime permission changes
- Test permission status display

### Device Testing
- Test with various audio devices
- Test device disconnection/reconnection
- Test device selection interface
- Test default device handling

### Format Testing
- Test with different audio formats
- Test format conversion if implemented
- Test audio quality validation
- Test Whisper integration

### Reliability Testing
- Test under various system conditions
- Test error scenarios and recovery
- Test resource usage and cleanup
- Test long-running stability

## Risk Assessment

### High Risk
- **Core Audio Complexity**: Low-level audio APIs can be complex and error-prone
- **Device Compatibility**: Various audio devices may have different capabilities

### Medium Risk
- **Permission Handling**: macOS permission system changes between versions
- **Format Conversion**: Audio format conversion can introduce latency or quality issues

### Mitigation Strategies
- Comprehensive testing with various audio devices
- Robust error handling and fallback mechanisms
- Clear user feedback for audio system issues
- Performance monitoring for audio operations

## Dependencies

### Prerequisites
- Basic app structure and dependency injection
- Error handling and logging systems
- UI components for preferences and feedback

### Dependent Tasks
- T29g (Delegate Integration) - depends on reliable audio system
- T29k (Integration Testing) - will validate audio system functionality
- T29m (Error Recovery) - will handle audio system errors

## Notes

- This task addresses a critical assumption made by other tasks
- Audio system reliability is fundamental to app functionality
- Should be implemented early in the task sequence
- Consider adding audio system diagnostics for user support

## Acceptance Criteria

1. **Complete Permission Management**: Microphone permissions properly handled with clear user guidance
2. **Reliable Device Management**: All audio devices detected and managed with user control
3. **Format Compatibility**: Audio format validated and compatible with Whisper transcription
4. **Robust Error Handling**: All audio system errors handled gracefully with user feedback
5. **Performance**: Audio system operates efficiently without impacting app responsiveness
