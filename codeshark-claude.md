# WhisperNode - Security, Performance & Best Practices

## Project Context
macOS voice dictation utility (Swift + Rust) - blazingly fast, privacy-first speech-to-text with press-and-hold activation for developers and power users.

## 🔒 Security & Privacy Essentials

### Audio Privacy
- Never store or transmit audio data - process entirely on-device
- Clear audio buffers immediately after transcription
- No cloud services, telemetry, or data collection
- Implement secure audio buffer management with proper cleanup

### System Permissions
- Request minimal required permissions (microphone, accessibility)
- Validate accessibility permission before CGEventTap operations
- Handle permission denials gracefully with clear user guidance
- Never escalate privileges beyond what's documented

### Hotkey Security
- Validate CGEventTap events to prevent injection attacks
- Implement proper event filtering for security
- Sanitize text before insertion via CGEventCreateKeyboardEvent
- Rate limit text insertion to prevent system abuse

## ⚡ Performance Optimization

### Real-Time Transcription
- Target ≤1s latency for 5s utterances, ≤2s for 15s
- Optimize whisper.cpp model loading and inference
- Implement efficient circular audio buffer (16kHz mono)
- Use Apple Silicon optimizations for ML inference

### Memory Management
- Keep idle memory ≤100MB, peak ≤700MB with small.en model
- Implement proper model cleanup when switching
- Monitor Core Audio buffer allocations
- Use ARC efficiently in Swift audio processing

### Battery & CPU Optimization
- Maintain <150% CPU utilization during active transcription
- Implement smart power management for background operation
- Optimize Rust FFI calls to minimize overhead
- Profile energy usage with Instruments

## 💻 Code Best Practices

### Swift Standards
- Follow Apple's Swift API Design Guidelines
- Use proper error handling with Result types
- Implement comprehensive logging with os_log
- Avoid force unwrapping - use guard/if let patterns

### Rust FFI Integration
- Use proper memory management across Swift-Rust boundary
- Implement thread-safe audio processing
- Handle FFI errors gracefully with proper Swift error translation
- Profile Rust code for memory leaks and performance

### Audio Processing Architecture
- Separate concerns: capture, processing, transcription, insertion
- Use actors for thread-safe audio state management
- Implement proper Core Audio callback handling
- Follow single responsibility principle for audio components

## 🚨 Critical System Integration Issues

### Accessibility Permissions (CRITICAL)
- Detect and handle accessibility permission denial gracefully
- Provide clear instructions for enabling CGEventTap access
- Test permission flow on clean macOS installations
- Implement fallback modes when permissions unavailable

### Audio System Integration
- Handle Core Audio interruptions and device changes
- Implement proper microphone permission handling
- Test with various audio devices and sample rates
- Recover gracefully from audio system errors

### Text Insertion Reliability
- Ensure text insertion works across all major macOS apps
- Handle special characters and Unicode properly
- Test with various keyboard layouts and input methods
- Implement retry logic for failed text insertion

## 🎯 Performance Targets

### Transcription Latency
- 5-second utterance: <1s processing time
- 15-second utterance: <2s processing time
- Model loading: <3s for small.en model
- Cold start: <5s from launch to ready

### Resource Usage
- Idle memory: <100MB
- Peak memory: <700MB (with small.en model)
- CPU usage: <150% during active transcription
- App bundle size: <200MB including tiny.en model

## 🔧 Testing Strategy

### Unit Tests
- Test audio processing pipeline with synthetic data
- Validate Rust FFI bindings and memory management
- Test text insertion with various character encodings
- Test error handling for system permission failures

### Integration Tests
- Test complete dictation flow: hotkey → audio → transcription → insertion
- Validate model switching and memory cleanup
- Test across major macOS applications (VS Code, Slack, Safari)
- Test with various Whisper models and audio qualities

### Performance Testing
- Use Instruments for CPU, memory, and energy profiling
- Test transcription accuracy with LibriSpeech dataset
- Validate real-time performance under system load
- Test on various Apple Silicon configurations (M1, M2, M3)

## 📱 Accessibility & UX

### VoiceOver Support
- Ensure all UI elements have proper accessibility labels
- Test preferences window with VoiceOver navigation
- Provide audio feedback for transcription states
- Support keyboard-only navigation

### Visual Feedback
- Implement clear visual states for dictation orb (idle, listening, processing)
- Use system colors for proper dark/light mode support
- Ensure sufficient contrast for status indicators
- Provide clear error messaging with actionable solutions

## 🚀 Release Checklist

### Pre-Release
- [ ] Run Swift tests and build validation
- [ ] Test core dictation functionality across major apps
- [ ] Validate memory usage and performance benchmarks
- [ ] Test model downloading and switching
- [ ] Verify code signing and notarization

### Post-Release
- [ ] Test installation on clean macOS systems
- [ ] Verify accessibility permission prompts work correctly
- [ ] Test automatic updates (if implemented)
- [ ] Monitor crash reports and performance metrics
- [ ] Validate whisper.cpp model integrity

## 📊 Monitoring & Diagnostics

### Key Metrics
- Transcription accuracy (target: ≥95% WER on LibriSpeech)
- Average transcription latency
- Memory usage patterns and leaks
- System permission success rates
- Crash frequency and error patterns

