# Task 07: Text Insertion Engine

**Status**: ⏳ WIP  
**Priority**: High  
**Estimated Hours**: 12  
**Dependencies**: T06  

## Description

Implement text insertion system using CGEventCreateKeyboardEvent with smart formatting and caret positioning.

## Acceptance Criteria

- [ ] CGEventCreateKeyboardEvent implementation
- [ ] Text inserted at current cursor position
- [ ] Smart punctuation and capitalization
- [ ] User dictionary override support
- [ ] System text replacement respect
- [ ] 95% compatibility with Cocoa text views

## Implementation Details

### CGEvent Text Insertion
```swift
func insertText(_ text: String) {
    for character in text {
        let keyCode = characterToKeyCode(character)
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
```

### Smart Formatting
- Auto-capitalization for sentence starts
- Smart punctuation (quotes, apostrophes)
- Respect existing text context

### Compatibility Testing
- VS Code, Xcode, TextEdit
- Slack, Discord, Mail
- Safari forms, Terminal
- System text fields

## Testing Plan

- [ ] Text appears at cursor position
- [ ] Formatting rules work correctly
- [ ] No conflicts with existing text
- [ ] Works across target applications

## Tags
`text-insertion`, `cgevents`, `formatting`, `compatibility`