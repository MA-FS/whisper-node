# Whisper Node - Product Requirements Document

## 0. Purpose

Deliver a blazingly fast, resource-light macOS utility that converts speech to text entirely on-device, aimed at developers and power users who prefer keyboard-style "press-and-hold" voice input. Version 1 intentionally limits scope to guarantee speed, stability, and an ultra-clean user experience.

## 1. Target Audience

| Segment | Needs | Priority |
|---------|-------|----------|
| Developers / Engineers | Hands-free code dictation, quick snippets, IDE control | ★★★ |
| Technical writers & power users | Accurate prose dictation in editors, email, chats | ★★☆ |
| Privacy-conscious users | 100% offline, no telemetry | ★★☆ |

## 2. Core Use Cases

- **Voice-to-cursor**: User holds a hotkey, speaks, releases, and sees text appear where the caret is.
- **Context-agnostic insertion**: Works in any macOS text field (VS Code, Slack, Safari, etc.).
- **Rapid micro-dictation**: Latency small enough that speaking short commands feels instantaneous.

## 3. Functional Requirements

| Ref | Feature | Description | Must/Should |
|-----|---------|-------------|-------------|
| F-1 | Hotkey activation | Single global shortcut (customisable) starts/stops capture while pressed. | Must |
| F-2 | Visual indicator | Semi-transparent animated orb, bottom-right by default; colour shift or pulse while recording; fades out on completion. | Must |
| F-3 | Local model picker | UI to download, update, select, and delete Whisper-family models optimised for Apple Silicon (e.g., tiny.en, distil-medium.en, faster-whisper-small.en). | Must |
| F-4 | Insertion engine | Transcription inserted at caret with smart punctuation, capitalisation, and user dictionary overrides. | Must |
| F-5 | Menu-bar app | Runs headless (no Dock icon unless toggled), preferences accessible from menu-bar. | Must |
| F-6 | Microphone selection | Input device chooser with live input level meter. | Should |
| F-7 | Launch at login toggle | Persistent via SMLoginItem (Apple-recommended). | Should |
| F-8 | Error handling | Clear error states with user-friendly messaging and recovery options. | Must |
| F-9 | Model management | Download progress, storage usage display, and model deletion UI. | Must |
| F-10 | Keyboard shortcut customization | Global hotkey recorder with conflict detection. | Should |
| F-11 | First-run onboarding | Microphone permission request and initial setup wizard. | Must |

## 4. Non-Functional Requirements

| Category | Requirement | Target |
|----------|-------------|--------|
| **Performance** | Latency ≤ 1s for utterances ≤ 5 seconds on M1 Air; ≤ 2s for ≥ 15 seconds. | P0 |
| | Idle RAM ≤ 100 MB; peak RAM ≤ 700 MB with small.en model. | P0 |
| **Battery impact** | Average CPU < 150% core utilisation during transcription. | P1 |
| **Security & privacy** | No network calls; all model downloads signed and checksum-verified. | P0 |
| **Accessibility** | VoiceOver-labelled controls; high-contrast orb option. | P1 |
| **Internationalisation** | UI strings externalised; only English ASR model shipped in v1. | P2 |

## 5. User Experience

**Aesthetic**: Native macOS translucency, SF Symbols, subtle haptics on Macs with Force Touch trackpads.

