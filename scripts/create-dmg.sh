#!/bin/bash

# Create DMG Installer for Whisper Node
# This script creates a professionally styled .dmg installer with proper error handling
#
# Usage: ./create-dmg.sh [APP_PATH]
#
# Requirements:
#   - create-dmg (install via: brew install create-dmg)
#   - Valid macOS app bundle
#   - Xcode Command Line Tools (for codesign)
#   - Optional: WHISPERNODE_SIGNING_IDENTITY environment variable
#
# Examples:
#   ./create-dmg.sh build/WhisperNode.app
#   WHISPERNODE_SIGNING_IDENTITY="My Developer ID" ./create-dmg.sh build/WhisperNode.app

set -euo pipefail
set -o errtrace

# Configuration
# shellcheck disable=SC2155
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
DMG_DIR="$BUILD_DIR/dmg"
APP_PATH="${1:-$BUILD_DIR/WhisperNode.app}"
FINAL_DMG_PATH="$BUILD_DIR/WhisperNode.dmg"

# DMG Layout Configuration (coordinates for professional installer appearance)
WINDOW_POS_X=200          # Horizontal position of installer window
WINDOW_POS_Y=120          # Vertical position of installer window  
WINDOW_WIDTH=800          # Width of installer window
WINDOW_HEIGHT=400         # Height of installer window
ICON_SIZE=100            # Size of application icon in installer
APP_ICON_X=200           # X position of app icon
APP_ICON_Y=190           # Y position of app icon
APPLICATIONS_LINK_X=600  # X position of Applications folder shortcut
APPLICATIONS_LINK_Y=185  # Y position of Applications folder shortcut
DMG_TIMEOUT="${DMG_TIMEOUT:-300}"  # Timeout for DMG creation (default: 5 minutes, configurable via env var)

