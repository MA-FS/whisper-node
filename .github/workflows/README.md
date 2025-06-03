# CI/CD Pipeline Documentation

⚠️ **PIPELINE CURRENTLY SHELVED** ⚠️

The CI/CD pipeline has been temporarily disabled due to build failures and dependency issues. It will be reactivated once the core application is fully functional locally.

**Current Status**: Development focus is on completing core functionality locally before implementing automated builds.

**When to Reactivate**: After the WhisperNode app builds and runs successfully on local development machines.

---

This directory contains GitHub Actions workflows for automated building, testing, and releasing of WhisperNode (currently disabled).

## Local Development Workflow (Current Focus)

Until the CI/CD pipeline is reactivated, use these local development commands:

### Prerequisites
- macOS 13+ with Apple Silicon
- Xcode 15+ with command line tools
- Rust toolchain with `aarch64-apple-darwin` target

### Local Build Commands
```bash
# Build Rust library
./scripts/build-rust.sh release

# Build Swift application
swift build --configuration release --arch arm64 --build-path build

# Run tests locally
swift test --build-path build

# Create app bundle (manual)
./scripts/build-release.sh Release

# Test app locally
open build/WhisperNode.app
```

### Before Reactivating CI/CD
1. Ensure local builds complete without errors
2. Verify the app runs and functions correctly locally
3. Test all core features (audio capture, transcription, text insertion)
4. Resolve any Rust FFI or dependency issues
5. Update CI/CD workflows with working build configuration

---

## Workflows Overview (For Future Reference)

### 1. `ci.yml` - Continuous Integration
**Trigger**: Push/PR to main or develop branches

**Jobs**:
- **Lint**: Code formatting and style checks
- **Test**: Build and test in Debug/Release configurations
- **Integration Test**: Performance and integration tests
- **Dependencies**: Dependency auditing and version checks

### 2. `build-and-release.yml` - Build and Release
**Trigger**: Git tags starting with 'v' (e.g., v1.0.0)

**Jobs**:
- **Test**: Full test suite validation
- **Build**: Signed app building and notarization
- **Security Scan**: Security compliance verification

**Artifacts**:
- Notarized WhisperNode.app
- Signed DMG installer
- Automatic GitHub Release creation

### 3. `security.yml` - Security and Compliance
**Trigger**: Push to main, PRs, weekly schedule

**Jobs**:
- **Security Scan**: Secret detection and vulnerability scanning
- **Privacy Audit**: Offline operation and audio privacy verification
- **Compliance**: macOS sandboxing and signing compliance

## Required Secrets

Configure these in GitHub repository settings → Secrets and variables → Actions:

### Code Signing
- `CERTIFICATES_P12`: Base64-encoded .p12 certificate file
- `CERTIFICATES_P12_PASSWORD`: Password for the .p12 file
- `SIGNING_IDENTITY`: Developer ID Application certificate name

### Notarization
- `APPLE_TEAM_ID`: Apple Developer Team ID (10-character string)
- `APPLE_ID`: Apple ID email address for notarization
- `APPLE_APP_PASSWORD`: App-specific password for notarization

### Automatic (GitHub-provided)
- `GITHUB_TOKEN`: Automatically provided for releases

## Setup Instructions

### 1. Certificate Setup
```bash
# Export your Developer ID Application certificate as .p12
# From Keychain Access → Export → Personal Information Exchange (.p12)

# Convert to base64 for GitHub secret
base64 -i YourCertificate.p12 | pbcopy
# Paste result into CERTIFICATES_P12 secret
```

### 2. App-Specific Password
1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign in with your Apple ID
3. App-Specific Passwords → Generate password
4. Use generated password for `APPLE_APP_PASSWORD` secret

### 3. Team ID Discovery
```bash
# Find your Team ID
xcrun altool --list-providers -u "your-apple-id@example.com" -p "app-specific-password"
```

## Release Process

### Automatic Release (Recommended)
1. Ensure all tests pass on main branch
2. Create and push a version tag:
   ```bash
   git tag -a v1.0.0 -m "Release version 1.0.0"
   git push origin v1.0.0
   ```
3. GitHub Actions will:
   - Run full test suite
   - Build and sign the application
   - Submit for notarization
   - Create DMG installer
   - Create GitHub release with artifacts

### Manual Testing
For testing workflows without creating a release:
```bash
# Trigger workflow manually
gh workflow run build-and-release.yml
```

## Workflow Features

### Caching
- Rust dependencies cached between runs
- Significant build time reduction for incremental changes

### Security
- Automatic secret scanning
- Privacy compliance verification
- Dependency vulnerability scanning
- No secrets exposed in logs

### Performance
- Parallel job execution where possible
- Matrix builds for multiple configurations
- Selective testing based on trigger type

### Error Handling
- Detailed error reporting
- Artifact preservation on failure
- Comprehensive logging

## Troubleshooting

### Common Issues

### Code Signing Failures
- Verify certificate is valid and not expired
- Check that certificate includes "Developer ID Application"
- Ensure certificate is in the correct .p12 format

### Notarization Failures
- Verify Apple ID credentials are correct
- Check that Team ID matches the certificate
- Ensure app-specific password is current

### Test Failures
- Check if the Rust toolchain is properly installed
- Verify that all dependencies are available
- Review test logs for specific failure reasons

### Build Failures
- Ensure all required frameworks are linked
- Check that Rust library builds successfully
- Verify Xcode version compatibility

### Debug Commands
```bash
# Check workflow status
gh run list --workflow=ci.yml

# View workflow logs
gh run view <run-id> --log

# Re-run failed workflow
gh run rerun <run-id>
```

## Local Testing

Before pushing changes, test locally:
```bash
# Run the same commands as CI
./scripts/build-rust.sh release
swift test --build-path build
./scripts/run-performance-tests.sh
./scripts/build-release.sh Release
```

## Maintenance

### Regular Tasks
- Update Xcode version in workflows quarterly
- Review and update dependency versions monthly
- Rotate app-specific passwords annually
- Audit security configurations quarterly

### Workflow Updates
When modifying workflows:
1. Test in a fork first
2. Use workflow_dispatch for manual testing
3. Monitor first few runs after changes
4. Document any breaking changes

## Security Considerations

- All secrets are stored securely in GitHub
- No sensitive information is logged
- Artifacts are automatically cleaned up
- Security scanning runs on every change
- Privacy compliance is continuously verified