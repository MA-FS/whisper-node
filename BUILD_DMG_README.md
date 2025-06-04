# WhisperNode DMG Build Guide

This guide helps you build a DMG installer for WhisperNode to test the audio recording fixes on your Mac.

## Quick Start

```bash
# Build Debug DMG for testing (recommended)
./build-dmg.sh

# Build Release DMG for distribution
./build-dmg.sh Release
```

## Prerequisites

### Required Tools
- **Xcode** (from App Store)
- **Xcode Command Line Tools**: `xcode-select --install`
- **Homebrew** (for create-dmg): `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
- **create-dmg**: `brew install create-dmg`

### Optional Tools
- **Rust** (for enhanced Whisper functionality): `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`

## Build Process

The `build-dmg.sh` script performs these steps:

1. **Checks Requirements** - Verifies all tools are installed
2. **Builds Rust Library** - Compiles the Whisper Rust components
3. **Builds Swift App** - Compiles the main WhisperNode application
4. **Creates App Bundle** - Packages everything into WhisperNode.app
5. **Code Signs App** - Signs the app (ad-hoc for Debug, proper for Release)
6. **Creates DMG** - Builds a professional installer with background and icons
7. **Verifies DMG** - Tests the installer to ensure it works

## Testing the Audio Fixes

After building and installing, test these specific fixes:

### 1. Level Meter Functionality
- Open WhisperNode → Voice Settings
- Speak into your microphone
- **Expected**: dB level bars should move in real-time
- **Before Fix**: Bars were static/not moving

### 2. Test Recording Feature
- Click "Start Test Recording" button
- Speak for 3 seconds
- **Expected**: Detailed feedback with audio quality assessment
- **Before Fix**: No feedback or results

### 3. Audio Engine Status
- Check the status indicator next to the dB level
- **Expected**: Shows "Active" when recording, "Idle" when stopped
- **Before Fix**: No status indication

## Build Configurations

### Debug Build (Default)
```bash
./build-dmg.sh
```
- **Purpose**: Local testing and development
- **Code Signing**: Ad-hoc (may show security warnings)
- **Size**: Larger (includes debug symbols)
- **Performance**: Not optimized
- **Recommended for**: Testing the audio fixes

### Release Build
```bash
./build-dmg.sh Release
```
- **Purpose**: Distribution to users
- **Code Signing**: Proper certificates (if available)
- **Size**: Smaller (optimized)
- **Performance**: Fully optimized
- **Recommended for**: Final distribution

## Troubleshooting

### Common Issues

#### "create-dmg not found"
```bash
brew install create-dmg
```

#### "xcodebuild not found"
Install Xcode from the App Store

#### "No valid signing identity found"
This is normal for Debug builds - the script will use ad-hoc signing

#### "Permission denied" when running script
```bash
chmod +x build-dmg.sh
```

#### Build fails with Rust errors
Rust is optional. The app will build without it, but with limited Whisper functionality.

### Getting Help

1. **Check the build output** - The script provides detailed logging
2. **Verify prerequisites** - Ensure all required tools are installed
3. **Try Debug build first** - It has fewer requirements than Release
4. **Check disk space** - Builds require several GB of free space

## Output Files

After a successful build, you'll find:

- **DMG Installer**: `build/WhisperNode-[version].dmg`
- **App Bundle**: `build/WhisperNode.app`
- **Build Artifacts**: `build/` directory

## Installation Testing

1. **Open the DMG**: Double-click the `.dmg` file
2. **Install the App**: Drag WhisperNode.app to Applications
3. **Launch**: Open from Applications folder or Spotlight
4. **Test Audio**: Go to Voice Settings and test the fixes
5. **Grant Permissions**: Allow microphone access when prompted

## Security Notes

### Debug Builds
- Use ad-hoc code signing
- macOS may show security warnings
- Safe for personal testing
- **Do not distribute** to other users

### Release Builds
- Require proper Apple Developer certificates
- Should be notarized for distribution
- Safe for public distribution
- Follow Apple's distribution guidelines

## Next Steps

After testing the DMG:

1. **Verify Audio Fixes**: Test all three reported issues are resolved
2. **Test Different Devices**: Try various microphones and audio interfaces
3. **Check Permissions**: Ensure microphone permission flow works correctly
4. **Performance Testing**: Verify the app performs well during audio capture

## Support

If you encounter issues:

1. Check the console output for detailed error messages
2. Verify all prerequisites are installed correctly
3. Try building with Debug configuration first
4. Ensure you have sufficient disk space and permissions

The build process includes comprehensive logging to help diagnose any issues.