# Cleanup function for error handling
TEMP_FILES=()
cleanup() {
    local exit_code=$?
    if [ ${#TEMP_FILES[@]} -gt 0 ]; then
        log_info "Cleaning up temporary files..."
        for temp_file in "${TEMP_FILES[@]}"; do
            [[ -f "$temp_file" || -d "$temp_file" ]] && rm -rf "$temp_file"
        done
    fi
    
    # Unmount any mounted DMGs
    if mount | grep -q "dmg\."; then
        log_info "Cleaning up mounted DMG volumes..."
        for volume in $(mount | grep "dmg\." | awk '{print $3}'); do
            hdiutil detach "$volume" -quiet 2>/dev/null || true
        done
    fi
    
    exit $exit_code
}

# Set up cleanup trap
trap cleanup EXIT ERR

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

# Check requirements and validate inputs
check_requirements() {
    log_step "Checking requirements..."
    
    # Check required tools
    local missing_tools=()
    
    if ! command -v create-dmg &> /dev/null; then
        missing_tools+=("create-dmg (install with: brew install create-dmg)")
    fi
    
    if ! command -v codesign &> /dev/null; then
        missing_tools+=("codesign (install Xcode Command Line Tools)")
    fi
    
    if ! command -v hdiutil &> /dev/null; then
        missing_tools+=("hdiutil (part of macOS)")
    fi
    
    if ! command -v plutil &> /dev/null; then
        missing_tools+=("plutil (part of macOS)")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools:"
        for tool in "${missing_tools[@]}"; do
            log_error "  - $tool"
        done
        exit 1
    fi
    
    # Validate app bundle structure
    if [ ! -d "$APP_PATH" ]; then
        log_error "App not found at: $APP_PATH"
        log_error "Run build-release.sh first to create the app bundle"
        exit 1
    fi
    
    # Validate app bundle structure (Critical Issue #C3)
    if [ ! -f "$APP_PATH/Contents/Info.plist" ]; then
        log_error "Invalid app bundle: Missing Contents/Info.plist"
        log_error "Path: $APP_PATH"
        exit 1
    fi
    
    # Validate app bundle identifier
    if ! plutil -lint "$APP_PATH/Contents/Info.plist" >/dev/null 2>&1; then
        log_error "Invalid app bundle: Corrupted Info.plist"
        exit 1
    fi
    
    # Validate we're in the expected directory (security check)
    if [[ "$(basename "$PROJECT_DIR")" != "whisper-node" ]]; then
        log_error "Script must be run from whisper-node project directory"
        log_error "Current directory: $(basename "$PROJECT_DIR")"
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
        
        # Security-enhanced background creation (fixes Critical Issue #C1)
        local python_script="$PROJECT_DIR/create-background.py"
        TEMP_FILES+=("$python_script")
        
        # Validate execution context before creating script
        if [[ "$(basename "$PWD")" != "whisper-node" ]]; then
            log_error "Security check failed: Must be in whisper-node directory"
            exit 1
        fi
        
        cat > "$python_script" << 'EOF'
#!/usr/bin/env python3
import sys
import os

# Security validation
if not os.path.basename(os.getcwd()) == "whisper-node":
    print("Error: Script must be run from whisper-node directory")
    sys.exit(1)

try:
    from PIL import Image, ImageDraw
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

def create_professional_background():
    """Create a professional macOS-style background image."""
    if not HAS_PIL:
        print("PIL (Pillow) not available - skipping background creation")
        return False
    
    # Create professional gradient background
    width, height = 800, 400
    img = Image.new('RGB', (width, height), (248, 248, 248))
    draw = ImageDraw.Draw(img)
    
    # Subtle vertical gradient
    for y in range(height):
        gray_value = int(248 - (y / height) * 8)  # 248 to 240
        color = (gray_value, gray_value, gray_value)
        draw.line([(0, y), (width, y)], fill=color)
    
    # Add subtle border
    border_color = (220, 220, 220)
    draw.rectangle([0, 0, width-1, height-1], outline=border_color, width=1)
    
    # Save the image
    img.save("installer-background.png", "PNG")
    print("Professional background image created (800x400)")
    return True

if __name__ == "__main__":
    if not create_professional_background():
        sys.exit(1)
EOF
        
        if command -v python3 &> /dev/null; then
            cd "$PROJECT_DIR"
            if python3 "$python_script"; then
                log_info "Background image created successfully"
            else
                log_warning "Failed to create background image with Python"
                # Skip background parameter instead of creating empty file
                log_info "DMG will be created without custom background"
                rm -f "$bg_path"  # Remove any empty files
            fi
            rm -f "$python_script"
        else
            log_warning "Python3 not available - skipping background creation"
            log_info "DMG will be created without custom background"
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
    rm -f "$FINAL_DMG_PATH"
    
    # Get app version for DMG name
    local app_version=""
    if command -v plutil &> /dev/null; then
        app_version=$(plutil -extract CFBundleShortVersionString raw "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "")
    fi
    
    if [ -n "$app_version" ]; then
        FINAL_DMG_PATH="$BUILD_DIR/WhisperNode-$app_version.dmg"
    fi
    
    log_info "Creating DMG: $(basename "$FINAL_DMG_PATH")"
    
    # Build create-dmg command with conditional parameters
    local create_dmg_args=(
        --volname "Whisper Node"
        --window-pos "$WINDOW_POS_X" "$WINDOW_POS_Y"
        --window-size "$WINDOW_WIDTH" "$WINDOW_HEIGHT"
        --icon-size "$ICON_SIZE"
        --icon "WhisperNode.app" "$APP_ICON_X" "$APP_ICON_Y"
        --hide-extension "WhisperNode.app"
        --app-drop-link "$APPLICATIONS_LINK_X" "$APPLICATIONS_LINK_Y"
        --no-internet-enable
    )
    
    # Add background image if it exists and is valid
    if [ -f "$PROJECT_DIR/installer-background.png" ] && [ -s "$PROJECT_DIR/installer-background.png" ]; then
        create_dmg_args+=(--background "$PROJECT_DIR/installer-background.png")
        log_info "Using custom background image"
    else
        log_info "No background image - using default appearance"
    fi
    
    # Add volume icon if it exists
    if [ -f "$PROJECT_DIR/installer-icon.icns" ] && [ -s "$PROJECT_DIR/installer-icon.icns" ]; then
        create_dmg_args+=(--volicon "$PROJECT_DIR/installer-icon.icns")
        log_info "Using custom volume icon"
    else
        log_info "No volume icon - using default"
    fi
    
    # Create DMG with timeout handling (use gtimeout if available, otherwise skip timeout)
    local timeout_exit_code=0
    log_info "Starting DMG creation..."

    # Check if timeout command is available (gtimeout on macOS via brew)
    if command -v gtimeout &> /dev/null; then
        if ! gtimeout "$DMG_TIMEOUT" create-dmg "${create_dmg_args[@]}" "$FINAL_DMG_PATH" "$DMG_DIR"; then
            timeout_exit_code=$?
            if [ $timeout_exit_code -eq 124 ]; then
                log_error "DMG creation timed out after $DMG_TIMEOUT seconds"
                log_error "Try reducing app size or increasing timeout with DMG_TIMEOUT environment variable"
                exit 1
            elif [ $timeout_exit_code -ne 0 ]; then
                log_error "DMG creation failed with exit code $timeout_exit_code"
                log_error "Check the create-dmg output above for details"
                exit 1
            fi
        fi
    else
        # Run without timeout
        log_warning "gtimeout not found - DMG creation will proceed without timeout protection"
        log_warning "Install with: brew install coreutils"
        if ! create-dmg "${create_dmg_args[@]}" "$FINAL_DMG_PATH" "$DMG_DIR"; then
            log_error "DMG creation failed"
            log_error "Check the create-dmg output above for details"
            exit 1
        fi
    fi
    
    log_info "DMG created successfully"
}

# Sign the DMG
sign_dmg() {
    log_step "Signing DMG..."
    
    # Enhanced signing validation (fixes Potential Issue #P1)
    if ! command -v codesign &> /dev/null; then
        log_error "codesign not found. Install Xcode Command Line Tools"
        exit 1
    fi
    
    # Get the signing identity
    local signing_identity="${WHISPERNODE_SIGNING_IDENTITY:-}"

    if [ -z "$signing_identity" ]; then
        # Check if we have any valid signing identities
        if security find-identity -v -p codesigning | grep -q "Developer ID Application\|Apple Development"; then
            signing_identity="Developer ID Application"
        else
            # Use ad-hoc signing for local development
            log_warning "No valid signing identity found, using ad-hoc signing for DMG"
            signing_identity="-"
        fi
    fi

    # Validate signing identity if not ad-hoc
    if [ "$signing_identity" != "-" ] && ! security find-identity -v -p codesigning | grep -q "$signing_identity"; then
        log_warning "Signing identity '$signing_identity' not found"
        log_warning "Available identities:"
        security find-identity -v -p codesigning | head -10
        log_warning "Falling back to ad-hoc signing"
        signing_identity="-"
    fi
    
    log_info "Signing DMG with identity: $signing_identity"
    
    # Sign the DMG with detailed error handling
    if [ "$signing_identity" = "-" ]; then
        # Ad-hoc signing
        if ! codesign --force --sign "$signing_identity" "$FINAL_DMG_PATH"; then
            local sign_exit_code=$?
            log_error "DMG ad-hoc signing failed with exit code $sign_exit_code"
            exit 1
        fi
    else
        # Full signing with runtime options
        if ! codesign --force --sign "$signing_identity" \
            --options runtime \
            --timestamp \
            "$FINAL_DMG_PATH"; then
            local sign_exit_code=$?
            log_error "DMG signing failed with exit code $sign_exit_code"

            # Provide specific guidance for common signing failures
            case $sign_exit_code in
                1)
                    log_error "Common causes: Invalid signing identity, expired certificate, or keychain access"
                    log_error "Try: security unlock-keychain ~/Library/Keychains/login.keychain-db"
                    ;;
                2)
                    log_error "File not found or access denied"
                    log_error "Check that the DMG file exists and is accessible"
                    ;;
                *)
                    log_error "Unknown signing error. Check codesign documentation"
                    ;;
            esac
            exit 1
        fi
    fi
    
    log_info "DMG signed successfully"
}

