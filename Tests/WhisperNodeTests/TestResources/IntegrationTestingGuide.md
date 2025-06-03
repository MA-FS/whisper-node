# WhisperNode System Integration Testing Guide

## Overview

This guide provides comprehensive instructions for testing WhisperNode's text insertion compatibility across macOS applications to meet the PRD requirement of ≥95% Cocoa text view compatibility.

## Prerequisites

### System Requirements
- macOS 13+ (Ventura)
- Apple Silicon Mac (M1+)
- Accessibility permissions granted to test runner
- Target applications installed

### Test Environment Setup
1. **Accessibility Permissions**
   ```bash
   # Grant accessibility permissions to Terminal (for automated tests)
   # System Preferences > Security & Privacy > Privacy > Accessibility
   # Add Terminal.app and grant permissions
   ```

2. **Install Test Applications**
   ```bash
   # Core test applications (verify these are installed)
   - Visual Studio Code (com.microsoft.VSCode)
   - Safari (com.apple.Safari) 
   - Slack (com.tinyspeck.slackmacgap)
   - TextEdit (com.apple.TextEdit)
   - Mail (com.apple.mail)
   - Terminal (com.apple.Terminal)
   ```

## Running Tests

### Automated Test Suite

```bash
# Run all integration tests
swift test --filter SystemIntegrationTests

# Run performance tests  
swift test --filter IntegrationPerformanceTests

# Run specific application test
swift test --filter testVSCodeTextInsertion

# Generate compatibility report
swift test --filter testAllApplicationsComprehensiveCompatibility
```

### Manual Testing Protocol

#### 1. Basic Text Insertion Test
For each target application:

1. **Launch Application**
   - Open the target application
   - Navigate to a text input area
   - Position cursor in text field

2. **Perform Test**
   - Activate WhisperNode (global hotkey)
   - Speak: "Hello, this is a basic test message"
   - Release hotkey
   - Verify text appears correctly

3. **Validation Criteria**
   - ✅ Text inserted at cursor position
   - ✅ Proper capitalization applied
   - ✅ No extra characters or corruption
   - ✅ Cursor positioned at end of inserted text

#### 2. Special Characters Test
1. **Test Input**: "Special characters: !@#$%^&*()_+-={}[]|\\:;\"'<>?,./"
2. **Expected**: All symbols appear correctly
3. **Validation**: No character substitution or missing symbols

#### 3. Unicode Support Test  
1. **Test Input**: "Unicode test: 🌟 émojis and áccénts café naïve résumé"
2. **Expected**: Emojis and accented characters display properly
3. **Validation**: No character corruption or fallback symbols

#### 4. Smart Formatting Test
1. **Test Input**: "hello world.this is a test!how are you?"
2. **Expected**: "Hello world. This is a test! How are you?"
3. **Validation**: Proper capitalization and punctuation spacing

#### 5. Performance Test
1. **Test Input**: Long text sample (200+ characters)
2. **Expected**: Insertion completes within 2 seconds
3. **Validation**: No lag or system freeze

### Application-Specific Testing

#### Visual Studio Code
- **Text Areas**: Editor pane, integrated terminal, search box
- **Special Cases**: Code completion popup, multi-cursor editing
- **Expected Issues**: None (should work in all contexts)

#### Safari
- **Text Areas**: Address bar, search fields, form inputs, content-editable areas
- **Special Cases**: Rich text editors, password fields
- **Expected Issues**: None (WebKit has excellent compatibility)

#### Slack  
- **Text Areas**: Message compose, thread replies, search, channel descriptions
- **Special Cases**: Emoji picker open, slash commands
- **Expected Issues**: None (Electron apps generally work well)

#### TextEdit
- **Text Areas**: Document area (both plain text and rich text modes)
- **Special Cases**: Document with complex formatting
- **Expected Issues**: None (reference Cocoa text view implementation)

