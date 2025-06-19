
Hotkey Activation & Transcription – Issues and Fixes
Issues with Hotkey Detection and Activation
Global Hotkey Not Triggering: The Control+Option hotkey (or any configured combination) fails to start voice capture. This is likely due to the global event tap not running or not receiving events. In the current code, if the hotkey system isn’t initialized properly (e.g. startListening() never called) or if macOS Accessibility permission is missing, the hotkey press does nothing
GitHub
GitHub
. Symptoms include no recording orb appearing and no log output when the keys are pressed. The app needs to ensure the hotkey listener is started and has the necessary privileges.
Modifier-Only Hotkey Release Behavior: When using a modifier-only hotkey (e.g. Ctrl+Alt with no additional key), the release logic is flawed. Currently, if the user doesn’t release both keys at exactly the same time, the code treats it as an “interrupted” hotkey and cancels the transcription instead of completing it
GitHub
. For example, lifting one finger off Ctrl slightly before Alt triggers a cancellation. This prevents the intended behavior of stopping recording and processing the audio on key release.
Event Tap Setup & Permissions: The global hotkey uses a CGEventTap that requires Accessibility access. If that permission isn’t granted or if the event tap isn’t installed correctly, no key events will be captured
GitHub
. There is an alert prompting the user to enable Accessibility permissions, but it asks the user to restart the app afterward
GitHub
. This creates a hiccup in usability – until a restart, the hotkey won’t function. Additionally, if the app’s onboarding flow doesn’t call startListening() at the right time, the hotkey system might never activate (the task analysis noted that the hotkey system might not be starting at all in some cases)
GitHub
.
Transcription Not Starting/Stopping at Correct Times: Even when the hotkey is detected, we need to confirm that the microphone is activated as soon as the keys are held down and deactivated on release. Any delay in starting the audio engine or stopping it could cause missed speech or extra unwanted audio. The current implementation triggers audio start on the hotkey press delegate callback and stops on release, which is correct in design
GitHub
GitHub
. We need to verify these callbacks always fire. If the event tap issue above is resolved, the callbacks in WhisperNodeCore should properly call audioEngine.startCapture() and audioEngine.stopCapture(). If they do not, that indicates a logic bug in the delegate wiring or thread timing.
Text Insertion Reliability: After transcription, the text should be injected at the current cursor location. The code uses a TextInsertionEngine with CGEvent keyboard events to type out the result
GitHub
. If the insertion isn’t happening, it could be due to focus issues or the text being empty. We should ensure that the insertion code runs on the main thread (CGEvent posting) and that the target application is active. (The code already gets the frontmost application and posts events to type the text – this was verified as a core feature
GitHub
, but it’s worth double-checking if any edge cases prevent it from working consistently.)
Technical To-Do List – Hotkey & Transcription Fixes
Initialize the Global Hotkey Listener: Ensure that GlobalHotkeyManager.startListening() is called during app startup or immediately after onboarding. Currently, the core is designed to auto-start hotkey listening only if onboarding is complete and permissions are in place
GitHub
. In practice, this means a user who just finished onboarding might need to restart the app (as the permission prompt suggests) to activate the hotkey. To fix this:
Call startListening() as soon as the user finishes onboarding and grants accessibility permission (e.g. in the onboarding completion step, after setting hasCompletedOnboarding=true).
If the app is already running and permissions become available, start the event tap without requiring a restart. This may involve re-checking AXIsProcessTrusted() periodically or when the preferences window is closed.
Improve Accessibility Permission Handling: The app should robustly handle the Accessibility (AX) permission required for listening to global keys. The code currently uses AXIsProcessTrustedWithOptions to prompt the user
GitHub
 and shows instructions in an alert
