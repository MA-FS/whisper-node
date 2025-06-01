# Task 20: App Bundle & Code Signing

**Status**: ⏳ WIP  
**Priority**: High  
**Estimated Hours**: 8  
**Dependencies**: T01  

## Description

Configure app bundle structure, code signing, and Gatekeeper compliance.

## Acceptance Criteria

- [ ] Proper app bundle structure
- [ ] Developer ID code signing
- [ ] Entitlements configuration
- [ ] Gatekeeper compliance
- [ ] Notarization preparation
- [ ] Sandboxing constraints handling

## Implementation Details

### App Bundle Structure
```
WhisperNode.app/
├── Contents/
│   ├── Info.plist
│   ├── MacOS/
│   │   └── WhisperNode
│   ├── Resources/
│   └── _CodeSignature/
```

### Code Signing
- Developer ID Application certificate
- Proper entitlements for microphone access
- Embedded provisioning profile
- All frameworks and binaries signed

### Entitlements
```xml
<key>com.apple.security.device.microphone</key>
<true/>
<key>com.apple.security.device.audio-input</key>
<true/>
```

### Notarization Prep
- Apple Developer ID setup
- Notarization workflow configuration
- Stapling process preparation

## Testing Plan

- [ ] App bundle validates correctly
- [ ] Code signature verification passes
- [ ] Gatekeeper allows execution
- [ ] Entitlements work as expected

## Tags
`signing`, `security`, `gatekeeper`, `bundle`