#### Mail
- **Text Areas**: Compose message, reply/forward, search
- **Special Cases**: Rich text formatting active, attachments present
- **Expected Issues**: None (standard Cocoa text views)

#### Terminal
- **Text Areas**: Command line, interactive applications (vim, nano)
- **Special Cases**: Within tmux/screen sessions, SSH connections
- **Expected Issues**: Possible focus issues in certain contexts

## Performance Validation

### Latency Requirements
- **Target**: ≤1ms per character for mapped characters
- **Test Method**: Insert 50-character string and measure total time
- **Calculation**: Total time ÷ character count should be ≤1ms

### Memory Usage
- **Target**: ≤700MB peak during transcription
- **Test Method**: Monitor memory before, during, and after large text insertion
- **Tools**: Activity Monitor or automated memory tracking

### CPU Utilization
- **Target**: <150% core utilization during transcription
- **Test Method**: Monitor CPU usage during intensive text insertion
- **Tools**: Activity Monitor or automated performance monitoring

## Troubleshooting

### Common Issues

#### Accessibility Permission Errors
```
Error: Accessibility permissions required for integration testing
Solution: Grant accessibility permissions to test runner application
```

#### Text Insertion Failures
```
Issue: Text not appearing in target application
Diagnosis: 
1. Check if application has focus
2. Verify cursor is in text input area
3. Confirm accessibility permissions
4. Check for modal dialogs blocking input
```

#### Performance Issues
```
Issue: Slow text insertion or system lag
Diagnosis:
1. Monitor CPU usage (should be <150%)
2. Check memory usage (should be <700MB)
3. Verify no other intensive processes running
4. Test with shorter text samples
```

#### Unicode Character Problems
```
Issue: Emojis or accented characters not appearing
Diagnosis:
1. Verify application supports Unicode
2. Check font availability
3. Test pasteboard fallback functionality
4. Validate character encoding
```

## Compatibility Matrix

| Application | Bundle ID | Compatibility | Notes |
|-------------|-----------|--------------|-------|
| VS Code | com.microsoft.VSCode | ✅ Full | All text areas |
| Safari | com.apple.Safari | ✅ Full | All web inputs |
| Slack | com.tinyspeck.slackmacgap | ✅ Full | All message areas |
| TextEdit | com.apple.TextEdit | ✅ Full | Reference implementation |
| Mail | com.apple.mail | ✅ Full | All compose areas |
| Terminal | com.apple.Terminal | ✅ Full | Command line input |

## Report Generation

### Automated Report
```bash
swift test --filter testAllApplicationsComprehensiveCompatibility 2>&1 | grep "Compatibility Report"
```

### Manual Report Template
```markdown
# WhisperNode Integration Test Report

**Date**: [Test Date]
**Tester**: [Tester Name]
**Build**: [App Version]

## Summary
- Applications Tested: X/Y
- Overall Compatibility: XX.X%
- PRD Requirement (≥95%): ✅/❌

## Detailed Results
[For each application, record:]
- Application: [Name]
- Version: [Version]
- Basic Text: ✅/❌
- Special Chars: ✅/❌  
- Unicode: ✅/❌
- Formatting: ✅/❌
- Performance: ✅/❌
- Notes: [Any issues or observations]

## Issues Found
[List any compatibility issues or failures]

## Recommendations
[Suggested improvements or fixes]
```

## Continuous Integration

### CI Test Configuration
```yaml
# Example GitHub Actions workflow step
- name: Run Integration Tests
  run: |
    # Grant accessibility permissions (automated setup)
    # Run test suite
    swift test --filter SystemIntegrationTests
    swift test --filter IntegrationPerformanceTests
  env:
    INTEGRATION_TEST_MODE: true
```

### Test Data Collection
- Store test results in structured format (JSON/CSV)
- Track performance metrics over time
- Monitor compatibility regression
- Generate trend reports

This testing guide ensures comprehensive validation of WhisperNode's integration capabilities across the macOS ecosystem while meeting all PRD requirements for compatibility and performance.