# Task 11: Preferences Window - Models Tab

**Status**: ⏳ WIP  
**Priority**: High  
**Estimated Hours**: 14  
**Dependencies**: T06, T09  

## Description

Build Models tab for downloading, managing, and switching between Whisper models.

## Acceptance Criteria

- [ ] Model list with sizes and descriptions
- [ ] Download progress indicators
- [ ] Storage usage display
- [ ] Model deletion with confirmation
- [ ] Automatic fallback to smaller models
- [ ] Checksum verification for downloads
- [ ] Low disk space warnings (<1GB)

## Implementation Details

### Model Management UI
```swift
struct ModelsTab: View {
    @State private var models = [
        ModelInfo(name: "tiny.en", size: "39MB", status: .bundled),
        ModelInfo(name: "small.en", size: "244MB", status: .available),
        ModelInfo(name: "medium.en", size: "769MB", status: .available)
    ]
}
```

### Download System
- Atomic downloads with progress tracking
- SHA256 checksum verification
- Automatic retry with exponential backoff
- Background download support

### Storage Management
- Display storage usage per model
- Cleanup of incomplete downloads
- Disk space monitoring

## Testing Plan

- [ ] Model downloads complete successfully
- [ ] Progress indicators work correctly
- [ ] Checksums prevent corrupted downloads
- [ ] Storage calculations are accurate

## Tags
`preferences`, `models`, `download`, `storage`