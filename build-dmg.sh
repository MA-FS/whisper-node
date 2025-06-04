#!/bin/bash

# WhisperNode DMG Builder
# Complete build and DMG creation script for local testing
#
# This script builds the WhisperNode app and creates a DMG installer
# ready for testing on your Mac. It handles all dependencies and
# provides clear feedback throughout the process.
#
# Usage: ./build-dmg.sh [configuration]
#   configuration: Debug (default) or Release
#
# Examples:
#   ./build-dmg.sh           # Build Debug DMG for testing
#   ./build-dmg.sh Release   # Build Release DMG for distribution

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
CONFIGURATION="${1:-Debug}"

# Validate configuration argument
if [[ "$CONFIGURATION" != "Debug" && "$CONFIGURATION" != "Release" ]]; then
    echo -e "\033[0;31m[ERROR]\033[0m Invalid configuration: $CONFIGURATION. Use Debug or Release."
    exit 1
fi

BUILD_DIR="$PROJECT_DIR/build"
APP_PATH="$BUILD_DIR/WhisperNode.app"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
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

log_header() {
    echo -e "${CYAN}${BOLD}$1${NC}"
}

# Error handling
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Build failed with exit code $exit_code"
        log_info "Check the output above for details"
    fi
    exit $exit_code
}

trap cleanup EXIT ERR

# Check if we're in the right directory
check_project_directory() {
    if [[ "$(basename "$PROJECT_DIR")" != "whisper-node" ]]; then
        log_error "This script must be run from the whisper-node project root directory"
        log_error "Current directory: $(basename "$PROJECT_DIR")"
        exit 1
    fi
    
    if [ ! -f "$PROJECT_DIR/Package.swift" ]; then
        log_error "Package.swift not found. Are you in the whisper-node project directory?"
        exit 1
    fi
}

# Check system requirements
check_requirements() {
    log_step "Checking system requirements..."
    
    local missing_tools=()
    
    # Check for Xcode tools
    if ! command -v xcodebuild &> /dev/null; then
        missing_tools+=("xcodebuild (install Xcode from App Store)")
    fi
    
    if ! command -v swift &> /dev/null; then
        missing_tools+=("swift (install Xcode Command Line Tools)")
    fi
    
    if ! command -v codesign &> /dev/null; then
        missing_tools+=("codesign (install Xcode Command Line Tools)")
    fi
    
    # Check for DMG creation tools
    if ! command -v create-dmg &> /dev/null; then
        missing_tools+=("create-dmg (install with: brew install create-dmg)")
    fi
    
    # Check for Rust (optional but recommended)
    if ! command -v cargo &> /dev/null; then
        log_warning "Rust/Cargo not found - Whisper functionality may be limited"
        log_warning "Install Rust from: https://rustup.rs/"
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools:"
        for tool in "${missing_tools[@]}"; do
            log_error "  - $tool"
        done
        log_error ""
        log_error "Install missing tools and run this script again"
        exit 1
    fi
    
    log_info "All required tools found"
}

# Display build information
show_build_info() {
    log_header "🚀 WhisperNode DMG Builder"
    echo
    log_info "Configuration: $CONFIGURATION"
    log_info "Project directory: $PROJECT_DIR"
    log_info "Build directory: $BUILD_DIR"
    log_info "Target app: $APP_PATH"
    echo
    
    if [ "$CONFIGURATION" = "Debug" ]; then
        log_info "Building Debug version for local testing"
        log_info "This build will use ad-hoc code signing"
    else
        log_info "Building Release version for distribution"
        log_info "This build requires proper code signing certificates"
    fi
    echo
}

# Build the application
build_application() {
    log_step "Building WhisperNode application..."
    
    if [ ! -f "$PROJECT_DIR/scripts/build-release.sh" ]; then
        log_error "Build script not found: scripts/build-release.sh"
        exit 1
    fi
    
    # Make build script executable
    chmod +x "$PROJECT_DIR/scripts/build-release.sh"
    
    # Run the build script
    log_info "Running build script with configuration: $CONFIGURATION"
    "$PROJECT_DIR/scripts/build-release.sh" "$CONFIGURATION"
    
    # Verify the app was built
    if [ ! -d "$APP_PATH" ]; then
        log_error "App bundle not found after build: $APP_PATH"
        exit 1
    fi
    
    if [ ! -f "$APP_PATH/Contents/MacOS/WhisperNode" ]; then
        log_error "App executable not found: $APP_PATH/Contents/MacOS/WhisperNode"
        exit 1
    fi
    
    log_info "Application built successfully"
}

# Create DMG installer
create_dmg_installer() {
    log_step "Creating DMG installer..."
    
    if [ ! -f "$PROJECT_DIR/scripts/create-dmg.sh" ]; then
        log_error "DMG creation script not found: scripts/create-dmg.sh"
        exit 1
    fi
    
    # Make DMG script executable
    chmod +x "$PROJECT_DIR/scripts/create-dmg.sh"
    
    # Run the DMG creation script
    log_info "Running DMG creation script..."
    "$PROJECT_DIR/scripts/create-dmg.sh" "$APP_PATH"
    
    log_info "DMG installer created successfully"
}

# Show final results
show_results() {
    log_header "✅ Build Complete!"
    echo
    
    # Find the created DMG
    local dmg_file
    dmg_file=$(find "$BUILD_DIR" -name "*.dmg" -type f | head -1)
    
    if [ -n "$dmg_file" ] && [ -f "$dmg_file" ]; then
        log_info "📦 DMG Installer: $(basename "$dmg_file")"
        log_info "   Location: $dmg_file"
        log_info "   Size: $(du -h "$dmg_file" | cut -f1)"
        echo
        
        log_info "🧪 Testing Instructions:"
        log_info "   1. Open the DMG: open '$dmg_file'"
        log_info "   2. Drag WhisperNode.app to Applications folder"
        log_info "   3. Launch from Applications or Spotlight"
        log_info "   4. Test the audio recording functionality we just fixed"
        echo
        
        if [ "$CONFIGURATION" = "Debug" ]; then
            log_warning "⚠️  Debug Build Notes:"
            log_warning "   - Uses ad-hoc code signing (may show security warnings)"
            log_warning "   - Includes debug symbols (larger file size)"
            log_warning "   - Suitable for local testing only"
        else
            log_info "🚀 Release Build Notes:"
            log_info "   - Optimized for performance"
            log_info "   - Properly code signed (if certificates available)"
            log_info "   - Ready for distribution (after notarization)"
        fi
        echo
        
        log_info "🎯 Audio Testing Focus:"
        log_info "   - Check that dB level bars move when speaking"
        log_info "   - Verify test recording provides detailed feedback"
        log_info "   - Confirm microphone permission flow works"
        log_info "   - Test with different audio input devices"
        
    else
        log_error "DMG file not found in build directory"
        log_error "Check the build output above for errors"
        exit 1
    fi
}

# Main execution
main() {
    show_build_info
    check_project_directory
    check_requirements
    build_application
    create_dmg_installer
    show_results
}

# Run main function
main "$@"
