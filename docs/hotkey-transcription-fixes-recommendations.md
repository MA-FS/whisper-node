# WhisperNode Hotkey & Transcription Fixes - Comprehensive Recommendations

## Hotkey Activation & Transcription – Issues and Fixes

### Issues with Hotkey Detection and Activation

#### 1. Global Hotkey Not Triggering
The Control+Option hotkey (or any configured combination) fails to start voice capture. This is likely due to the global event tap not running or not receiving events. In the current code, if the hotkey system isn't initialized properly (e.g. `startListening()` never called) or if macOS Accessibility permission is missing, the hotkey press does nothing.

**Symptoms:**
- No recording orb appearing
- No log output when keys are pressed
- App needs to ensure hotkey listener is started with necessary privileges

#### 2. Modifier-Only Hotkey Release Behavior
When using a modifier-only hotkey (e.g. Ctrl+Alt with no additional key), the release logic is flawed. Currently, if the user doesn't release both keys at exactly the same time, the code treats it as an "interrupted" hotkey and cancels the transcription instead of completing it.

**Example:** Lifting one finger off Ctrl slightly before Alt triggers a cancellation. This prevents the intended behavior of stopping recording and processing the audio on key release.

#### 3. Event Tap Setup & Permissions
The global hotkey uses a CGEventTap that requires Accessibility access. If that permission isn't granted or if the event tap isn't installed correctly, no key events will be captured.

**Issues:**
- Alert prompts user to enable Accessibility permissions but asks for app restart
- Creates usability hiccup – hotkey won't function until restart
- If onboarding flow doesn't call `startListening()` at right time, hotkey system might never activate

#### 4. Transcription Not Starting/Stopping at Correct Times
Even when the hotkey is detected, we need to confirm that the microphone is activated as soon as the keys are held down and deactivated on release. Any delay in starting the audio engine or stopping it could cause missed speech or extra unwanted audio.

**Current Design:** Triggers audio start on hotkey press delegate callback and stops on release, which is correct in design. We need to verify these callbacks always fire.

#### 5. Text Insertion Reliability
After transcription, the text should be injected at the current cursor location. The code uses a TextInsertionEngine with CGEvent keyboard events to type out the result.

**Potential Issues:**
- Focus issues or empty text
- Insertion code should run on main thread
- Target application should be active
- Edge cases preventing consistent operation

## Technical To-Do List – Hotkey & Transcription Fixes

### 1. Initialize the Global Hotkey Listener
Ensure that `GlobalHotkeyManager.startListening()` is called during app startup or immediately after onboarding. Currently, the core is designed to auto-start hotkey listening only if onboarding is complete and permissions are in place.

**Issues:**
- User who just finished onboarding might need to restart the app to activate the hotkey

**Solutions:**
- Call `startListening()` as soon as user finishes onboarding and grants accessibility permission
- If app is already running and permissions become available, start event tap without requiring restart
- Re-check `AXIsProcessTrusted()` periodically or when preferences window is closed

### 2. Improve Accessibility Permission Handling
The app should robustly handle the Accessibility (AX) permission required for listening to global keys.

**Current Issues:**
- Uses `AXIsProcessTrustedWithOptions` to prompt user and shows instructions in alert
- Silent failure when permissions missing

**Improvements Needed:**
- Detect if permissions are missing at launch and inform user immediately
- Highlight in UI or menu bar icon rather than silently failing
- After user grants permission, allow app to pick that up automatically
- Periodically call `AXIsProcessTrusted()` in background
- When it returns true, log message and call `startListening()` automatically
- Eliminate "please restart" requirement and make activation seamless
- If user refuses permission, gracefully handle it with red menu bar icon
- Display tooltip or menu item like "Enable Accessibility in System Settings to activate hotkey"

### 3. Fix Modifier-Only Hotkey Logic
Adjust the logic in `GlobalHotkeyManager.handleFlagsChanged(_:)` so that releasing a modifier-only combo properly ends the recording.

