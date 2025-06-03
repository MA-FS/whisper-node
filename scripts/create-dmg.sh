#!/bin/bash

# Create DMG Installer for Whisper Node
# This script creates a professionally styled .dmg installer

set -euo pipefail

# Configuration
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
DMG_DIR="$BUILD_DIR/dmg"
APP_PATH="${1:-$BUILD_DIR/WhisperNode.app}"
DMG_PATH="$BUILD_DIR/WhisperNode.dmg"
TEMP_DMG_PATH="$BUILD_DIR/WhisperNode-temp.dmg"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check requirements
check_requirements() {
    log_step "Checking requirements..."
    
    if ! command -v create-dmg &> /dev/null; then
        log_error "create-dmg not found. Install with: brew install create-dmg"
        exit 1
    fi
    
    if [ ! -d "$APP_PATH" ]; then
        log_error "App not found at: $APP_PATH"
        log_error "Run build-release.sh first to create the app bundle"
        exit 1
    fi
    
    log_info "All requirements satisfied"
}

# Prepare DMG staging directory
prepare_staging() {
    log_step "Preparing DMG staging directory..."
    
    # Clean and create staging directory
    rm -rf "$DMG_DIR"
    mkdir -p "$DMG_DIR"
    
    # Copy app to staging
    log_info "Copying app to staging directory..."
    cp -R "$APP_PATH" "$DMG_DIR/"
    
    log_info "Staging directory prepared"
}

# Create background image if it doesn't exist
create_background_image() {
    log_step "Checking for background image..."
    
    local bg_path="$PROJECT_DIR/installer-background.png"
    
    if [ ! -f "$bg_path" ]; then
        log_info "Creating default background image..."
        
        # Create a simple background with macOS-style design
        # This is a placeholder - in a real project you'd have a designer create this
        cat > "$PROJECT_DIR/create-background.py" << 'EOF'
#!/usr/bin/env python3
import sys
try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("PIL (Pillow) not available, creating simple background")
    # Create a simple solid color background
    with open("installer-background.png", "w") as f:
        f.write("")  # Empty file as placeholder
    sys.exit(0)

# Create a professional background image
width, height = 800, 400
bg_color = (248, 248, 248)  # Light gray background

# Create image
img = Image.new('RGB', (width, height), bg_color)
draw = ImageDraw.Draw(img)

# Add subtle gradient effect
for y in range(height):
    alpha = int(255 * (1 - y / height * 0.1))
    color = (240, 240, 240) if y < height // 2 else (250, 250, 250)
    draw.line([(0, y), (width, y)], fill=color)

# Save the image
img.save("installer-background.png", "PNG")
print("Background image created")
EOF
        
        if command -v python3 &> /dev/null; then
            cd "$PROJECT_DIR"
            python3 create-background.py
            rm create-background.py
        else
            # Create a minimal background file
            touch "$bg_path"
            log_warning "Created placeholder background (install Pillow for better graphics)"
        fi
    else
        log_info "Background image already exists"
    fi
}

# Create volume icon if it doesn't exist
create_volume_icon() {
    log_step "Checking for volume icon..."
    
    local icon_path="$PROJECT_DIR/installer-icon.icns"
    
    if [ ! -f "$icon_path" ]; then
        log_info "Creating volume icon..."
        
        # Try to extract icon from the app bundle
        local app_icon="$APP_PATH/Contents/Resources/AppIcon.icns"
        if [ -f "$app_icon" ]; then
            cp "$app_icon" "$icon_path"
            log_info "Copied app icon as volume icon"
        else
            # Create a minimal icon file (placeholder)
            touch "$icon_path"
            log_warning "Created placeholder icon (add AppIcon.icns to app bundle for better appearance)"
        fi
    else
        log_info "Volume icon already exists"
    fi
}

