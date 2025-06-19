# Delegate Integration for Audio Start/Stop Control

**Date**: December 18, 2024  
**Status**: 🔄 NOT STARTED  
**Priority**: HIGH  

## Overview

Verify and enhance the delegate integration between GlobalHotkeyManager and WhisperNodeCore to ensure reliable audio engine start/stop control and proper state management throughout the recording lifecycle.

## Issues Addressed

### 1. **Audio Engine Start/Stop Reliability**
- **Problem**: Audio engine may not start/stop consistently when hotkey events fire
- **Root Cause**: Delegate callbacks not firing reliably or audio engine calls failing silently
- **Impact**: Recording functionality appears to work but no audio is captured

### 2. **State Synchronization Issues**
- **Problem**: UI state and audio engine state may become desynchronized
- **Root Cause**: Incomplete error handling or callback failures not properly handled
- **Impact**: Recording indicator shows active state but audio isn't being captured

### 3. **Error Handling Gaps**
- **Problem**: Audio engine errors not properly propagated or handled
- **Root Cause**: Insufficient error handling in delegate callbacks
- **Impact**: Silent failures leave user unaware of recording problems

## Technical Requirements

### 1. Reliable Delegate Callbacks
- Ensure `didStartRecording`, `didCompleteRecording`, and `didCancelRecording` always fire
- Implement comprehensive error handling for all delegate methods
- Add logging and diagnostics for callback execution

### 2. Audio Engine Integration
- Verify `audioEngine.startCapture()` and `audioEngine.stopCapture()` are called correctly
- Implement proper error handling for audio engine operations
- Ensure audio engine state synchronization with UI state

### 3. State Management
- Maintain consistent state across hotkey manager, core, and UI components
- Implement proper cleanup for interrupted or failed operations
- Add state validation and recovery mechanisms

## Implementation Plan

### Phase 1: Current Integration Analysis
1. **Callback Flow Documentation**
   - Map complete flow from hotkey event to audio engine control
   - Document current delegate method implementations
   - Identify potential failure points and error conditions

2. **State Management Review**
   - Analyze current state synchronization mechanisms
   - Document state transitions and dependencies
   - Identify inconsistency scenarios

### Phase 2: Enhancement Implementation
1. **Delegate Method Improvements**
   - Enhance error handling in all delegate methods
   - Add comprehensive logging and diagnostics
   - Implement retry mechanisms for transient failures

2. **Audio Engine Integration**
   - Verify and enhance audio engine start/stop calls
   - Add proper error propagation and handling
   - Implement state validation and recovery

### Phase 3: Testing and Validation
1. **Integration Testing**
   - Test complete recording lifecycle under various conditions
   - Verify error handling and recovery mechanisms
   - Validate state consistency across components

2. **Error Scenario Testing**
   - Test behavior when audio engine fails to start/stop
   - Test delegate callback failures and recovery
   - Validate error reporting and user feedback

## Files to Modify

### Core Integration
1. **`Sources/WhisperNode/Core/WhisperNodeCore.swift`**
   - Enhance delegate method implementations
   - Improve error handling and logging
   - Add state validation and recovery logic
   - Implement comprehensive audio engine integration

2. **`Sources/WhisperNode/Core/GlobalHotkeyManager.swift`**
   - Add delegate callback reliability mechanisms
   - Implement callback execution validation
   - Enhance error reporting for delegate failures

### Audio Engine Integration
3. **`Sources/WhisperNode/Audio/AudioCaptureEngine.swift`**
   - Enhance error reporting for start/stop operations
   - Add state validation and diagnostics
   - Implement proper cleanup for failed operations

4. **`Sources/WhisperNode/UI/RecordingIndicatorWindowManager.swift`**
   - Ensure UI state synchronization with audio state
   - Add error state visualization
   - Implement state recovery mechanisms

## Detailed Implementation

### Enhanced Delegate Methods
```swift
extension WhisperNodeCore: GlobalHotkeyManagerDelegate {
    func didStartRecording() {
        logger.info("Hotkey delegate: Starting recording")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update state first
            self.isRecording = true
            
            // Update UI
            self.menuBarManager.updateRecordingState(true)
            self.recordingIndicatorManager.showRecording()
            
            // Start audio capture with error handling
            Task { [weak self] in
                do {
                    try await self?.audioEngine.startCapture()
                    logger.info("Audio capture started successfully")
                } catch {
                    logger.error("Failed to start audio capture: \(error)")
                    
                    // Revert state on failure
                    await MainActor.run {
                        self?.handleAudioStartFailure(error)
                    }
                }
            }
        }
    }
    
    func didCompleteRecording() {
        logger.info("Hotkey delegate: Completing recording")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update state
            self.isRecording = false
            
            // Update UI to processing state
            self.recordingIndicatorManager.showProcessing(0.0)
            
            // Stop audio capture and process
            Task { [weak self] in
                do {
                    try await self?.audioEngine.stopCapture()
                    logger.info("Audio capture stopped successfully")
                    
                    // Process the captured audio
                    await self?.processAudioData()
                } catch {
                    logger.error("Failed to stop audio capture: \(error)")
                    await MainActor.run {
                        self?.handleAudioStopFailure(error)
                    }
                }
            }
        }
    }
    
    func didCancelRecording() {
        logger.info("Hotkey delegate: Cancelling recording")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update state
            self.isRecording = false
            
            // Update UI
            self.menuBarManager.updateRecordingState(false)
            self.recordingIndicatorManager.hideIndicator()
            
            // Stop audio capture without processing
            Task { [weak self] in
                do {
                    try await self?.audioEngine.stopCapture()
                    logger.info("Audio capture cancelled successfully")
                } catch {
                    logger.error("Failed to cancel audio capture: \(error)")
                    // Still update UI even if stop fails
                    await MainActor.run {
                        self?.handleAudioCancelFailure(error)
                    }
                }
            }
        }
    }
}
```

