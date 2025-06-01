# Task 09: Preferences Window - General Tab

**Status**: ⏳ WIP  
**Priority**: Medium  
**Estimated Hours**: 8  
**Dependencies**: T08  

## Description

Build General preferences tab with launch at login, Dock icon toggle, and basic app settings.

## Acceptance Criteria

- [ ] SwiftUI preferences window with tabs
- [ ] Launch at login toggle (SMLoginItem)
- [ ] Dock icon visibility toggle
- [ ] Window positioning and size persistence
- [ ] Keyboard navigation support
- [ ] VoiceOver accessibility labels

## Implementation Details

### Preferences Window
```swift
struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
    }
}
```

### Launch at Login
- SMLoginItem integration
- macOS 13+ recommended approach
- Proper entitlements configuration

### Settings Persistence
- UserDefaults for preferences
- Window position/size restoration
- Theme preference storage

## Testing Plan

- [ ] Window opens and closes properly
- [ ] Launch at login works correctly
- [ ] Settings persist between sessions
- [ ] Accessibility navigation works

## Tags
`preferences`, `ui`, `login-item`, `accessibility`