# Create the DMG
create_dmg() {
    log_step "Creating DMG installer..."
    
    # Remove existing DMG
    rm -f "$DMG_PATH" "$TEMP_DMG_PATH"
    
    # Get app version for DMG name
    local app_version=""
    if command -v plutil &> /dev/null; then
        app_version=$(plutil -extract CFBundleShortVersionString raw "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "")
    fi
    
    if [ -n "$app_version" ]; then
        DMG_PATH="$BUILD_DIR/WhisperNode-$app_version.dmg"
    fi
    
    log_info "Creating DMG: $(basename "$DMG_PATH")"
    
    # Create DMG with create-dmg (with timeout handling)
    timeout 300 create-dmg \
        --volname "Whisper Node" \
        --volicon "$PROJECT_DIR/installer-icon.icns" \
        --background "$PROJECT_DIR/installer-background.png" \
        --window-pos 200 120 \
        --window-size 800 400 \
        --icon-size 100 \
        --icon "WhisperNode.app" 200 190 \
        --hide-extension "WhisperNode.app" \
        --app-drop-link 600 185 \
        --no-internet-enable \
        "$DMG_PATH" \
        "$DMG_DIR"
    
    if [ $? -eq 0 ]; then
        log_info "DMG created successfully"
    else
        log_error "DMG creation failed"
        exit 1
    fi
}

# Sign the DMG
sign_dmg() {
    log_step "Signing DMG..."
    
    # Get the signing identity
    SIGNING_IDENTITY="${WHISPERNODE_SIGNING_IDENTITY:-Developer ID Application}"
    
    log_info "Signing DMG with identity: $SIGNING_IDENTITY"
    
    # Sign the DMG
    codesign --force --sign "$SIGNING_IDENTITY" \
        --options runtime \
        --timestamp \
        "$DMG_PATH"
    
    if [ $? -eq 0 ]; then
        log_info "DMG signed successfully"
    else
        log_error "DMG signing failed"
        exit 1
    fi
}

# Verify the DMG
verify_dmg() {
    log_step "Verifying DMG..."
    
    # Verify code signature
    if codesign --verify --deep --strict --verbose=4 "$DMG_PATH"; then
        log_info "DMG signature verified"
    else
        log_error "DMG signature verification failed"
        exit 1
    fi
    
    # Test mounting the DMG
    log_info "Testing DMG mount..."
    local mount_point=$(mktemp -d)
    
    if hdiutil attach "$DMG_PATH" -mountpoint "$mount_point" -nobrowse -quiet; then
        log_info "DMG mounted successfully"
        
        # Check that the app is there
        if [ -d "$mount_point/WhisperNode.app" ]; then
            log_info "App found in DMG"
        else
            log_error "App not found in mounted DMG"
            hdiutil detach "$mount_point" -quiet
            exit 1
        fi
        
        # Unmount
        hdiutil detach "$mount_point" -quiet
        log_info "DMG unmounted successfully"
    else
        log_error "Failed to mount DMG for testing"
        exit 1
    fi
}

# Display final information
show_results() {
    log_info "✅ DMG installer created successfully!"
    log_info ""
    log_info "DMG location: $DMG_PATH"
    log_info "DMG size: $(du -h "$DMG_PATH" | cut -f1)"
    
    if command -v codesign &> /dev/null; then
        log_info "Code signature: $(codesign -dvv "$DMG_PATH" 2>&1 | grep "Authority" | head -1 | cut -d= -f2)"
    fi
    
    log_info ""
    log_info "Next steps:"
    log_info "1. Test the installer: open '$DMG_PATH'"
    log_info "2. Notarize for distribution: $PROJECT_DIR/scripts/notarize-app.sh '$DMG_PATH'"
    log_info "3. Distribute to users"
}

# Main execution
main() {
    log_info "Creating DMG installer for Whisper Node"
    log_info "App path: $APP_PATH"
    
    check_requirements
    prepare_staging
    create_background_image
    create_volume_icon
    create_dmg
    sign_dmg
    verify_dmg
    show_results
}

# Run main function
main