**Visual Design Specifications**:
- **Orb dimensions**: 80pt diameter at 1x scale (160pt on Retina)
- **Positioning**: 24pt from bottom edge, 24pt from right edge of screen
- **Colors**: 
  - Idle state: `systemBlue` with 70% opacity (#007AFF70)
  - Recording state: `systemBlue` with 85% opacity, gentle pulse animation
  - Processing state: Progress ring in `systemBlue` (#007AFF)
  - Error state: `systemRed` with 70% opacity (#FF3B3070)
- **Animations**: 
  - Appear/disappear: 0.3s ease-in-out
  - Pulse during recording: 1.2s ease-in-out, infinite
  - Progress ring: 0.8s linear sweep
- **Blur effect**: `NSVisualEffectView` with `.hudWindow` material

**Indicator behaviour**:
- Idle → hidden
- Hotkey down → orb appears with fade-in, begins gentle pulse
- Recording → pulse continues, orb brightens to 85% opacity
- Processing → pulse stops, progress ring sweeps clockwise once
- Complete → orb fades out over 0.5s
- Error → orb flashes red briefly, then fades

**Theme Support**:
- Light mode: Blue orb on light blur background
- Dark mode: Blue orb on dark blur background  
- Auto-follows system appearance setting
- High contrast mode: Increased opacity to 90%, sharper edges

**Menu Bar Integration**:
- Icon: 16x16pt microphone SF Symbol (`mic.fill`)
- States: Normal (black/white), Recording (blue), Error (red)
- Dropdown: 240pt wide, dynamic height based on content

**Settings panes**: General • Voice • Models • Shortcut • About (Sparkle update check lives here).

**Interaction Patterns**:
- **Hotkey behavior**: Press and hold to record, release to process. No click-to-start mode in v1.
- **Text insertion**: Always inserts at current cursor position, no selection replacement.
- **Model switching**: Requires app restart if switching between different model sizes.
- **Microphone permission**: If denied, show alert with System Preferences deeplink.
- **Audio level meter**: Real-time visualization in Voice preferences, 60fps update rate.
- **Shortcut conflicts**: Detect conflicts with system shortcuts, prompt user to choose alternative.

**Error States & Recovery**:
- **No microphone access**: Alert with "Open System Preferences" button
- **Model download failure**: Retry button with automatic fallback to smaller model
- **Transcription failure**: Silent failure with brief red orb flash, no modal dialogs
- **Hotkey conflicts**: Non-blocking notification in preferences with suggestion
- **Low disk space**: Warning when <1GB available, prevent new model downloads

**Accessibility Features**:
- **VoiceOver**: All controls labeled, orb announced as "Recording indicator"
- **Keyboard navigation**: Full keyboard control of preferences window
- **High contrast**: Orb opacity increases to 90%, sharper visual definition  
- **Reduced motion**: Disable pulse animations, use static color changes only
- **Text size**: Preferences UI scales with system text size settings

## 6. Technical Architecture

| Layer | Choice | Rationale |
|-------|--------|-----------|
| **UI** | SwiftUI | Minimal bundle size, fluid animations, Ventura+ native. |
| **Core logic** | Swift + Rust FFI | Swift for macOS APIs; Rust for whisper.cpp bindings gives top-tier Apple Silicon performance. |
| **Audio capture** | AVAudioEngine with a circular buffer (16 kHz mono). | Low latency, system-level permission prompts. |
| **Model inference** | whisper.cpp compiled with -mfpu=neon + -march=armv8.2-a. | Pure CPU, no Metal dependency, predictable footprint. |
| **Packaging** | Xcode's App Bundle + signed .dmg via create-dmg script. | Gatekeeper compliance. |

**Implementation Details**:
- **Global hotkey registration**: `CGEventTap` with `kCGEventTapOptionDefault` for system-wide key capture
- **Text insertion**: `CGEventCreateKeyboardEvent` to simulate typing, respects system text replacement
- **Model storage**: `~/Library/Application Support/WhisperNode/Models/` with atomic downloads
- **Audio processing**: 16kHz mono PCM, 1024-sample buffer chunks, VAD threshold at -40dB
- **Memory management**: Lazy model loading, unload after 30s idle, automatic garbage collection
- **Permissions**: Request microphone access on first launch, store grant status in UserDefaults
- **Update mechanism**: Sparkle framework with EdDSA signatures, check weekly
- **Crash reporting**: Optional anonymous telemetry via TelemetryDeck (opt-in only)
- **Performance monitoring**: CPU/memory usage tracking, automatic model downgrade if >80% CPU
- **File system**: All writes atomic, temp files cleaned on exit, respect sandboxing constraints

## 7. Acceptance / Success Criteria

- Cold launch ≤ 2s (Spotlight open → indicator ready).
- First-time dictation accuracy ≥ 95% WER on Librispeech test subset.
- System Integration: Text insertion works in ≥ 95% of Cocoa text views tested.
- VirusTotal scan shows zero outbound connections during use.
- User survey (≥ 30 beta testers) average "satisfaction with speed" ≥ 4/5.

## 8. Deliverables (MVP)

| Item | Due | Owner |
|------|-----|-------|
| Signed .dmg installer | Week 6 | Release Eng |
| README & quick-start docs | Week 6 | Tech Writer |
| Automated CI pipeline (GitHub Actions) with notarisation | Week 4 | DevOps |

## 9. Future Considerations (Post-MVP, not to affect v1 schedule)

- Command-mode JSON API for scripting (e.g., "Run test suite").
- Multilingual model bundles with on-demand download.
- GPU inference path (Metal Performance Shaders) for sub-250ms latency.
- Inline transcript editor & history pane.
- Energy-aware throttling for laptops on battery.

## 10. Assumptions & Dependencies

- Users run macOS 13 Ventura or later (for SwiftUI menu-bar improvements).
- Apple Silicon baseline M1; Intel support deferred.
- Whisper model weights licensed under MIT or similar and re-distribution permitted.

## 11. Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Hotkey clash with third-party utilities | Medium | Medium | Detect duplicates, prompt user to choose another. |
| Large models bloating installer | Low | High | Ship only tiny.en; larger models downloaded after first run. |
| macOS microphone permission denial | High | Low | First-launch onboarding explaining steps to enable. |

## 12. Design Decisions (Resolved)

- **Model bundling**: Ship with tiny.en (~39MB) bundled; larger models downloaded on-demand to balance installer size vs. immediate functionality
- **Dock icon behavior**: Hidden by default, toggle available in General preferences for users who prefer traditional app behavior  
- **License choice**: MIT license selected for maximum compatibility and future open-source release flexibility
- **Haptic feedback**: Enabled on supported MacBooks when recording starts/stops, subtle single tap (intensity 0.3)
- **Window positioning**: Preferences window centers on screen, remembers last position, constrained to visible screen area
- **Model download UI**: Progress shown in menu bar dropdown, full details in Models preferences tab

---

**Status**: Draft v1.0 — comprehensive specification ready for development handoff  
**Prepared by**: Product & Engineering – 2 June 2025 (AWST)  
**Last updated**: 2 June 2025 — added complete visual specs, interaction patterns, and technical implementation details