### Diagnostic Tools
- Instruments for performance profiling
- Console.app for system integration debugging
- Activity Monitor for resource usage validation
- Xcode's memory graph debugger for leak detection
- Custom logging for audio processing pipeline

---

## 🤖 CodeShark Review Process

When reviewing PRs for WhisperNode, focus on:

### Phase 1: Analysis
1. **Understand Changes**: What dictation functionality is being added/modified?
2. **Privacy & Security Check**: Audio handling, system permissions, data retention
3. **Performance Impact**: Memory usage, transcription latency, CPU utilization
4. **System Integration**: macOS compatibility, accessibility, text insertion reliability

### Phase 2: Review Output Format

```markdown
## WhisperNode: CodeShark Review 🎙️

**PR Summary & Overall Assessment:**
*(1-3 sentence high-level summary of the PR's purpose and most significant findings)*

**Key Recommendations (TL;DR):**
*(Bulleted list of 2-4 most critical actions)*
* Example: Fix accessibility permission detection preventing hotkey activation
* Example: Optimize audio buffer management to reduce memory usage
* Example: Improve transcription accuracy for technical terminology

---

### 🚀 **Positive Reinforcement & Well-Implemented Aspects**
*(1-3 points highlighting good practices - fosters positive review environment)*
* Example: Excellent audio buffer management with proper cleanup
* Example: Proper Swift error handling for system integration
* Example: Well-structured Rust FFI with memory safety

---

### 🚨 **Critical Issues (Must Be Addressed Before Merge)**
**Total Critical Issues: X**

<details>
<summary>File: `path/to/file.ext` (Y critical issues)</summary>

**Issue #C1: [Concise Title of Critical Issue]**
Severity: **Critical**
Category: `security`/`functionality`/`performance`/`accessibility`
Line(s): `L10-L15`

**Description**:
Clear explanation of the issue and why it's critical for this biomarker converter.

**Impact**:
Potential consequences (e.g., "Audio data retention could compromise user privacy")

**Suggested Solution**:
```diff
- old_problematic_code;
+ new_suggested_code;
```

**Further Explanation/References**:
(Optional: Links to documentation or best practices)

-----

</details>

---

### ⚠️ **Potential Issues & Areas for Improvement (Recommended Fixes)**
**Total Potential Issues: X**

<details>
<summary>File: `path/to/file.ext` (Y potential issues)</summary>

**Issue #P1: [Concise Title of Potential Issue]**
Severity: **High / Medium**
Category: `seo`/`performance`/`user-experience`/`code-quality`
Line(s): `L20-L25`

**Description**:
Explanation of the issue and why it matters for the biomarker converter.

**Impact**:
How this affects users or system performance.

**Suggested Solution**:
```diff
- old_code;
+ improved_code;
```

-----

</details>

---

### 🧹 **Nitpicks & Minor Suggestions (Non-Blocking)**
**Total Nitpicks: X**

<details>
<summary>File: `path/to/file.ext` (Y nitpicks)</summary>

**Suggestion #N1: [Concise Title of Nitpick]**
Severity: **Low / Nitpick**
Category: `documentation`/`naming`/`style`
Line(s): `L30`

**Description**:
Brief explanation of minor improvement.

**Suggested Solution**:
```diff
- old_code_snippet;
+ improved_code_snippet;
```

-----

</details>

---

### 🧐 **Questions for the Author**

**Technical:**
1. `path/to/file.ext:LXX`: Could you clarify the audio processing algorithm changes?
2. How does this change affect transcription accuracy or latency?

**Performance & Privacy:**
3. Have you validated memory usage with the new model?
4. Does this change affect audio data handling or cleanup?

---

### 📋 **Comprehensive Analysis Sections**

1. **Audio Processing Review**:
   *(Assessment of transcription accuracy and audio handling)*

2. **Privacy & Security Assessment**:
   *(Audio data handling, system permissions, local processing)*

3. **System Integration Impact**:
   *(macOS compatibility, accessibility, text insertion)*

4. **Performance Analysis**:
   *(Memory usage, transcription latency, CPU utilization)*

5. **User Experience Check**:
   *(VoiceOver support, visual feedback, error handling)*

6. **Code Quality**:
   *(Swift/Rust best practices, FFI safety, maintainability)*

---

### **Severity Classifications**

* **critical**: Blocking issues - broken dictation, privacy violations, system crashes. **Must fix before merge.**
* **high**: Significant issues - performance degradation, accessibility problems, permission handling issues. **Strongly recommended to fix.**
* **medium**: Moderate issues - code quality concerns, minor UX problems, transcription accuracy issues. **Recommended to fix.**
* **low**: Minor issues - documentation gaps, logging improvements, small style inconsistencies. **Good to fix for polish.**
* **nitpick**: Trivial suggestions - very minor naming or formatting improvements. **Consider if time permits.**
```

### Key Review Priorities
1. **Privacy First** - Ensure no audio data retention or transmission
2. **System Integration** - Validate macOS compatibility and permissions
3. **Performance** - Maintain real-time transcription targets
4. **Accuracy** - Preserve or improve transcription quality
5. **User Experience** - Support developers and power users efficiently

---

*Keep it blazingly fast, privacy-focused, and developer-friendly. Optimize for press-and-hold workflow.*

