# Task 08: Menu Bar Application Framework

**Status**: ⏳ WIP  
**Priority**: Medium  
**Estimated Hours**: 10  
**Dependencies**: T01  

## Description

Create menu bar app with SF Symbols, dropdown menu, and headless operation (no Dock icon).

## Acceptance Criteria

- [ ] Menu bar icon with mic.fill SF Symbol (16x16pt)
- [ ] State indication: normal, recording (blue), error (red)
- [ ] 240pt wide dropdown with dynamic height
- [ ] Headless operation (no Dock icon by default)
- [ ] Optional Dock icon toggle in preferences

## Implementation Details

### Menu Bar Setup
```swift
let statusBar = NSStatusBar.system
let statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
statusItem.button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Whisper Node")
```

### State Management
- Normal: Black/white mic icon
- Recording: Blue tinted icon
- Error: Red tinted icon

### Dropdown Menu
- 240pt fixed width
- Dynamic height based on content
- SwiftUI content integration

## Testing Plan

- [ ] Menu bar icon appears correctly
- [ ] State changes work
- [ ] Dropdown shows/hides properly
- [ ] Headless mode works

## Tags
`menubar`, `ui`, `sf-symbols`, `headless`