**Current Problem:**
- Code cancels on a change in flags (going from both modifiers to one modifier)
- Should remove that cancellation for this scenario

**Solution:**
- When target modifiers (e.g. Control+Option) are pressed, start recording as now
- When any of those modifiers are released, treat as end of push-to-talk and finalize recording
- Wait until all required modifiers are up, then end normally
- First modifier keyup event can trigger the stop
- May implement slight delay (few milliseconds) to see if second modifier released nearly simultaneously
- Only cancel if user presses unrelated key or completely different modifier combination while recording
- Test thoroughly: holding Ctrl+Option should start recording, and whether user lets go of both keys at once or one-after-the-other, recording should end once both keys are up and proceed to transcription

### 4. Verify Key Event Capture (Key Down/Up)
Currently, the event tap listens for `.keyDown`, `.keyUp`, and `.flagsChanged` events.

**Requirements:**
- Key-down of normal key + modifiers triggers start (for combos like Ctrl+Opt+Space)
- Code's `handleEvent` checks if event matches configured hotkey and on `.keyDown` calls `handleKeyDown()`
- On `.keyUp`, calls `handleKeyUp()` to stop recording
- FlagsChanged for pure modifiers triggers start/stop appropriately
- `matchesCurrentHotkey` function has logic to handle case where `keyCode == UInt16.max` (sentinel for modifier-only hotkey)
- Should only return true on `.flagsChanged` event that brings modifier state equal to target combo
- No double-triggering: code uses internal `keyDownTime` to ignore repeated keyDowns until keyUp occurs

### 5. Enhance Threading for Event Tap
The CGEventTap is currently added on the main thread's run loop. If the main thread is ever busy, keyboard events could be delayed.

**Best Practice:**
- Move event tap listening to dedicated thread
- Create background thread when starting hotkey listener
- Attach event tap's run loop source to that thread's run loop
- Isolates key capture from main UI thread
- Delegate callbacks can still be dispatched to main actor for UI work
- Improves reliability, especially under high load

### 6. Confirm Delegate Integration for Audio Start/Stop
Once hotkey events fire, the WhisperNodeCore (as GlobalHotkeyManagerDelegate) should handle them:

**On didStartRecording:**
- Sets `isRecording=true`
- Updates menubar state
- Shows recording indicator
- Starts audio capture engine
- Ensure `audioEngine.startCapture()` is being called on background Task
- Handle any errors (catch exceptions and show errors if mic not available)

**On didCompleteRecording:**
- Stops audio engine
- Signals transcription processing state
- Verify `audioEngine.stopCapture()` always called when it should be
- If orb ever stays "listening" or mic stays on after keys released, indicates callback didn't fire

**On didCancelRecording:**
- Called if recording was too short or interrupted
- Implementation stops capture and hides indicator
- Ensure canceled recording doesn't attempt to transcribe anything
- Leaves system in clean state (orb hidden, `isRecording=false`)

### 7. Persist and Load Hotkey Settings
Confirm that hotkey configuration is saved to user settings and restored on launch.

**Current Implementation:**
- Uses SettingsManager to store `hotkeyKeyCode` and `hotkeyModifierFlags`
- Loads them on GlobalHotkeyManager init

**Requirements:**
- Make sure modifier-only combo is represented properly
- Use `UInt16.max` as keyCode for "modifier-only" hotkeys
- Needs to round-trip to UserDefaults correctly
- When loading, code should interpret correctly and not treat as actual key
- Check that changing hotkey in Preferences updates active hotkey immediately
- ShortcutTab calls `hotkeyManager.updateHotkey(newHotkey)` which stops and restarts listener if active

### 8. Text Insertion Timing
Once audio is captured and transcribed, text injection happens in `processAudioData()` by calling `textInsertionEngine.insertText(result.text)`.