# Verify the DMG
verify_dmg() {
    log_step "Verifying DMG..."
    
    # Verify code signature
    if codesign --verify --deep --strict --verbose=4 "$FINAL_DMG_PATH"; then
        log_info "DMG signature verified"
    else
        log_error "DMG signature verification failed"
        exit 1
    fi
    
    # Test mounting the DMG with proper cleanup
    log_info "Testing DMG mount..."
    
    # Fix ShellCheck SC2155 warning by separating declaration and assignment
    local mount_point
    mount_point=$(mktemp -d)
    TEMP_FILES+=("$mount_point")
    
    # Add cleanup function for this specific mount point
    cleanup_mount() {
        if mount | grep -q "$mount_point"; then
            log_info "Cleaning up test mount: $mount_point"
            hdiutil detach "$mount_point" -quiet 2>/dev/null || true
        fi
        [[ -d "$mount_point" ]] && rmdir "$mount_point" 2>/dev/null || true
    }
    
    if hdiutil attach "$FINAL_DMG_PATH" -mountpoint "$mount_point" -nobrowse -quiet; then
        log_info "DMG mounted successfully at: $mount_point"
        
        # Check that the app is there
        if [ -d "$mount_point/WhisperNode.app" ]; then
            log_info "App found in DMG"
            
            # Verify app bundle structure in DMG
            if [ -f "$mount_point/WhisperNode.app/Contents/Info.plist" ]; then
                log_info "App bundle structure verified in DMG"
            else
                log_warning "App bundle in DMG may be incomplete"
            fi
        else
            log_error "App not found in mounted DMG"
            cleanup_mount
            exit 1
        fi
        
        # Check for Applications link
        if [ -L "$mount_point/Applications" ]; then
            log_info "Applications symlink found in DMG"
        else
            log_warning "Applications symlink not found (may affect installation UX)"
        fi
        
        # Unmount with retry logic
        local unmount_attempts=0
        while mount | grep -q "$mount_point" && [ $unmount_attempts -lt 3 ]; do
            if hdiutil detach "$mount_point" -quiet 2>/dev/null; then
                log_info "DMG unmounted successfully"
                break
            else
                unmount_attempts=$((unmount_attempts + 1))
                log_warning "Unmount attempt $unmount_attempts failed, retrying..."
                sleep 1
            fi
        done
        
        if mount | grep -q "$mount_point"; then
            log_warning "DMG still mounted after verification - may require manual cleanup"
        fi
    else
        log_error "Failed to mount DMG for testing"
        cleanup_mount
        exit 1
    fi
}