### Error Handling Methods
```swift
private func handleAudioStartFailure(_ error: Error) {
    logger.error("Audio start failure: \(error)")
    
    // Revert state
    isRecording = false
    menuBarManager.updateRecordingState(false)
    recordingIndicatorManager.hideIndicator()
    
    // Show error to user
    errorManager.handleAudioEngineError(error)
    
    // Provide haptic feedback
    hapticManager.playErrorFeedback()
}

private func handleAudioStopFailure(_ error: Error) {
    logger.error("Audio stop failure: \(error)")
    
    // Ensure clean state
    isRecording = false
    menuBarManager.updateRecordingState(false)
    recordingIndicatorManager.hideIndicator()
    
    // Show error to user
    errorManager.handleAudioEngineError(error)
}

private func handleAudioCancelFailure(_ error: Error) {
    logger.error("Audio cancel failure: \(error)")
    
    // Ensure clean state regardless of error
    isRecording = false
    menuBarManager.updateRecordingState(false)
    recordingIndicatorManager.hideIndicator()
    
    // Log error but don't show to user (cancellation should be silent)
}
```

### State Validation
```swift
private func validateAudioEngineState() -> Bool {
    let engineState = audioEngine.isCapturing
    let coreState = isRecording
    
    if engineState != coreState {
        logger.warning("State mismatch - Engine: \(engineState), Core: \(coreState)")
        
        // Attempt to synchronize states
        if engineState && !coreState {
            // Engine is capturing but core thinks it's not
            Task {
                try? await audioEngine.stopCapture()
            }
        } else if !engineState && coreState {
            // Core thinks it's recording but engine is not
            isRecording = false
            menuBarManager.updateRecordingState(false)
            recordingIndicatorManager.hideIndicator()
        }
        
        return false
    }
    
    return true
}
```

## Success Criteria

### Functional Requirements
- [ ] Audio engine starts reliably when hotkey pressed
- [ ] Audio engine stops reliably when hotkey released
- [ ] Recording cancellation properly stops audio capture
- [ ] All delegate callbacks execute without failure

### Error Handling
- [ ] Audio engine failures properly handled and reported
- [ ] State inconsistencies detected and corrected
- [ ] User receives appropriate feedback for all error conditions
- [ ] System remains in clean state after any failure

### State Management
- [ ] UI state always reflects actual audio engine state
- [ ] No orphaned recording sessions or stuck states
- [ ] Proper cleanup after interrupted operations
- [ ] State validation and recovery mechanisms work correctly

## Testing Plan

### Unit Tests
- Test each delegate method with various success/failure scenarios
- Test error handling and state recovery mechanisms
- Test state validation and synchronization logic
- Mock audio engine to test error conditions

### Integration Tests
- Test complete recording lifecycle from hotkey to transcription
- Test error scenarios with real audio engine
- Test state synchronization across all components
- Test recovery from various failure modes

### Stress Tests
- Rapid hotkey activation/deactivation cycles
- Audio engine failure simulation
- System resource exhaustion scenarios
- Long-running operation stability

## Edge Cases to Handle

### Audio Engine Failures
- **Microphone Access Denied**: Handle permission revocation during recording
- **Device Disconnection**: Handle audio device removal during recording
- **System Audio Issues**: Handle system audio service failures
- **Resource Exhaustion**: Handle low memory or CPU conditions

### State Synchronization
- **Concurrent Operations**: Multiple recording attempts or state changes
- **UI Thread Blocking**: Main thread blocked during state updates
- **Background/Foreground**: App state changes during recording
- **System Sleep**: Recording interrupted by system sleep

### Delegate Failures
- **Callback Exceptions**: Unhandled exceptions in delegate methods
- **Threading Issues**: Callback execution on wrong thread
- **Memory Issues**: Weak reference failures or memory pressure
- **Timing Issues**: Callbacks fired in unexpected order

## Risk Assessment

### High Risk
- **Silent Failures**: Audio not captured but user thinks it is
- **State Corruption**: Inconsistent state leading to app instability

### Medium Risk
- **Performance Impact**: Error handling overhead affecting responsiveness
- **User Experience**: Frequent error messages disrupting workflow

### Mitigation Strategies
- Comprehensive error handling with proper user feedback
- State validation and automatic recovery mechanisms
- Extensive testing of error conditions and edge cases
- Graceful degradation when components fail

## Dependencies

### Prerequisites
- T29b (Global Hotkey Listener Initialization) - working hotkey system
- T29e (Key Event Capture Verification) - reliable event detection
- Audio capture engine functionality

### Dependent Tasks
- T29h (Settings Persistence) - may affect state management
- T29i (Text Insertion Timing) - depends on reliable audio processing
- T29j (UX Improvements) - builds on reliable core functionality

## Notes

- This task is critical for core app functionality
- Must maintain backward compatibility with existing delegate interface
- Should provide comprehensive diagnostics for troubleshooting
- Consider adding delegate callback validation and monitoring

## Acceptance Criteria

1. **Reliable Audio Control**: Audio engine starts/stops consistently with hotkey events
2. **Comprehensive Error Handling**: All failure modes properly handled with user feedback
3. **State Consistency**: UI and audio engine states always synchronized
4. **Clean Recovery**: System returns to clean state after any failure
5. **Diagnostic Information**: Sufficient logging and diagnostics for troubleshooting issues