**Requirements:**
- Recording indicator switches to "processing" state on release
- Hides when transcription is done
- UI properly reflects sequence (orb turns into processing spinner or different color, then disappears)
- `insertText` function synthesizes key events or pasteboard insertion to input text
- Test in different target applications (TextEdit, browser address bar, chat application)
- If injection occasionally misses first character (timing issue), add tiny delay before insertion
- Ensure target app is frontmost

## Swift/macOS API Adjustments and Enhancements

### 1. Global Event Tap Configuration
The use of `CGEvent.tapCreate` with session-level event tap is correct for capturing global keystrokes.

**Current Setup:**
- Using `.cgSessionEventTap` at `.headInsertEventTap` with `.defaultTap` options
- App intercepts keys (system/other apps won't see them while held)
- Returns nil for matching events, effectively consuming them

**Improvements:**
- Add more debug logging around tap creation success/failure
- Log value of `CGEventTapCreate` result or any error codes for clarity

### 2. NSEvent Monitor Fallback
The app uses `NSEvent.addGlobalMonitorForEvents(matching:)` in preferences UI when recording new shortcut.

**Notes:**
- NSEvent global monitors don't require separate Accessibility permission
- Work as long as app is frontmost
- Don't receive keyUp events for modifiers reliably (why CGEventTap needed)
- Ensure monitors are removed to avoid leaks
- Could fall back to global NSEvent monitor if CGEventTap cannot be enabled (degraded experience)

### 3. UI Indicator (NSWindow) Level
Ensure recording indicator window is created with proper style and level.

**Requirements:**
- Borderless, non-activating panel that floats above normal windows
- `NSWindow.Level.floating` or `.statusBar` level
- Ignore mouse events so doesn't grab focus
- Adjust window's level and collection behavior if issues exist

### 4. Haptic and Sound Feedback
The app uses `NSHapticFeedbackManager` for feedback on hotkey press/release and errors.

**Considerations:**
- Haptic feedback only felt on devices with trackpad/Magic Mouse that supports it
- Only if app is active
- Consider adding audible cue using `NSSound` or system sound for start/stop recording
- Should respect user's sound settings (make optional in preferences)

### 5. Voice Activity Detection (VAD)
The AudioCaptureEngine includes voice activity detection and input level monitoring.

**Improvements:**
- Use VAD to control orb's appearance (change color/animation when speech detected vs background noise)
- Code already toggles indicator between "recording" (active voice) and "idle" (no voice detected but still listening)
- Verify this is working correctly
- May need to tweak VAD threshold or UI update frequency

### 6. Whisper Model Performance
Apply macOS best practices for Whisper processing:

**Requirements:**
- Ensure whisper processing is on background thread
- App monitors CPU and can auto-downgrade model size if needed
- Consider using `autoreleasepool` around transcription
- Free Whisper model from memory when not in use if memory is concern
- Handle audio session interruptions properly
- Handle edge cases (user locks screen while holding hotkey, high system load, multi-monitor/Spaces)

## UX and Reliability Improvements (Siri-Like Experience)

### 1. Seamless Activation
Goal: User can press hotkey anytime, in any app, and immediately see feedback that system is listening.

**Requirements:**
- On first launch: go through onboarding, grant permissions, set hotkey, press it in different app
- Orb should appear and transcription should work with no extra steps
- "It just works" experience like Apple aims for
- If permission prompt doesn't appear or user accidentally denies, add guidance
- Mention enabling Accessibility for hotkey in onboarding "Permissions" step

### 2. Visual Indicator & Feedback
Make recording indicator as clear and responsive as possible.

**Position and Appearance:**
- Ensure orb is not stuck in corner or hidden
- Should be noticeable but not intrusive
- Consider where to show on multiple monitors (all monitors or just main? all spaces or just current?)

**Animation:**
- Add subtle pulsing or waveform animation to indicate actively listening
- Makes experience feel alive and confirms speech is being picked up

**State Changes:**
- Use different visuals for listening vs processing vs error
- When user releases keys and orb switches to "processing", change color or show spinner overlay
- When error occurs, flash orb red briefly
- Menu bar icon also changes color for errors

**Duration:**
- If user holds hotkey for extremely long time, consider how orb behaves
- Ensure UI doesn't start lagging
- Audio buffer might recycle unless handling long recordings explicitly
- Perhaps set upper limit like 60 seconds with gentle cutoff

### 3. User Control and Preferences
For usability:

**Re-trigger Options:**
- Provide way to easily re-trigger onboarding or permission checks if something goes wrong
- Button in preferences like "Re-check Accessibility Permission"
- Calls `AXIsProcessTrustedWithOptions` with prompt again

**Clear Status Display:**
- In Preferences > Shortcut tab, show clear message if hotkey system inactive due to permission issues
- If `AXIsProcessTrusted()` is false, display warning icon and message
- "⚠️ Global hotkeys disabled – enable Accessibility permissions to use voice activation hotkey"

**Toggle Option:**
- Possibly allow user to choose whether hotkey is press-and-hold or toggle
- Current design is strictly press-and-hold (aligns with "walkie-talkie" or Siri behavior)
- Some users might prefer toggle (press once to start, again to stop)

### 4. Performance and Responsiveness
App should remain lightweight when idle.

**Requirements:**
- Menubar icon and background threads shouldn't hog CPU when not in use
- Audio engine shouldn't run when idle (starts only on hotkey, stops after)
- Whisper model shouldn't consume resources until needed
- WhisperNodeCore keeps model loaded by default (tiny.en), which is fine

**During Transcription:**
- Consider providing intermediate feedback for longer audio
- Whisper.cpp can sometimes provide partial results if configured (streaming mode)
- User might see words appear as being recognized
- Currently waits until end and inserts all text at once (acceptable and simpler)
- Enhancement: stream partial text in floating text box near orb, then finalize at release

**Memory Management:**
- Ensure app doesn't leak memory or file handles
- Each start/stop audio and transcribe uses memory for audio buffer and transcription result
- Should be freed properly over many uses
- Run through Instruments (Leaks and CPU profiler) for validation

### 5. Graceful Handling of Fast Re-activation
If user quickly presses hotkey again right after releasing (to correct themselves or say another sentence), system should handle it.

**Current Behavior:**
- After finishing transcription, there's moment where app is inserting text and showing processing indicator
- If user presses hotkey during that, event tap will detect hotkey and start new recording
- Previous transcription might still be running in background thread

**Improvements:**
- Consider blocking hotkey while processing (ignore hotkey presses until previous result injected)
- Or queue them (less ideal)
- Siri typically doesn't let you start new query until last one is done
- Implement with flag like `isTranscribing` set when beginning Whisper transcription, cleared when done
- If `isTranscribing == true`, `didStartRecording` delegate could immediately cancel new recording
- Perhaps flash orb or play brief "busy" sound

### 6. Testing Scenarios for Reliability
Test with different scenarios:

**Key Combinations:**
- Letter key with modifiers (Ctrl+Alt+S)
- Function key
- Pure modifier
- Single key (if allowed)

**Environment Testing:**
- Without active internet connection (confirm no part tries to reach out)
- Intel vs Apple Silicon if applicable
- Different macOS versions (Accessibility API and event taps can have quirks)

**User Feedback Integration:**
- Once fixes are in, use user reports to further refine experience
- "It didn't start when I pressed keys"
- "It stopped too soon"
- "It typed text in wrong place"

## Implementation Priority

By implementing these comprehensive fixes and enhancements, WhisperNode will become much more robust and user-friendly. The hotkey will reliably activate the microphone while held, the Siri-like orb will give immediate feedback, and upon release the transcribed text will appear at the cursor with minimal delay.

Each detail – from permission handling to visual feedback – contributes to an intuitive press-to-talk workflow that "just works" for the end user, making WhisperNode feel as natural as a native macOS feature like Siri or Dictation.
