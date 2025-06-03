# Code Signing and Distribution Guide for Whisper Node

This guide covers the complete process of building, signing, notarizing, and distributing Whisper Node for macOS.

## Prerequisites

1. **Apple Developer Account**: Required for code signing and notarization
2. **Developer ID Certificates**: 
   - Developer ID Application certificate
   - Developer ID Installer certificate (optional, for pkg distribution)
3. **Xcode**: Version 14.0 or later
4. **macOS**: Version 13.0 (Ventura) or later

## Environment Setup

Set the following environment variables in your shell profile:

```bash
# Your Apple Developer Team ID (found in Apple Developer portal)
export WHISPERNODE_TEAM_ID="YOUR_TEAM_ID"

# Your Apple ID email
export WHISPERNODE_APPLE_ID="your.email@example.com"

# App-specific password for notarization
# Generate at: https://appleid.apple.com/account/manage
export WHISPERNODE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"

# Optional: Specific signing identity
export WHISPERNODE_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

## Build Process

### 1. Development Build

For local testing without code signing:

```bash
swift build
```

### 2. Release Build

For distribution with proper code signing:

```bash
./scripts/build-release.sh Release
```

This script will:
- Build the Rust FFI library
- Build the Swift application
- Create the app bundle structure
- Sign all components with proper entitlements
- Verify the code signature

### 3. Verify Code Signing

After building, verify the app is properly signed:

```bash
./scripts/verify-signing.sh build/WhisperNode.app
```

This will check:
- Code signature validity
- Entitlements configuration
- Hardened runtime status
- Framework signatures
- Gatekeeper compliance

## Notarization Process

Apple requires all distributed apps to be notarized for macOS 10.15+.

### 1. Submit for Notarization

```bash
./scripts/notarize-app.sh build/WhisperNode.app
```

This process:
- Uploads the app to Apple's notarization service
- Waits for the notarization to complete
- Staples the notarization ticket to the app
- Verifies the final result

### 2. Manual Notarization (if needed)

```bash
# Create a ZIP for upload
ditto -c -k --keepParent build/WhisperNode.app WhisperNode.zip

# Submit for notarization
xcrun notarytool submit WhisperNode.zip \
    --apple-id "$WHISPERNODE_APPLE_ID" \
    --password "$WHISPERNODE_APP_PASSWORD" \
    --team-id "$WHISPERNODE_TEAM_ID" \
    --wait

# Staple the ticket
xcrun stapler staple build/WhisperNode.app
```

## Distribution

### Option 1: Direct .app Distribution

The signed and notarized app can be distributed directly:

1. Compress the app:
   ```bash
   ditto -c -k --keepParent build/WhisperNode.app WhisperNode.zip
   ```

2. Distribute the ZIP file
3. Users can unzip and drag to Applications

### Option 2: DMG Distribution (Recommended)

See `T21-dmg-installer.md` for creating a DMG installer.

### Option 3: PKG Installer

For advanced distribution with installation scripts:

```bash
productbuild --component build/WhisperNode.app /Applications \
    --sign "Developer ID Installer: Your Name (TEAMID)" \
    WhisperNode.pkg
```

## Troubleshooting

### Common Issues

1. **"errSecInternalComponent" error**
   - Ensure you're running on the Mac where the certificates are installed
   - Check Keychain Access for valid certificates

2. **"The executable does not have the hardened runtime enabled"**
   - Ensure `ENABLE_HARDENED_RUNTIME = YES` in build settings
   - Add `--options runtime` to codesign commands

3. **Notarization fails with "The signature does not include a secure timestamp"**
   - Add `--timestamp` flag to all codesign commands

4. **App crashes on launch after signing**
   - Check entitlements match app capabilities
   - Verify all frameworks are properly signed
   - Check Console.app for crash logs

### Security Considerations

1. **Never commit credentials**: Keep signing certificates and passwords out of version control
2. **Use CI/CD secrets**: Store credentials securely in CI/CD systems
3. **Minimal entitlements**: Only request necessary permissions
4. **Regular updates**: Keep certificates and provisioning profiles current

## Entitlements

Whisper Node requires these entitlements:

- `com.apple.security.device.microphone`: Microphone access for speech recognition
- `com.apple.security.accessibility`: Global hotkeys and text insertion
- `com.apple.security.network.client`: Model downloads and update checks
- `com.apple.security.cs.allow-jit`: Performance optimization for ML inference
- `com.apple.security.cs.disable-library-validation`: Loading whisper.cpp library

## Certificate Management

### Creating Certificates

1. Log in to [Apple Developer Portal](https://developer.apple.com)
2. Navigate to Certificates, Identifiers & Profiles
3. Create a new certificate:
   - Type: Developer ID Application
   - Follow the CSR generation process
4. Download and install in Keychain Access

### Exporting for CI/CD

```bash
# Export certificates to .p12 file
security export -k ~/Library/Keychains/login.keychain-db \
    -t certs -f pkcs12 -o certificates.p12
```

## Continuous Integration

For automated builds, see `T22-cicd-pipeline.md` for GitHub Actions setup.

## Resources

- [Apple Developer - Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Code Signing Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Introduction/Introduction.html)
- [Hardened Runtime](https://developer.apple.com/documentation/security/hardened_runtime)