# Task 13: Preferences Window - About Tab

**Status**: ⏳ WIP  
**Priority**: Low  
**Estimated Hours**: 6  
**Dependencies**: T09  

## Description

Build About tab with version info, credits, and Sparkle update integration.

## Acceptance Criteria

- [ ] App version and build information
- [ ] Sparkle update framework integration
- [ ] Weekly update check configuration
- [ ] EdDSA signature verification
- [ ] Credits and license information
- [ ] Manual update check button

## Implementation Details

### Version Display
```swift
struct AboutTab: View {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
}
```

### Sparkle Integration
- Weekly automatic update checks
- EdDSA signature verification
- Manual check button
- Update notification handling

### Credits Section
- Development team information
- Open source acknowledgments
- License information (MIT)

## Testing Plan

- [ ] Version information displays correctly
- [ ] Update checks work properly
- [ ] Credits are complete and accurate
- [ ] License text is properly formatted

## Tags
`preferences`, `about`, `updates`, `sparkle`