GitHub
. We need to:
Detect if permissions are missing at launch and inform the user immediately (e.g. highlight in the UI or menu bar icon) rather than silently failing.
After the user grants permission (in System Preferences), allow the app to pick that up. For example, once the user clicks "Open System Preferences" via our prompt and checks the box, the app could periodically call AXIsProcessTrusted() in the background. When it returns true, we log a message and call startListening() automatically. This would eliminate the “please restart” requirement and make activation seamless.
Error feedback: If the user refuses permission, we should gracefully handle it (the app currently sets an error state and shows a red menu bar icon
GitHub
). We can keep the icon red and perhaps display a tooltip or menu item like “Enable Accessibility in System Settings to activate hotkey” for clarity.
Fix Modifier-Only Hotkey Logic: Adjust the logic in GlobalHotkeyManager.handleFlagsChanged(_:) so that releasing a modifier-only combo properly ends the recording. Specifically:
When the target modifiers (e.g. Control+Option) are pressed, we start recording as we do now.
When any of those modifiers are released, we should treat that as the end of the push-to-talk and finalize the recording. The current code cancels on a change in flags (if you go from both modifiers to one modifier)
GitHub
. We should remove that cancellation for this scenario. Instead, wait until all required modifiers are up, then end normally. In practice, this means the first modifier keyup event can trigger the stop. We may implement a slight delay (a few milliseconds) to see if the second modifier is released nearly simultaneously, but it might be simpler to immediately stop on the first key up of the combo.
Only cancel if the user presses an unrelated key or a completely different modifier combination while recording (an actual interruption). For example, if the hotkey is Ctrl+Opt and the user, while holding them, also presses Command – that’s likely a conflict or user error, and we can cancel in that case. But releasing one of the two modifiers is a normal part of finishing the chord and should not be treated as a cancellation.
Test this thoroughly: after the fix, holding Ctrl+Option should start recording, and whether the user lets go of both keys at once or one-after-the-other, the recording should end once both keys are up and proceed to transcription.
Verify Key Event Capture (Key Down/Up): Currently, the event tap listens for .keyDown, .keyUp, and .flagsChanged events
GitHub
GitHub
. We need to ensure that:
Key-down of a normal key + modifiers triggers start (for combos like Ctrl+Opt+Space). The code’s handleEvent checks if an event matches the configured hotkey and on .keyDown calls handleKeyDown() (which sets isRecording=true and invokes the delegate)
GitHub
GitHub
. On .keyUp, it calls handleKeyUp() to stop recording
GitHub
GitHub
. This flow should be confirmed working. If a hotkey like “Space with Ctrl+Opt” isn’t starting/stopping, there may be an issue in matchesCurrentHotkey() or in how the event flags are compared – we’d fix that by ensuring the mask cleaning logic is correct and that we consider the right flags (the code currently cleans system flags and compares exactly)
GitHub
GitHub
.
FlagsChanged for pure modifiers triggers start/stop appropriately. The matchesCurrentHotkey function has logic to handle the case where keyCode == UInt16.max (our sentinel for a modifier-only hotkey)
GitHub
. It returns true if the exact modifier flags match the configured combo. We should double-check this logic: it should only return true on a .flagsChanged event that brings the modifier state equal to the target combo (and similarly handle the all-released state). If any anomalies are found (e.g., it might return true for an unrelated key event that happens to have those modifiers in flags), refine the check to include event type or use the keyCode != 0 guard as noted in the docs
GitHub
.
No double-triggering: Ensure that pressing a hotkey doesn’t cause two start events. The code uses an internal keyDownTime to ignore repeated keyDowns until a keyUp occurs
GitHub
GitHub
. That prevents multiple triggers while holding the key, which is good. We should maintain that and ensure keyDownTime resets properly on release.
Enhance Threading for Event Tap: The CGEventTap is currently added on the main thread’s run loop (CFRunLoopAddSource on .commonModes)
GitHub
. If the main thread is ever busy (rendering UI, etc.), it’s possible keyboard events could be delayed. As a best practice, we can move the event tap listening to a dedicated thread:
Create a background thread when starting the hotkey listener, and attach the event tap’s run loop source to that thread’s run loop. This isolates key capture from the main UI thread.
The delegate callbacks (which update UI and start/stop audio) can still be dispatched to the main actor as they are now
GitHub
GitHub
, so the UI work happens on the main thread, but the actual event capturing is never blocked.
This change will improve reliability, especially under high load. (It might also allow removing the .commonModes if using a dedicated thread, since we can just run the loop normally.)
Confirm Delegate Integration for Audio Start/Stop: Once the hotkey events fire, the WhisperNodeCore (as GlobalHotkeyManagerDelegate) should handle them:
On didStartRecording: It sets isRecording=true, updates the menubar state, shows the recording indicator, and starts the audio capture engine
GitHub
GitHub
. We need to ensure audioEngine.startCapture() is indeed being called on the background Task and that any errors are handled (the code does catch exceptions and shows errors if, say, the mic is not available
GitHub
GitHub
). If audio isn’t actually starting, we investigate issues in AudioCaptureEngine (permissions or device selection), but as per the problem statement, microphone selection/permission is confirmed working.
On didCompleteRecording: It stops the audio engine and signals the transcription processing state
GitHub
. Verify that audioEngine.stopCapture() is always called when it should be (the code calls it on every normal completion and cancellation)
GitHub
GitHub
. If the orb ever stays “listening” or the mic stays on after keys are released, that indicates this callback didn’t fire or stopCapture() failed — requiring a fix.
On didCancelRecording: This is called if the recording was too short or interrupted. The implementation stops capture and hides the indicator
GitHub
GitHub
. We should ensure that a canceled recording (e.g., user tapped the hotkey super briefly or a conflict occurred) does not attempt to transcribe anything and leaves the system in a clean state (orb hidden, isRecording=false). The current code looks correct here.
Persist and Load Hotkey Settings: Confirm that the hotkey configuration is saved to user settings and restored on launch. The code uses SettingsManager to store hotkeyKeyCode and hotkeyModifierFlags, and loads them on GlobalHotkeyManager init
GitHub
GitHub
. We should:
Make sure that a modifier-only combo is represented properly. In the code, they use UInt16.max as the keyCode for “modifier-only” hotkeys
GitHub
GitHub
. This needs to round-trip to UserDefaults. For example, if a user sets Ctrl+Option (no key) in the UI, hotkeyKeyCode might be stored as 65535 (max UInt16) and flags as the two modifiers. When loading, the code should interpret that correctly and not, say, treat it as an actual key. The formatting utilities and .description appear to handle this by showing something like “⌃⌥” without a key
GitHub
.
Check that changing the hotkey in Preferences updates the active hotkey immediately. The ShortcutTab calls hotkeyManager.updateHotkey(newHotkey) which in turn stops and restarts the listener if it was active
GitHub
GitHub
. Any issues with the new hotkey not taking effect would likely lie in that update logic. We should test updating to a few different combinations (including back to default) and verifying the new combo triggers recording.
Hotkey Conflict Checks: Improve the conflict detection to avoid using a hotkey that macOS reserves:
The app already has a list of common system shortcuts to avoid (e.g. Command+Space for Spotlight, etc.)
GitHub
. We should review this list and possibly extend it. For instance, Ctrl+Option (no key) by itself typically isn’t a system shortcut, but we might consider if any accessibility features use it. It’s likely fine. However, certain function-key combos or media keys might need consideration.
The UI currently pops an alert if a conflict is detected and even suggests alternatives (e.g. it might suggest Control+Option+V instead of an unsafe combo)
GitHub
GitHub
. We should verify this works when, say, trying to set Command+Q as the hotkey (which should definitely be flagged).
If a user insists on using a conflicted hotkey (“Use Anyway”), make sure that’s handled (the code allows it via an alert button
GitHub
). We might log a warning in that case so if the user complains it doesn’t work (because macOS might consume it), we have a trace.
Text Insertion Timing: Once audio is captured and transcribed, the text injection happens in processAudioData() by calling textInsertionEngine.insertText(result.text)
GitHub
. This should occur after the whisper model finishes processing. We should confirm:
The recording indicator switches to a “processing” state on release (the code does showProcessing(0.0) with a short delay)
GitHub
, and then hides when transcription is done
GitHub
. Ensure the UI properly reflects that sequence (e.g., orb turns into a processing spinner or different color, then disappears).
The insertText function actually synthesizes key events or pasteboard insertion to input the text. Since this is core to the app’s function, verifying it on different target applications is worthwhile. For example, test in a TextEdit document, a browser address bar, a chat application, etc. If any of these fail, we may need to adjust the event tap or text injection method. (One known limitation: if no text field is focused, the text has nowhere to go – the app can’t magically know where to insert. In such cases, the behavior is undefined; we might simply do nothing. We should document to users that they need to have a text field active in whatever app they want the dictation to go to.)
If we discover the injection occasionally misses the first character or so (timing issue), a small tweak could be adding a tiny delay before insertion or ensuring the target app is frontmost (perhaps an Accessibility API call to focus the last used app, though generally the user never left it).
By addressing each of these items, we will fix the hotkey detection and transcription activation pipeline so it works reliably as designed.
Swift/macOS API Adjustments and Enhancements
Global Event Tap Configuration: The use of CGEvent.tapCreate with a session-level event tap is correct for capturing global keystrokes
GitHub
. We should ensure it’s set up with the optimal options:
Currently it’s using .cgSessionEventTap at .headInsertEventTap with .defaultTap options
GitHub
. This means our app will intercept the keys (so the system or other apps won’t see them while held, which is usually desirable for a push-to-talk key). We return nil for matching events, effectively consuming them
GitHub
GitHub
. This is fine. In some cases, developers use .listenOnly if they don’t want to interfere with the event for other apps, but here we do want to block (for example, if the hotkey were “Space”, we don’t want a space character to also appear in the active document while dictating).
No changes needed here except possibly adding more debug logging around tap creation success/failure. If the tap fails to create (returns null), we already call a delegate error
GitHub
GitHub
. We might log the value of CGEventTapCreate result or any error codes for clarity.
NSEvent Monitor Fallback: The app uses NSEvent.addGlobalMonitorForEvents(matching:) in the preferences UI when recording a new shortcut
GitHub
. Note that NSEvent global monitors do not require a separate Accessibility permission – they work as long as the app is frontmost (and in some cases even if not, since it’s read-only). However, NSEvent global monitors don’t receive keyUp events for modifiers reliably, which is why the CGEventTap is needed for the actual hotkey usage. We likely don’t need to adjust the NSEvent usage in preferences (it’s just for capturing the user’s chosen combo), but ensure we remove those monitors to avoid leaks (the code does remove them on stopRecording() in HotkeyRecorderView
GitHub
).
One thing to consider: if for some reason the CGEventTap cannot be enabled (maybe the user still hasn’t granted permission), we could choose to fall back to a global NSEvent monitor temporarily. But this would be a degraded experience (the app would only see keyDown events, and only when it’s frontmost). It’s probably not worth implementing as it defeats the purpose of a global hotkey. Better to insist on the permission.
UI Indicator (NSWindow) Level: While not directly an API “bug,” we should ensure the recording indicator window is created with the proper style and level. It should be a borderless, non-activating panel that floats above normal windows (NSWindow.Level.floating or even .statusBar level). It should also ignore mouse events so it doesn’t grab focus away from the user’s app. The code likely does this in RecordingIndicatorWindowManager (as Task T05 was completed: “floating orb with animations verified”
GitHub
). If any issues exist (e.g., orb not visible or appearing behind other windows), adjusting the window’s level and collection behavior via AppKit APIs will be necessary.
Haptic and Sound Feedback: The app uses NSHapticFeedbackManager (via a custom HapticManager) for feedback on hotkey press/release and errors. This is a nice touch, but remember that haptic feedback will only be felt on devices with a trackpad or Magic Mouse that supports it, and only if the app is active (for a menubar app, it still works, as it’s calling the feedback on the main thread). No specific API changes required, but consider adding an audible cue using NSSound or system sound for start/stop recording. Apple’s Siri uses an audible tone. This can be done by playing a short audio file or using NSSound(named:). It should respect the user’s sound settings (maybe make it optional in preferences).
Voice Activity Detection (VAD): The AudioCaptureEngine includes voice activity detection and input level monitoring. One potential improvement is to use the VAD to control the orb’s appearance (e.g., change color or animation when speech is detected vs. just background noise). The code already toggles the indicator between “recording” (active voice) and “idle” (no voice detected but still listening) states
GitHub
. We should verify that this is working: if the orb flickers or doesn’t accurately reflect speaking vs silence, we might need to tweak the VAD threshold or how often the UI updates. This is more of a UX tweak than a fundamental issue.
Whisper Model Performance: From an API perspective, using the Whisper CPP model is outside Apple’s frameworks, but we can still apply macOS best practices:
Make sure the whisper processing is on a background thread (it is, via await engine.transcribe(...) which likely runs on a global concurrent queue in the WhisperEngine implementation). As a rule, heavy CPU tasks should not run on the main thread.
The app monitors CPU and can auto-downgrade the model size if needed
GitHub
GitHub
. This is great for reliability. We should continue to use Combine or Timer-based checks to periodically assess if the system is under stress.
If memory is a concern, consider using autoreleasepool around the transcription or freeing the Whisper model from memory when not in use (if the model is large and the user isn’t actively using the app, maybe unload it after some idle time – though that adds latency when needed again).
Ensure that the AudioCaptureEngine is properly handling audio session interruptions (on macOS this is less of an issue than iOS, but if the input device changes or something, we handle the error).
Edge-case handling: Using macOS APIs, think about what happens in unusual scenarios:
If the user locks the screen while holding the hotkey (the app would stop receiving events – likely not an issue to handle explicitly).
If the user presses the hotkey during a period of high system load and there’s a slight lag – our minimum hold time of 0.1s might filter out a valid quick press if the system is sluggish. We might consider slightly increasing the tolerance or making it configurable. However, 0.1s is already quite short and should be fine.
Multi-monitor or Spaces: The orb window should ideally appear on whatever space the user is currently in (since it’s probably set as a floating panel, it should). We might want to set the window’s collectionBehavior to canJoinAllSpaces so that it’s not tied to one desktop. This is an NSWindow API flag.
Overall, most of the needed adjustments involve fine-tuning existing APIs (CGEventTap, NSWindow levels, NSAccessibility checks) rather than introducing new ones. The main thing is to use these APIs in a way that maximizes reliability (e.g., event tap on a background thread, robust permission checks, etc.) as described above.
UX and Reliability Improvements (Siri-Like Experience)
Seamless Activation: The goal is that the user can press the hotkey anytime, in any app, and immediately see feedback that the system is listening. By fixing the hotkey detection and not requiring restarts or additional clicks, we achieve this. After implementing the above fixes, test the flow as a user:
On first launch, go through onboarding, grant mic and accessibility permissions, set a hotkey, and then press it in a different app. The orb should appear and you should be transcribing – with no extra steps. This is the “it just works” experience that Apple aims for.
If anything in that flow is confusing (for instance, if the permission prompt doesn’t appear or the user accidentally denies it), add guidance. Perhaps in the onboarding “Permissions” step (which currently covers microphone), also mention enabling Accessibility for the hotkey (maybe the app already does, or perhaps it’s supposed to happen when recording the hotkey in onboarding).
Visual Indicator & Feedback: Make the recording indicator as clear and responsive as possible:
Position and appearance: Ensure the orb is not stuck in a corner or hidden. Siri on Mac shows a waveform orb at the bottom-right of the screen. Our orb could appear near the menu bar icon or center of screen – wherever it is, it should be noticeable but not intrusive. If users have multiple monitors, consider where it should show (all monitors or just main? All spaces or just current? Likely current space is enough).
Animation: If not already, add a subtle pulsing or waveform animation to indicate it’s actively listening. The code’s RecordingIndicatorWindowManager likely handles animations (perhaps resizing or a glow when voice is detected). This makes the experience feel alive and confirms to the user that speech is being picked up.
State changes: Use different visuals for listening vs processing vs error. For example, when the user releases the keys and the orb switches to “processing,” maybe change its color or show a spinner overlay. When an error occurs (like permission denied or no model), maybe flash the orb red briefly (the code does something like this via errorManager.handleTranscriptionFailure() which presumably flashes an error indicator)
GitHub
. Since the menu bar icon also changes color for errors, the orb could disappear on error (since nothing to transcribe) or likewise indicate it.
Duration: If a user holds the hotkey for an extremely long time (say, they monologue for minutes), consider how the orb behaves. It might be fine, but we should ensure the UI doesn’t start lagging. The audio buffer might recycle (circular buffer) unless we handle long recordings explicitly. Perhaps set an upper limit like 60 seconds with a gentle cutoff – Siri typically has a limit to how long it will listen. This could be a future enhancement.
User Control and Preferences: For usability:
Provide a way to easily re-trigger onboarding or permission checks if something goes wrong. Maybe a button in preferences like “Re-check Accessibility Permission” that again calls AXIsProcessTrustedWithOptions with the prompt. This could help users who skipped it the first time.
In Preferences > Shortcut tab, show a clear message if the hotkey system is inactive due to permission issues. For example, if AXIsProcessTrusted() is false, that tab could display a warning icon and message like “⚠️ Global hotkeys disabled – enable Accessibility permissions to use the voice activation hotkey.”
Possibly allow the user to choose whether the hotkey is press-and-hold or a toggle (press once to start, again to stop). The current design is strictly press-and-hold (which aligns with “like a walkie-talkie” or Siri’s old behavior when holding a button). Some users might prefer a toggle. Supporting both could be complex, but mentioning it as a future idea could be worthwhile for UX flexibility.
Performance and Responsiveness:
The app should remain lightweight when idle. The menubar icon and any background threads (like performance monitor) should not hog CPU. From the progress, core features are optimized, but we should verify that when not in use (no hotkey pressed), the audio engine isn’t running (it shouldn’t be – it starts only on hotkey and stops after) and that the whisper model isn’t consuming resources until needed. WhisperNodeCore keeps the model loaded by default (tiny.en by default)
GitHub
, which is fine.
During transcription, especially for longer audio, consider providing intermediate feedback. Whisper.cpp can sometimes provide partial results if configured to do so (streaming mode). In a Siri-like UX, the user might see words appear as they’re being recognized. Currently, WhisperNode waits until the end and then inserts all text at once. For now, that’s acceptable and probably simpler (and Whisper’s accuracy improves when processing the whole utterance). But as an enhancement, if we could stream partial text (perhaps in a floating text box near the orb) and then finalize it at release, that’d be even more Siri-like. This is a non-trivial improvement and might be left for later once stability is achieved.
Ensure the app doesn’t leak memory or file handles. Each time you start/stop audio and transcribe, memory will be used for the audio buffer and transcription result. Over many uses, that should be freed properly. Running the app through Instruments (Leaks and CPU profiler) while doing repeated activations is a good validation step for reliability.
Graceful Handling of Fast Re-activation:
As mentioned in the to-do list, if a user quickly presses the hotkey again right after releasing it (perhaps to correct themselves or say another sentence), our system should handle it. Ideally, the user can speak sentence after sentence in fairly quick succession and the app will handle each as separate transcriptions.
After finishing one transcription, there is a moment where the app is inserting text and showing the processing indicator. If the user presses the hotkey during that, two things happen in the current design: (a) The event tap will detect the hotkey (since we only set isRecording=false after release, and the tap is still active), so it will start a new recording. (b) The previous transcription might still be running in the background thread. In testing, see if starting a new recording cancels the previous processAudioData call or if they run concurrently. They might run concurrently – which could spike CPU usage.
To improve UX, we might want to block the hotkey while processing (i.e., ignore hotkey presses until the previous result is injected). Or queue them (less ideal). Siri typically doesn’t let you start a new query until the last one is done; we can mimic that. We can implement this by having a flag like isTranscribing that we set when we begin Whisper transcription and clear when done. If isTranscribing == true, the didStartRecording delegate could immediately cancel the new recording (or not even start the audioEngine) and perhaps flash the orb or play a brief “busy” sound. This might be overkill, but it’s something to consider if we find users accidentally overrunning the system. Given WhisperNode’s target is probably power users, they might not do rapid-fire requests, but it’s good to handle edge cases.
Testing Scenarios for Reliability:
Test with different key combinations: e.g., a letter key with modifiers (like Ctrl+Alt+S) vs. a function key vs. a pure modifier vs. a single key (if allowed). Ensure all behave as expected.
Test without an active internet connection (just to confirm no part of the pipeline tries to reach out – it shouldn’t, everything is local).
Test on Intel vs Apple Silicon if applicable, and on different macOS versions (the Accessibility API and event taps can sometimes have quirks on older versions).
Incorporate user feedback: once these fixes are in, if users report “it didn’t start when I pressed the keys” or “it stopped too soon” or “it typed the text in the wrong place,” use that to further refine the experience.
By implementing the above to-do list and enhancements, the Whisper Node app will become much more robust and user-friendly. The hotkey will reliably activate the microphone while held, the Siri-like orb will give immediate feedback, and upon release the transcribed text will appear at the cursor with minimal delay. These changes prioritize a seamless experience, so using Whisper Node feels as natural as a native macOS feature like Siri or Dictation. Each detail – from permission handling to visual feedback – contributes to an intuitive press-to-talk workflow that “just works” for the end user. 
GitHub
GitHub

