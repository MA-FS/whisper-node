# Task 14: First-Run Onboarding Flow

**Status**: ⏳ WIP  
**Priority**: High  
**Estimated Hours**: 10  
**Dependencies**: T04, T11  

## Description

Create setup wizard for microphone permissions, initial configuration, and model download.

## Acceptance Criteria

- [ ] Welcome screen with app overview
- [ ] Microphone permission request flow
- [ ] System Preferences deeplink for denied permissions
- [ ] Initial model selection and download
- [ ] Basic hotkey configuration
- [ ] Completion confirmation

## Implementation Details

### Onboarding Flow
```swift
struct OnboardingFlow: View {
    @State private var currentStep = 0
    let steps = [
        WelcomeStep(),
        PermissionsStep(),
        ModelSelectionStep(),
        HotkeySetupStep(),
        CompletionStep()
    ]
}
```

### Permission Handling
- Request microphone access
- Handle denial gracefully
- Direct link to System Preferences
- Re-check permissions flow

### Model Download
- Suggest appropriate model based on device
- Show download progress
- Handle download failures

## Testing Plan

- [ ] Onboarding completes successfully
- [ ] Permission flows work correctly
- [ ] Model downloads during setup
- [ ] Users can exit and resume onboarding

## Tags
`onboarding`, `permissions`, `setup`, `ux`