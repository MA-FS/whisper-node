# Task 21: DMG Installer Creation

**Status**: ⏳ WIP  
**Priority**: Medium  
**Estimated Hours**: 6  
**Dependencies**: T20  

## Description

Build signed .dmg installer with proper layout and distribution setup.

## Acceptance Criteria

- [ ] create-dmg script integration
- [ ] Professional installer layout
- [ ] Background image and styling
- [ ] Application shortcut creation
- [ ] Volume icon customization
- [ ] Digital signature verification

## Implementation Details

### DMG Creation Script
```bash
#!/bin/bash
create-dmg \
  --volname "Whisper Node" \
  --volicon "installer-icon.icns" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "WhisperNode.app" 200 190 \
  --hide-extension "WhisperNode.app" \
  --app-drop-link 600 185 \
  "WhisperNode.dmg" \
  "release/"
```

### Visual Design
- Custom background image
- App icon and Applications alias
- Professional layout and spacing
- Volume icon matching app branding

### Code Signing
- Sign the .dmg file with Developer ID
- Verify signature before distribution
- Notarization of the installer

## Testing Plan

- [ ] DMG mounts correctly
- [ ] Installation process is intuitive
- [ ] Code signature validates
- [ ] Visual appearance is professional

## Tags
`installer`, `dmg`, `distribution`, `packaging`