Favicon
Sources



No file chosenNo file chosen
ChatGPT can make mistakes. OpenAI doesn't use ATT Workspace workspace data to train its models.

Hotkey Activation & Transcription – Issues and Fixes
Issues with Hotkey Detection and Activation
Global Hotkey Not Triggering: The Control+Option hotkey (or any configured combination) fails to start voice capture. This is likely due to the global event tap not running or not receiving events. In the current code, if the hotkey system isn’t initialized properly (e.g. startListening() never called) or if macOS Accessibility permission is missing, the hotkey press does nothing
GitHub
GitHub
. Symptoms include no recording orb appearing and no log output when the keys are pressed. The app needs to ensure the hotkey listener is started and has the necessary privileges.
Modifier-Only Hotkey Release Behavior: When using a modifier-only hotkey (e.g. Ctrl+Alt with no additional key), the release logic is flawed. Currently, if the user doesn’t release both keys at exactly the same time, the code treats it as an “interrupted” hotkey and cancels the transcription instead of completing it
GitHub
. For example, lifting one finger off Ctrl slightly before Alt triggers a cancellation. This prevents the intended behavior of stopping recording and processing the audio on key release.
Event Tap Setup & Permissions: The global hotkey uses a CGEventTap that requires Accessibility access. If that permission isn’t granted or if the event tap isn’t installed correctly, no key events will be captured
GitHub
. There is an alert prompting the user to enable Accessibility permissions, but it asks the user to restart the app afterward
GitHub
. This creates a hiccup in usability – until a restart, the hotkey won’t function. Additionally, if the app’s onboarding flow doesn’t call startListening() at the right time, the hotkey system might never activate (the task analysis noted that the hotkey system might not be starting at all in some cases)
GitHub
.
Transcription Not Starting/Stopping at Correct Times: Even when the hotkey is detected, we need to confirm that the microphone is activated as soon as the keys are held down and deactivated on release. Any delay in starting the audio engine or stopping it could cause missed speech or extra unwanted audio. The current implementation triggers audio start on the hotkey press delegate callback and stops on release, which is correct in design
GitHub
GitHub
. We need to verify these callbacks always fire. If the event tap issue above is resolved, the callbacks in WhisperNodeCore should properly call audioEngine.startCapture() and audioEngine.stopCapture(). If they do not, that indicates a logic bug in the delegate wiring or thread timing.
Text Insertion Reliability: After transcription, the text should be injected at the current cursor location. The code uses a TextInsertionEngine with CGEvent keyboard events to type out the result
GitHub
. If the insertion isn’t happening, it could be due to focus issues or the text being empty. We should ensure that the insertion code runs on the main thread (CGEvent posting) and that the target application is active. (The code already gets the frontmost application and posts events to type the text – this was verified as a core feature
GitHub
, but it’s worth double-checking if any edge cases prevent it from working consistently.)
Technical To-Do List – Hotkey & Transcription Fixes
Initialize the Global Hotkey Listener: Ensure that GlobalHotkeyManager.startListening() is called during app startup or immediately after onboarding. Currently, the core is designed to auto-start hotkey listening only if onboarding is complete and permissions are in place
GitHub
. In practice, this means a user who just finished onboarding might need to restart the app (as the permission prompt suggests) to activate the hotkey. To fix this:
Call startListening() as soon as the user finishes onboarding and grants accessibility permission (e.g. in the onboarding completion step, after setting hasCompletedOnboarding=true).
If the app is already running and permissions become available, start the event tap without requiring a restart. This may involve re-checking AXIsProcessTrusted() periodically or when the preferences window is closed.
Improve Accessibility Permission Handling: The app should robustly handle the Accessibility (AX) permission required for listening to global keys. The code currently uses AXIsProcessTrustedWithOptions to prompt the user
GitHub
 and shows instructions in an alert
