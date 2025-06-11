# WhisperNode

A native macOS application for real-time speech-to-text transcription using OpenAI's Whisper model, built with Swift and Rust.

## Features

- 🎤 Real-time audio transcription
- 🚀 Apple Silicon optimized (M1/M2/M3)
- 🔒 Privacy-focused (local processing)
- ⚡ High-performance Rust backend
- 🎯 Native macOS integration
- 📦 Easy DMG installer

## Quick Start

### Prerequisites

- macOS 13+ (Ventura or later)
- Xcode Command Line Tools
- Rust toolchain with aarch64-apple-darwin target
- Homebrew (for create-dmg)

### Installation

#### Option 1: Download DMG (Recommended)
1. Download the latest `WhisperNode-x.x.x.dmg` from releases
2. Open the DMG file
3. Drag WhisperNode.app to the Applications folder
4. Launch from Applications

#### Option 2: Build from Source
```bash
# Clone the repository
git clone https://github.com/MA-FS/whisper-node.git
cd whisper-node

# Build and create DMG
./scripts/build-release.sh && ./scripts/create-dmg.sh

# Install the built app
open build/WhisperNode-1.0.0.dmg
```

## Development

### Build Requirements
- Swift Package Manager
- Rust 1.70+
- create-dmg (install via `brew install create-dmg`)

### Build Commands
```bash
# Build Debug DMG for testing
./build-dmg.sh

# Build Release DMG for distribution
./build-dmg.sh Release

# Build app only (no DMG)
./scripts/build-release.sh

# Create DMG from existing app
./scripts/create-dmg.sh ./build/WhisperNode.app

# Clean build
rm -rf build/ && ./scripts/build-release.sh
```

⏺ **Individual script options:**
1. **For Release builds:** `./build-dmg.sh Release`
2. **Just build the app (no DMG):** `./scripts/build-release.sh`
3. **Just create DMG from existing app:** `./scripts/create-dmg.sh ./build/WhisperNode.app`

### Project Structure
```
whisper-node/
├── Sources/WhisperNode/          # Swift application code
├── whisper-rust/                 # Rust FFI library
├── scripts/                      # Build and packaging scripts
├── docs/                         # Documentation
└── build/                        # Build outputs
```

## Documentation

- [Local DMG Analysis](docs/local-dmg-analysis.md) - Comprehensive technical analysis
- [DMG Quick Start](docs/dmg-quick-start.md) - Quick reference guide
- [Project Progress](docs/Progress.md) - Development status

## Architecture

- **Frontend**: Swift + SwiftUI for native macOS UI
- **Backend**: Rust library with whisper.cpp bindings
- **Audio**: AVFoundation for microphone access
- **Updates**: Sparkle framework for auto-updates
- **Distribution**: DMG installer with code signing

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Status

✅ **Local DMG Creation**: Fully operational and tested
🚧 **Production Distribution**: Requires code signing setup
📋 **Progress**: 20/25 tasks completed (80% done)