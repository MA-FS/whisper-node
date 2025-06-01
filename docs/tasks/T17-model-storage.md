# Task 17: Model Storage & Management System

**Status**: ⏳ WIP  
**Priority**: Medium  
**Estimated Hours**: 8  
**Dependencies**: T11  

## Description

Build secure model storage with atomic downloads, checksums, and cleanup.

## Acceptance Criteria

- [ ] Storage in ~/Library/Application Support/WhisperNode/Models/
- [ ] Atomic file downloads with temp staging
- [ ] SHA256 checksum verification
- [ ] Automatic cleanup of temp files
- [ ] Model file corruption detection
- [ ] Safe concurrent access handling

## Implementation Details

### Storage Structure
```
~/Library/Application Support/WhisperNode/
├── Models/
│   ├── tiny.en.bin
│   ├── small.en.bin
│   └── medium.en.bin
├── temp/
└── metadata.json
```

### Atomic Downloads
- Download to temp directory first
- Verify checksum before moving
- Atomic file system operations
- Rollback on failure

### File Integrity
- SHA256 checksum verification
- Corruption detection and recovery
- Metadata tracking for each model

## Testing Plan

- [ ] Downloads are atomic and safe
- [ ] Checksums prevent corruption
- [ ] Cleanup works properly
- [ ] Concurrent access is handled safely

## Tags
`storage`, `security`, `files`, `atomic`