# Development Entitlements Configuration

## Overview

WhisperNode uses two different entitlements files to support both local development and production distribution:

- **Production**: `Sources/WhisperNode/Resources/WhisperNode.entitlements`
- **Development**: `Sources/WhisperNode/Resources/WhisperNode-dev.entitlements`

## Development Entitlements

The development entitlements file (`WhisperNode-dev.entitlements`) is automatically used when building with ad-hoc signing for local testing.

### Key Differences from Production

| Entitlement | Production | Development | Reason |
|-------------|------------|-------------|---------|
| `com.apple.application-identifier` | Required with Team ID | ❌ Removed | Incompatible with ad-hoc signing |
| `com.apple.developer.team-identifier` | Required | ❌ Removed | Incompatible with ad-hoc signing |
| `com.apple.security.app-sandbox` | `true` | ❌ Removed | Requires proper signing |
| `com.apple.security.accessibility` | `true` | ❌ Removed | Requires proper signing |
| `com.apple.security.cs.disable-library-validation` | `false` | ✅ `true` | Allows unsigned dylibs |
| `com.apple.security.cs.allow-unsigned-executable-memory` | ❌ Not present | ✅ `true` | Development flexibility |

### Included Permissions

The development entitlements include only the essential permissions that work with ad-hoc signing:

```xml
<!-- Basic Audio Input Permissions -->
<key>com.apple.security.device.microphone</key>
<true/>
<key>com.apple.security.device.audio-input</key>
<true/>

<!-- Basic File Access -->
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.files.downloads.read-write</key>
<true/>

<!-- Network Access -->
<key>com.apple.security.network.client</key>
<true/>

<!-- Development-specific -->
<key>com.apple.security.cs.disable-library-validation</key>
<true/>
<key>com.apple.security.cs.allow-unsigned-executable-memory</key>
<true/>
```

## Automatic Selection

The build script (`scripts/build-release.sh`) automatically selects the appropriate entitlements file:

```bash
# Choose appropriate entitlements file
if [ "$SIGNING_IDENTITY" = "-" ]; then
    ENTITLEMENTS_FILE="$PROJECT_DIR/Sources/WhisperNode/Resources/WhisperNode-dev.entitlements"
    log_info "Using development entitlements for ad-hoc signing"
else
    ENTITLEMENTS_FILE="$PROJECT_DIR/Sources/WhisperNode/Resources/WhisperNode.entitlements"
    log_info "Using production entitlements for proper signing"
fi
```

## Limitations

### Security Restrictions
- No app sandbox protection
- No accessibility API access
- Reduced system integration capabilities
- Users will see "unidentified developer" warnings

### Functionality Impact
- Global hotkeys may have limited functionality
- Some advanced system features may not work
- Automatic updates require user approval
- No Gatekeeper approval without notarization

## Production Migration

When moving to production distribution:

1. **Obtain Apple Developer ID** - Required for proper signing
2. **Use production entitlements** - Full security model
3. **Enable app sandbox** - Enhanced security
4. **Add accessibility permissions** - Full system integration
5. **Implement notarization** - Gatekeeper approval

## Testing Considerations

### What Works in Development
✅ Basic app functionality  
✅ Microphone access (with user permission)  
✅ File operations (user-selected)  
✅ Network requests  
✅ Core transcription features  

### What May Not Work
⚠️ Global system hotkeys (limited)  
⚠️ Accessibility API features  
⚠️ Advanced system integration  
⚠️ Automatic privilege escalation  

## Troubleshooting

### App Won't Launch
```bash
# Check entitlements in use
codesign -d --entitlements - /path/to/WhisperNode.app

# Verify development entitlements are applied
grep -A 5 "disable-library-validation" entitlements_output.xml
```

### Permission Denied Errors
- Ensure microphone permission is granted in System Preferences
- Check that file access permissions are properly requested
- Verify network access is not blocked by firewall

### Signing Issues
```bash
# Verify ad-hoc signing
codesign -dv /path/to/WhisperNode.app
# Should show: Signature=adhoc

# Check for signing errors
log show --predicate 'eventMessage contains "WhisperNode"' --last 5m
```

## Best Practices

1. **Always test with development entitlements** before production
2. **Document any functionality differences** between dev and prod
3. **Use production entitlements** for final testing when possible
4. **Keep both files in sync** for common permissions
5. **Test permission requests** work correctly in both modes

---
*This configuration enables local development and testing while maintaining a clear path to production distribution.*