# Display final information
show_results() {
    log_info "✅ DMG installer created successfully!"
    log_info ""
    log_info "📦 DMG Details:"
    log_info "   Location: $FINAL_DMG_PATH"
    log_info "   Size: $(du -h "$FINAL_DMG_PATH" | cut -f1)"
    
    # Show signing information
    if command -v codesign &> /dev/null && codesign -dv "$FINAL_DMG_PATH" 2>/dev/null; then
        local authority
        authority=$(codesign -dvv "$FINAL_DMG_PATH" 2>&1 | grep "Authority" | head -1 | cut -d= -f2 || echo "Unknown")
        log_info "   Code signature: $authority"
        
        # Check notarization status
        if spctl -a -t open --context context:primary-signature "$FINAL_DMG_PATH" 2>/dev/null; then
            log_info "   Notarization: ✅ Accepted by Gatekeeper"
        else
            log_info "   Notarization: ⚠️  Not notarized (required for distribution)"
        fi
    else
        log_info "   Code signature: ❌ Not signed"
    fi
    
    # Show app version
    local app_version
    app_version=$(plutil -extract CFBundleShortVersionString raw "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "Unknown")
    log_info "   App version: $app_version"
    
    log_info ""
    log_info "🚀 Next steps:"
    log_info "   1. Test installer: open '$FINAL_DMG_PATH'"
    if [ -f "$PROJECT_DIR/scripts/notarize-app.sh" ]; then
        log_info "   2. Notarize: $PROJECT_DIR/scripts/notarize-app.sh '$FINAL_DMG_PATH'"
    else
        log_info "   2. Notarize with: xcrun notarytool submit '$FINAL_DMG_PATH' --wait"
    fi
    log_info "   3. Distribute to users"
    
    # Security reminder
    if [[ "$FINAL_DMG_PATH" == *"WhisperNode.dmg" ]] && ! codesign -dv "$FINAL_DMG_PATH" 2>/dev/null; then
        log_warning ""
        log_warning "⚠️  DMG is not code signed - users will see security warnings"
        log_warning "   For production distribution, ensure proper code signing setup"
    fi
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