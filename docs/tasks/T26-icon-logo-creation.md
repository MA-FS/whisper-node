# T26: Icon/Logo Creation

## Overview
Create professional icons and logos for the WhisperNode application, including app icons for macOS and installer graphics for the DMG distribution.

## Requirements

### 1. Icon Format and Sizes for macOS
- **Primary Format**: ICNS file (Apple Icon Image format)
- **Required Sizes**: Multiple resolutions in a single ICNS file
  - 16x16 pixels
  - 32x32 pixels  
  - 64x64 pixels
  - 128x128 pixels
  - 256x256 pixels
  - 512x512 pixels
  - 1024x1024 pixels
- **Resolution Variants**: Each size should have both standard (@1x) and high-resolution (@2x) versions
- **Color Depth**: Support for both 32-bit color and grayscale variants

### 2. Visual Design Elements
Consider incorporating these elements for a speech-to-text application:

#### Core Elements
- **Sound Wave**: Audio visualization element (waveform, frequency bars, or sound ripples)
- **Text Symbol**: Document, text lines, or typing cursor to represent transcription
- **Microphone**: Optional microphone icon for audio input representation
- **Whisper Branding**: Elements that align with OpenAI Whisper model aesthetic

#### Design Principles
- **Clean & Professional**: Modern, minimalist design suitable for productivity tools
- **Scalability**: Design must remain clear and recognizable at 16x16 pixels
- **Platform Consistency**: Follow macOS design guidelines and visual language
- **Color Scheme**: Professional palette that works well in both light and dark modes

### 3. Required Files and Locations

#### Application Icon
- **File**: `AppIcon.icns`
- **Location**: `Sources/WhisperNode/Resources/`
- **Purpose**: Main application icon displayed in Dock, Finder, and system dialogs

#### Installer Icon  
- **File**: `installer-icon.icns`
- **Location**: Project root directory
- **Purpose**: DMG volume icon for the installer package

## Implementation Steps

### Step 1: Design Creation
1. Create high-resolution source artwork (minimum 1024x1024, preferably vector-based)
2. Design with scalability in mind - test readability at smallest sizes
3. Create variations for different contexts if needed
4. Export master artwork in PNG format at 1024x1024 resolution

### Step 2: Icon Generation Tools Setup
Install required tools for ICNS generation:

```bash
# Install iconutil (part of Xcode Command Line Tools)
xcode-select --install

# Alternative: Install ImageMagick for additional format support
brew install imagemagick
```

### Step 3: Multi-Resolution Generation
Create a script to generate all required sizes from source artwork:

```bash
#!/bin/bash
# generate-icons.sh

SOURCE_IMAGE="icon-source.png"
ICONSET_DIR="AppIcon.iconset"

# Create iconset directory
mkdir -p "$ICONSET_DIR"

# Generate all required sizes
sips -z 16 16     "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_16x16.png"
sips -z 32 32     "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_16x16@2x.png"
sips -z 32 32     "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_32x32.png"
sips -z 64 64     "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_32x32@2x.png"
sips -z 128 128   "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_128x128.png"
sips -z 256 256   "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_128x128@2x.png"
sips -z 256 256   "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_256x256.png"
sips -z 512 512   "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_256x256@2x.png"
sips -z 512 512   "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_512x512.png"
sips -z 1024 1024 "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_512x512@2x.png"

# Convert iconset to ICNS
iconutil -c icns "$ICONSET_DIR"

# Clean up
rm -rf "$ICONSET_DIR"
```

### Step 4: File Placement
1. Place `AppIcon.icns` in `Sources/WhisperNode/Resources/`
2. Place `installer-icon.icns` in project root
3. Verify file permissions and accessibility

### Step 5: Build Integration Verification
The existing build scripts already support these icons:
- **App Bundle**: Automatically includes `AppIcon.icns` from Resources directory
- **DMG Creation**: Looks for `installer-icon.icns` in project root for volume icon

## Quality Assurance

### Testing Checklist
- [ ] Icons display correctly at all sizes (16px to 1024px)
- [ ] Icons remain clear and recognizable at smallest sizes
- [ ] Colors work well in both light and dark system themes
- [ ] ICNS files are properly formatted and contain all required sizes
- [ ] App icon appears correctly in Dock, Finder, and About dialog
- [ ] DMG volume icon displays properly when mounted
- [ ] No visual artifacts or pixelation at any size
- [ ] Icons follow macOS design guidelines

### File Validation
```bash
# Verify ICNS file structure
iconutil -l AppIcon.icns
iconutil -l installer-icon.icns

# Check file sizes and formats
file AppIcon.icns installer-icon.icns
ls -la *.icns
```

## Dependencies
- Xcode Command Line Tools (for `iconutil` and `sips`)
- High-resolution source artwork
- Optional: Design software (Sketch, Figma, Adobe Illustrator, etc.)
- Optional: ImageMagick for additional format support

## Deliverables
1. `AppIcon.icns` - Main application icon
2. `installer-icon.icns` - DMG volume icon  
3. Source artwork files (PNG/vector formats)
4. Icon generation script
5. Documentation of design decisions and usage guidelines

## Notes
- Icons should be created before final app bundle testing
- Consider creating additional marketing materials using the same visual identity
- Keep source files in version control for future updates
- Test icons on different macOS versions and display densities
- Consider accessibility requirements for color contrast and clarity

## Status
- [ ] Design concept created
- [ ] Source artwork completed
- [ ] Icon generation script developed
- [ ] ICNS files generated and placed
- [ ] Build integration verified
- [ ] Quality assurance completed
