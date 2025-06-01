# Claude Memory & Context for Whisper Node

## Project Overview
Whisper Node is a blazingly fast, resource-light macOS utility that converts speech to text entirely on-device, targeting developers and power users who prefer keyboard-style "press-and-hold" voice input.

## Key Project Context

### Technology Stack
- **UI Framework**: SwiftUI (macOS 13+ Ventura)
- **Core Logic**: Swift + Rust FFI for whisper.cpp bindings
- **Audio Processing**: AVAudioEngine with 16kHz mono circular buffer
- **ML Inference**: whisper.cpp with Apple Silicon optimizations
- **Distribution**: Xcode App Bundle + signed .dmg via create-dmg
- **Target Platform**: Apple Silicon M1+ only, macOS 13+

### Performance Requirements
- **Latency**: ≤1s for 5s utterances, ≤2s for 15s utterances
- **Memory**: ≤100MB idle, ≤700MB peak with small.en model
- **CPU**: <150% core utilization during transcription
- **Accuracy**: ≥95% WER on Librispeech test subset
- **Battery**: Minimal impact with <150% average CPU

### Core Features (Must-Have)
1. **Global Hotkey**: Press-and-hold activation using CGEventTap
2. **Visual Indicator**: 80pt floating orb with animations and state colors
3. **Model Management**: Download/select Whisper models (tiny.en, small.en, medium.en)
4. **Text Insertion**: CGEventCreateKeyboardEvent for cursor-position text injection
5. **Menu Bar App**: Headless operation with SF Symbols and dropdown
6. **Preferences**: 5-tab window (General, Voice, Models, Shortcut, About)
7. **Onboarding**: First-run setup with microphone permissions
8. **Error Handling**: Graceful degradation with user-friendly messaging

### Development Workflow

#### Task Management & Git Workflow
- **Task Files**: Located in `docs/tasks/T01-T25.md`
- **Progress Tracking**: `docs/Progress.md` with status indicators
- **Git Workflow**: Create feature branch → Implement → Push → Create PR → Review → Merge
- **Branch Naming**: `feature/t01-project-setup`, `feature/t02-rust-ffi`, etc.
- **Commit Format**: `T01: Add Swift Package Manager project structure`
- **PR Process**: Each task requires a separate PR for review before merge
- **Status Legend**: ⏳ WIP, ✅ Done, 🛂 Blocked, 🧪 Testing, 🔄 Review

#### Development Phases
1. **Phase 1 (Foundation)**: T01-T02, T20 - Project setup, Rust FFI, code signing
2. **Phase 2 (Core Features)**: T03-T07 - Audio capture, processing, text insertion
3. **Phase 3 (User Interface)**: T05, T08-T13 - Visual components and preferences
4. **Phase 4 (Polish & Distribution)**: T14-T25 - UX, performance, testing, release

#### Code Conventions
- **Swift**: Follow Apple's Swift API Design Guidelines
- **Rust**: Standard Rust formatting with rustfmt
- **Git**: Conventional commits with task prefixes (TXX:)
- **Branches**: feature/tXX-description, bugfix/issue-description
- **Testing**: Unit tests for all core logic, integration tests for system compatibility

### Important Constraints & Decisions
- **Privacy First**: 100% offline operation, no network calls, no telemetry
- **Apple Silicon Only**: No Intel support to optimize for M1+ performance
- **Model Bundling**: Ship with tiny.en (~39MB), larger models downloaded on-demand
- **Press-and-Hold Only**: No click-to-start mode in v1 for simplicity
- **Text Insertion Only**: No selection replacement, always insert at cursor
- **App Restart Required**: For model switching to ensure memory management

### File Structure
```
WhisperNode/
├── CLAUDE.md                 # This file
├── docs/
│   ├── Progress.md          # Main progress tracking
│   ├── tasks/T01-T25.md     # Individual task files
│   ├── prd/prd.md          # Product Requirements Document
│   └── wireframes/         # UI mockups
├── .taskmaster/
│   ├── docs/prd.txt        # Task Master PRD copy
│   └── tasks/tasks.json    # Task Master configuration
└── [Source code when created]
```

### Memory Management Commands
- **Search Tasks**: Use `mcp__memory__search_nodes(query: "Task Master setup workflow")`
- **Update Progress**: Always update todos with TodoWrite tool
- **Store Learnings**: Use `mcp__memory__create_entities` for new patterns/workflows

### Development Guidelines

#### Git Workflow for Each Task
1. **Create Feature Branch**: `git checkout -b feature/t01-project-setup`
2. **Read Task File**: Start by reading the relevant `docs/tasks/T0X.md` file
3. **Implement Changes**: Follow task acceptance criteria and implementation details
4. **Commit Changes**: Use format `T01: Add Swift Package Manager project structure`
5. **Push Branch**: `git push -u origin feature/t01-project-setup`
6. **Create Pull Request**: Use GitHub CLI or web interface
7. **Request Review**: Wait for code review approval
8. **Merge to Main**: After approval, merge PR and delete feature branch
9. **Update Progress**: Mark task as ✅ Done in `docs/Progress.md`

#### General Development Rules
1. **Always Read Task File First**: Start each work session by reading the relevant T0X.md file
2. **Update Progress Immediately**: Mark todos as completed as soon as work finishes
3. **Follow Dependencies**: Respect task dependencies mapped in Progress.md
4. **Test Early**: Implement testing alongside feature development
5. **Document Decisions**: Update task files with implementation decisions and learnings
6. **Never Commit to Main**: All changes must go through feature branch → PR → review workflow

### Quality Standards
- **Code Coverage**: Aim for 80%+ test coverage
- **Performance**: Validate against PRD requirements continuously
- **Accessibility**: Full VoiceOver support and keyboard navigation
- **Security**: Code signing, notarization, and privacy compliance
- **Compatibility**: Test with major macOS applications (VS Code, Slack, Safari, etc.)

### Communication Preferences
- **Concise Updates**: Brief status updates without unnecessary explanation
- **Task-Focused**: Always reference task numbers (T01, T02, etc.) in discussions
- **Problem-Solution Format**: When reporting issues, always include proposed solutions
- **Progress First**: Lead with progress updates before diving into technical details

### Privacy & Security Guidelines
- **No Personal Information**: Never include usernames, file paths, or system-specific details in code or documentation
- **Public Repository Safe**: All content must be suitable for public GitHub repository
- **No Sensitive Data**: Exclude API keys, certificates, personal preferences, or local configuration
- **Generic Examples**: Use placeholder names (e.g., "user", "developer") instead of real names
- **Clean Commits**: Review all commits to ensure no personal data is included
- **Local Development**: Keep personal settings in .gitignore'd files (config.json, local-config.*)

### Development Security
- **Code Signing**: Use generic developer references, store certificates locally only
- **Model Downloads**: Implement secure download verification without exposing user data
- **Audio Processing**: Ensure no audio data persists beyond immediate processing
- **Error Logging**: Log errors without including user-specific information
- **Network Isolation**: Maintain 100% offline operation with no data transmission

---

*This file serves as the primary context and memory aid for Claude when working on Whisper Node. Update it as the project evolves and new patterns emerge. Ensure all changes maintain privacy and security standards for public repository.*