GitHub
. We need to:
Detect if permissions are missing at launch and inform the user immediately (e.g. highlight in the UI or menu bar icon) rather than silently failing.
After the user grants permission (in System Preferences), allow the app to pick that up. For example, once the user clicks "Open System Preferences" via our prompt and checks the box, the app could periodically call AXIsProcessTrusted() in the background. When it returns true, we log a message and call startListening() automatically. This would eliminate the “please restart” requirement and make activation seamless.
Error feedback: If the user refuses permission, we should gracefully handle it (the app currently sets an error state and shows a red menu bar icon
GitHub
). We can keep the icon red and perhaps display a tooltip or menu item like “Enable Accessibility in System Settings to activate hotkey” for clarity.
Fix Modifier-Only Hotkey Logic: Adjust the logic in GlobalHotkeyManager.handleFlagsChanged(_:) so that releasing a modifier-only combo properly ends the recording. Specifically:
When the target modifiers (e.g. Control+Option) are pressed, we start recording as we do now.
When any of those modifiers are released, we should treat that as the end of the push-to-talk and finalize the recording. The current code cancels on a change in flags (if you go from both modifiers to one modifier)
GitHub
. We should remove that cancellation for this scenario. Instead, wait until all required modifiers are up, then end normally. In practice, this means the first modifier keyup event can trigger the stop. We may implement a slight delay (a few milliseconds) to see if the second modifier is released nearly simultaneously, but it might be simpler to immediately stop on the first key up of the combo.
Only cancel if the user presses an unrelated key or a completely different modifier combination while recording (an actual interruption). For example, if the hotkey is Ctrl+Opt and the user, while holding them, also presses Command – that’s likely a conflict or user error, and we can cancel in that case. But releasing one of the two modifiers is a normal part of finishing the chord and should not be treated as a cancellation.
Test this thoroughly: after the fix, holding Ctrl+Option should start recording, and whether the user lets go of both keys at once or one-after-the-other, the recording should end once both keys are up and proceed to transcription.
Verify Key Event Capture (Key Down/Up): Currently, the event tap listens for .keyDown, .keyUp, and .flagsChanged events
GitHub
GitHub
. We need to ensure that:
Key-down of a normal key + modifiers triggers start (for combos like Ctrl+Opt+Space). The code’s handleEvent checks if an event matches the configured hotkey and on .keyDown calls handleKeyDown() (which sets isRecording=true and invokes the delegate)
GitHub
GitHub
. On .keyUp, it calls handleKeyUp() to stop recording
GitHub
GitHub
. This flow should be confirmed working. If a hotkey like “Space with Ctrl+Opt” isn’t starting/stopping, there may be an issue in matchesCurrentHotkey() or in how the event flags are compared – we’d fix that by ensuring the mask cleaning logic is correct and that we consider the right flags (the code currently cleans system flags and compares exactly)
GitHub
GitHub
.
FlagsChanged for pure modifiers triggers start/stop appropriately. The matchesCurrentHotkey function has logic to handle the case where keyCode == UInt16.max (our sentinel for a modifier-only hotkey)
GitHub
. It returns true if the exact modifier flags match the configured combo. We should double-check this logic: it should only return true on a .flagsChanged event that brings the modifier state equal to the target combo (and similarly handle the all-released state). If any anomalies are found (e.g., it might return true for an unrelated key event that happens to have those modifiers in flags), refine the check to include event type or use the keyCode != 0 guard as noted in the docs
GitHub
.
No double-triggering: Ensure that pressing a hotkey doesn’t cause two start events. The code uses an internal keyDownTime to ignore repeated keyDowns until a keyUp occurs
GitHub
GitHub
. That prevents multiple triggers while holding the key, which is good. We should maintain that and ensure keyDownTime resets properly on release.
Enhance Threading for Event Tap: The CGEventTap is currently added on the main thread’s run loop (CFRunLoopAddSource on .commonModes)
GitHub
. If the main thread is ever busy (rendering UI, etc.), it’s possible keyboard events could be delayed. As a best practice, we can move the event tap listening to a dedicated thread:
Create a background thread when starting the hotkey listener, and attach the event tap’s run loop source to that thread’s run loop. This isolates key capture from the main UI thread.
The delegate callbacks (which update UI and start/stop audio) can still be dispatched to the main actor as they are now
GitHub
GitHub
, so the UI work happens on the main thread, but the actual event capturing is never blocked.
This change will improve reliability, especially under high load. (It might also allow removing the .commonModes if using a dedicated thread, since we can just run the loop normally.)
Confirm Delegate Integration for Audio Start/Stop: Once the hotkey events fire, the WhisperNodeCore (as GlobalHotkeyManagerDelegate) should handle them:
On didStartRecording: It sets isRecording=true, updates the menubar state, shows the recording indicator, and starts the audio capture engine
GitHub
GitHub
. We need to ensure audioEngine.startCapture() is indeed being called on the background Task and that any errors are handled (the code does catch exceptions and shows errors if, say, the mic is not available
GitHub
GitHub
). If audio isn’t actually starting, we investigate issues in AudioCaptureEngine (permissions or device selection), but as per the problem statement, microphone selection/permission is confirmed working.
On didCompleteRecording: It stops the audio engine and signals the transcription processing state
GitHub
. Verify that audioEngine.stopCapture() is always called when it should be (the code calls it on every normal completion and cancellation)
GitHub
GitHub
. If the orb ever stays “listening” or the mic stays on after keys are released, that indicates this callback didn’t fire or stopCapture() failed — requiring a fix.
On didCancelRecording: This is called if the recording was too short or interrupted. The implementation stops capture and hides the indicator
GitHub
GitHub
. We should ensure that a canceled recording (e.g., user tapped the hotkey super briefly or a conflict occurred) does not attempt to transcribe anything and leaves the system in a clean state (orb hidden, isRecording=false). The current code looks correct here.
Persist and Load Hotkey Settings: Confirm that the hotkey configuration is saved to user settings and restored on launch. The code uses SettingsManager to store hotkeyKeyCode and hotkeyModifierFlags, and loads them on GlobalHotkeyManager init
GitHub
GitHub
. We should:
Make sure that a modifier-only combo is represented properly. In the code, they use UInt16.max as the keyCode for “modifier-only” hotkeys
GitHub
GitHub
. This needs to round-trip to UserDefaults. For example, if a user sets Ctrl+Option (no key) in the UI, hotkeyKeyCode might be stored as 65535 (max UInt16) and flags as the two modifiers. When loading, the code should interpret that correctly and not, say, treat it as an actual key. The formatting utilities and .description appear to handle this by showing something like “⌃⌥” without a key
GitHub
.
Check that changing the hotkey in Preferences updates the active hotkey immediately. The ShortcutTab calls hotkeyManager.updateHotkey(newHotkey) which in turn stops and restarts the listener if it was active
GitHub
GitHub
. Any issues with the new hotkey not taking effect would likely lie in that update logic. We should test updating to a few different combinations (including back to default) and verifying the new combo triggers recording.
Hotkey Conflict Checks: Improve the conflict detection to avoid using a hotkey that macOS reserves:
The app already has a list of common system shortcuts to avoid (e.g. Command+Space for Spotlight, etc.)
GitHub
. We should review this list and possibly extend it. For instance, Ctrl+Option (no key) by itself typically isn’t a system shortcut, but we might consider if any accessibility features use it. It’s likely fine. However, certain function-key combos or media keys might need consideration.
The UI currently pops an alert if a conflict is detected and even suggests alternatives (e.g. it might suggest Control+Option+V instead of an unsafe combo)
GitHub
GitHub
. We should verify this works when, say, trying to set Command+Q as the hotkey (which should definitely be flagged).
If a user insists on using a conflicted hotkey (“Use Anyway”), make sure that’s handled (the code allows it via an alert button
GitHub
). We might log a warning in that case so if the user complains it doesn’t work (because macOS might consume it), we have a trace.
Text Insertion Timing: Once audio is captured and transcribed, the text injection happens in processAudioData() by calling textInsertionEngine.insertText(result.text)
GitHub
. This should occur after the whisper model finishes processing. We should confirm:
The recording indicator switches to a “processing” state on release (the code does showProcessing(0.0) with a short delay)
GitHub
, and then hides when transcription is done
GitHub
. Ensure the UI properly reflects that sequence (e.g., orb turns into a processing spinner or different color, then disappears).
The insertText function actually synthesizes key events or pasteboard insertion to input the text. Since this is core to the app’s function, verifying it on different target applications is worthwhile. For example, test in a TextEdit document, a browser address bar, a chat application, etc. If any of these fail, we may need to adjust the event tap or text injection method. (One known limitation: if no text field is focused, the text has nowhere to go – the app can’t magically know where to insert. In such cases, the behavior is undefined; we might simply do nothing. We should document to users that they need to have a text field active in whatever app they want the dictation to go to.)
If we discover the injection occasionally misses the first character or so (timing issue), a small tweak could be adding a tiny delay before insertion or ensuring the target app is frontmost (perhaps an Accessibility API call to focus the last used app, though generally the user never left it).
By addressing each of these items, we will fix the hotkey detection and transcription activation pipeline so it works reliably as designed.
Swift/macOS API Adjustments and Enhancements
Global Event Tap Configuration: The use of CGEvent.tapCreate with a session-level event tap is correct for capturing global keystrokes
GitHub
. We should ensure it’s set up with the optimal options:
Currently it’s using .cgSessionEventTap at .headInsertEventTap with .defaultTap options
GitHub
. This means our app will intercept the keys (so the system or other apps won’t see them while held, which is usually desirable for a push-to-talk key). We return nil for matching events, effectively consuming them
GitHub
GitHub
. This is fine. In some cases, developers use .listenOnly if they don’t want to interfere with the event for other apps, but here we do want to block (for example, if the hotkey were “Space”, we don’t want a space character to also appear in the active document while dictating).
No changes needed here except possibly adding more debug logging around tap creation success/failure. If the tap fails to create (returns null), we already call a delegate error
GitHub
GitHub
. We might log the value of CGEventTapCreate result or any error codes for clarity.
NSEvent Monitor Fallback: The app uses NSEvent.addGlobalMonitorForEvents(matching:) in the preferences UI when recording a new shortcut
GitHub
. Note that NSEvent global monitors do not require a separate Accessibility permission – they work as long as the app is frontmost (and in some cases even if not, since it’s read-only). However, NSEvent global monitors don’t receive keyUp events for modifiers reliably, which is why the CGEventTap is needed for the actual hotkey usage. We likely don’t need to adjust the NSEvent usage in preferences (it’s just for capturing the user’s chosen combo), but ensure we remove those monitors to avoid leaks (the code does remove them on stopRecording() in HotkeyRecorderView
GitHub
).
One thing to consider: if for some reason the CGEventTap cannot be enabled (maybe the user still hasn’t granted permission), we could choose to fall back to a global NSEvent monitor temporarily. But this would be a degraded experience (the app would only see keyDown events, and only when it’s frontmost). It’s probably not worth implementing as it defeats the purpose of a global hotkey. Better to insist on the permission.
UI Indicator (NSWindow) Level: While not directly an API “bug,” we should ensure the recording indicator window is created with the proper style and level. It should be a borderless, non-activating panel that floats above normal windows (NSWindow.Level.floating or even .statusBar level). It should also ignore mouse events so it doesn’t grab focus away from the user’s app. The code likely does this in RecordingIndicatorWindowManager (as Task T05 was completed: “floating orb with animations verified”
GitHub
). If any issues exist (e.g., orb not visible or appearing behind other windows), adjusting the window’s level and collection behavior via AppKit APIs will be necessary.
Haptic and Sound Feedback: The app uses NSHapticFeedbackManager (via a custom HapticManager) for feedback on hotkey press/release and errors. This is a nice touch, but remember that haptic feedback will only be felt on devices with a trackpad or Magic Mouse that supports it, and only if the app is active (for a menubar app, it still works, as it’s calling the feedback on the main thread). No specific API changes required, but consider adding an audible cue using NSSound or system sound for start/stop recording. Apple’s Siri uses an audible tone. This can be done by playing a short audio file or using NSSound(named:). It should respect the user’s sound settings (maybe make it optional in preferences).
Voice Activity Detection (VAD): The AudioCaptureEngine includes voice activity detection and input level monitoring. One potential improvement is to use the VAD to control the orb’s appearance (e.g., change color or animation when speech is detected vs. just background noise). The code already toggles the indicator between “recording” (active voice) and “idle” (no voice detected but still listening) states
GitHub
. We should verify that this is working: if the orb flickers or doesn’t accurately reflect speaking vs silence, we might need to tweak the VAD threshold or how often the UI updates. This is more of a UX tweak than a fundamental issue.
Whisper Model Performance: From an API perspective, using the Whisper CPP model is outside Apple’s frameworks, but we can still apply macOS best practices:
Make sure the whisper processing is on a background thread (it is, via await engine.transcribe(...) which likely runs on a global concurrent queue in the WhisperEngine implementation). As a rule, heavy CPU tasks should not run on the main thread.
The app monitors CPU and can auto-downgrade the model size if needed
GitHub
GitHub
. This is great for reliability. We should continue to use Combine or Timer-based checks to periodically assess if the system is under stress.
If memory is a concern, consider using autoreleasepool around the transcription or freeing the Whisper model from memory when not in use (if the model is large and the user isn’t actively using the app, maybe unload it after some idle time – though that adds latency when needed again).
Ensure that the AudioCaptureEngine is properly handling audio session interruptions (on macOS this is less of an issue than iOS, but if the input device changes or something, we handle the error).
Edge-case handling: Using macOS APIs, think about what happens in unusual scenarios:
If the user locks the screen while holding the hotkey (the app would stop receiving events – likely not an issue to handle explicitly).
If the user presses the hotkey during a period of high system load and there’s a slight lag – our minimum hold time of 0.1s might filter out a valid quick press if the system is sluggish. We might consider slightly increasing the tolerance or making it configurable. However, 0.1s is already quite short and should be fine.
Multi-monitor or Spaces: The orb window should ideally appear on whatever space the user is currently in (since it’s probably set as a floating panel, it should). We might want to set the window’s collectionBehavior to canJoinAllSpaces so that it’s not tied to one desktop. This is an NSWindow API flag.
Overall, most of the needed adjustments involve fine-tuning existing APIs (CGEventTap, NSWindow levels, NSAccessibility checks) rather than introducing new ones. The main thing is to use these APIs in a way that maximizes reliability (e.g., event tap on a background thread, robust permission checks, etc.) as described above.
UX and Reliability Improvements (Siri-Like Experience)
Seamless Activation: The goal is that the user can press the hotkey anytime, in any app, and immediately see feedback that the system is listening. By fixing the hotkey detection and not requiring restarts or additional clicks, we achieve this. After implementing the above fixes, test the flow as a user:
On first launch, go through onboarding, grant mic and accessibility permissions, set a hotkey, and then press it in a different app. The orb should appear and you should be transcribing – with no extra steps. This is the “it just works” experience that Apple aims for.
If anything in that flow is confusing (for instance, if the permission prompt doesn’t appear or the user accidentally denies it), add guidance. Perhaps in the onboarding “Permissions” step (which currently covers microphone), also mention enabling Accessibility for the hotkey (maybe the app already does, or perhaps it’s supposed to happen when recording the hotkey in onboarding).
Visual Indicator & Feedback: Make the recording indicator as clear and responsive as possible:
Position and appearance: Ensure the orb is not stuck in a corner or hidden. Siri on Mac shows a waveform orb at the bottom-right of the screen. Our orb could appear near the menu bar icon or center of screen – wherever it is, it should be noticeable but not intrusive. If users have multiple monitors, consider where it should show (all monitors or just main? All spaces or just current? Likely current space is enough).
Animation: If not already, add a subtle pulsing or waveform animation to indicate it’s actively listening. The code’s RecordingIndicatorWindowManager likely handles animations (perhaps resizing or a glow when voice is detected). This makes the experience feel alive and confirms to the user that speech is being picked up.
State changes: Use different visuals for listening vs processing vs error. For example, when the user releases the keys and the orb switches to “processing,” maybe change its color or show a spinner overlay. When an error occurs (like permission denied or no model), maybe flash the orb red briefly (the code does something like this via errorManager.handleTranscriptionFailure() which presumably flashes an error indicator)
GitHub
. Since the menu bar icon also changes color for errors, the orb could disappear on error (since nothing to transcribe) or likewise indicate it.
Duration: If a user holds the hotkey for an extremely long time (say, they monologue for minutes), consider how the orb behaves. It might be fine, but we should ensure the UI doesn’t start lagging. The audio buffer might recycle (circular buffer) unless we handle long recordings explicitly. Perhaps set an upper limit like 60 seconds with a gentle cutoff – Siri typically has a limit to how long it will listen. This could be a future enhancement.
User Control and Preferences: For usability:
Provide a way to easily re-trigger onboarding or permission checks if something goes wrong. Maybe a button in preferences like “Re-check Accessibility Permission” that again calls AXIsProcessTrustedWithOptions with the prompt. This could help users who skipped it the first time.
In Preferences > Shortcut tab, show a clear message if the hotkey system is inactive due to permission issues. For example, if AXIsProcessTrusted() is false, that tab could display a warning icon and message like “⚠️ Global hotkeys disabled – enable Accessibility permissions to use the voice activation hotkey.”
Possibly allow the user to choose whether the hotkey is press-and-hold or a toggle (press once to start, again to stop). The current design is strictly press-and-hold (which aligns with “like a walkie-talkie” or Siri’s old behavior when holding a button). Some users might prefer a toggle. Supporting both could be complex, but mentioning it as a future idea could be worthwhile for UX flexibility.
Performance and Responsiveness:
The app should remain lightweight when idle. The menubar icon and any background threads (like performance monitor) should not hog CPU. From the progress, core features are optimized, but we should verify that when not in use (no hotkey pressed), the audio engine isn’t running (it shouldn’t be – it starts only on hotkey and stops after) and that the whisper model isn’t consuming resources until needed. WhisperNodeCore keeps the model loaded by default (tiny.en by default)
GitHub
, which is fine.
During transcription, especially for longer audio, consider providing intermediate feedback. Whisper.cpp can sometimes provide partial results if configured to do so (streaming mode). In a Siri-like UX, the user might see words appear as they’re being recognized. Currently, WhisperNode waits until the end and then inserts all text at once. For now, that’s acceptable and probably simpler (and Whisper’s accuracy improves when processing the whole utterance). But as an enhancement, if we could stream partial text (perhaps in a floating text box near the orb) and then finalize it at release, that’d be even more Siri-like. This is a non-trivial improvement and might be left for later once stability is achieved.
Ensure the app doesn’t leak memory or file handles. Each time you start/stop audio and transcribe, memory will be used for the audio buffer and transcription result. Over many uses, that should be freed properly. Running the app through Instruments (Leaks and CPU profiler) while doing repeated activations is a good validation step for reliability.
Graceful Handling of Fast Re-activation:
As mentioned in the to-do list, if a user quickly presses the hotkey again right after releasing it (perhaps to correct themselves or say another sentence), our system should handle it. Ideally, the user can speak sentence after sentence in fairly quick succession and the app will handle each as separate transcriptions.
After finishing one transcription, there is a moment where the app is inserting text and showing the processing indicator. If the user presses the hotkey during that, two things happen in the current design: (a) The event tap will detect the hotkey (since we only set isRecording=false after release, and the tap is still active), so it will start a new recording. (b) The previous transcription might still be running in the background thread. In testing, see if starting a new recording cancels the previous processAudioData call or if they run concurrently. They might run concurrently – which could spike CPU usage.
To improve UX, we might want to block the hotkey while processing (i.e., ignore hotkey presses until the previous result is injected). Or queue them (less ideal). Siri typically doesn’t let you start a new query until the last one is done; we can mimic that. We can implement this by having a flag like isTranscribing that we set when we begin Whisper transcription and clear when done. If isTranscribing == true, the didStartRecording delegate could immediately cancel the new recording (or not even start the audioEngine) and perhaps flash the orb or play a brief “busy” sound. This might be overkill, but it’s something to consider if we find users accidentally overrunning the system. Given WhisperNode’s target is probably power users, they might not do rapid-fire requests, but it’s good to handle edge cases.
Testing Scenarios for Reliability:
Test with different key combinations: e.g., a letter key with modifiers (like Ctrl+Alt+S) vs. a function key vs. a pure modifier vs. a single key (if allowed). Ensure all behave as expected.
Test without an active internet connection (just to confirm no part of the pipeline tries to reach out – it shouldn’t, everything is local).
Test on Intel vs Apple Silicon if applicable, and on different macOS versions (the Accessibility API and event taps can sometimes have quirks on older versions).
Incorporate user feedback: once these fixes are in, if users report “it didn’t start when I pressed the keys” or “it stopped too soon” or “it typed the text in the wrong place,” use that to further refine the experience.
By implementing the above to-do list and enhancements, the Whisper Node app will become much more robust and user-friendly. The hotkey will reliably activate the microphone while held, the Siri-like orb will give immediate feedback, and upon release the transcribed text will appear at the cursor with minimal delay. These changes prioritize a seamless experience, so using Whisper Node feels as natural as a native macOS feature like Siri or Dictation. Each detail – from permission handling to visual feedback – contributes to an intuitive press-to-talk workflow that “just works” for the end user. 
