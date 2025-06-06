#!/bin/bash

# Build and Sign Script for Whisper Node
# This script creates a properly signed release build

set -euo pipefail

# Configuration
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/WhisperNode.xcarchive"
APP_PATH="$BUILD_DIR/WhisperNode.app"
CONFIGURATION="${1:-Release}"

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

# Check for required tools
check_requirements() {
    log_step "Checking requirements..."
    
    if ! command -v xcodebuild &> /dev/null; then
        log_error "xcodebuild not found. Please install Xcode."
        exit 1
    fi
    
    if ! command -v codesign &> /dev/null; then
        log_error "codesign not found. Please install Xcode command line tools."
        exit 1
    fi
    
    log_info "All requirements satisfied"
}

# Clean previous builds
clean_build() {
    log_step "Cleaning previous builds..."
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    log_info "Build directory cleaned"
}

# Build the Rust library
build_rust() {
    log_step "Building Rust library..."
    
    if [ -f "$PROJECT_DIR/scripts/build-rust.sh" ]; then
        "$PROJECT_DIR/scripts/build-rust.sh"
        log_info "Rust library built successfully"
    else
        log_warning "Rust build script not found, skipping Rust build"
    fi
}

# Build the app
build_app() {
    log_step "Building WhisperNode for $CONFIGURATION..."
    
    cd "$PROJECT_DIR"
    
    # Use Swift Package Manager to build (convert to lowercase for swift build)
    SWIFT_CONFIG=$(echo "$CONFIGURATION" | tr '[:upper:]' '[:lower:]')
    swift build \
        --configuration "$SWIFT_CONFIG" \
        --arch arm64 \
        --build-path "$BUILD_DIR"
    
    if [ $? -eq 0 ]; then
        log_info "Build completed successfully"
    else
        log_error "Build failed"
        exit 1
    fi
}

# Create app bundle structure
create_app_bundle() {
    log_step "Creating app bundle..."
    
    # Create bundle structure
    mkdir -p "$APP_PATH/Contents/MacOS"
    mkdir -p "$APP_PATH/Contents/Resources"
    mkdir -p "$APP_PATH/Contents/Frameworks"
    
    # Find the built executable with safer find options
    EXECUTABLE_PATH=$(find "$BUILD_DIR" -name "WhisperNode" -type f -perm +111 ! -path "*.dSYM*" | head -1)
    
    if [ -z "$EXECUTABLE_PATH" ]; then
        log_error "Built executable not found"
        exit 1
    fi
    
    # Copy executable
    cp "$EXECUTABLE_PATH" "$APP_PATH/Contents/MacOS/WhisperNode"
    
    # Copy Info.plist
    cp "$PROJECT_DIR/Sources/WhisperNode/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
    
    # Copy AppIcon.icns to Resources
    if [ -f "$PROJECT_DIR/Sources/WhisperNode/Resources/AppIcon.icns" ]; then
        cp "$PROJECT_DIR/Sources/WhisperNode/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
        log_info "Copied AppIcon.icns to app bundle"
    fi
    
    # Copy any additional resources (if they exist)
    if [ -d "$PROJECT_DIR/Resources" ]; then
        cp -R "$PROJECT_DIR/Resources/"* "$APP_PATH/Contents/Resources/" 2>/dev/null || true
    fi

    # Copy Sparkle framework if it exists
    SPARKLE_FRAMEWORK_PATH=""
    if [ -d "$BUILD_DIR/arm64-apple-macosx/release/Sparkle.framework" ]; then
        SPARKLE_FRAMEWORK_PATH="$BUILD_DIR/arm64-apple-macosx/release/Sparkle.framework"
    elif [ -d "$BUILD_DIR/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" ]; then
        SPARKLE_FRAMEWORK_PATH="$BUILD_DIR/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
    fi

    if [ -n "$SPARKLE_FRAMEWORK_PATH" ]; then
        cp -R "$SPARKLE_FRAMEWORK_PATH" "$APP_PATH/Contents/Frameworks/"
        log_info "Copied Sparkle framework to app bundle"
    else
        log_warning "Sparkle framework not found in build directory"
        log_warning "App will build but auto-update functionality will not be available"
        log_warning "To resolve: ensure Sparkle is properly configured in your Swift Package dependencies"
        
        # Check if this is a critical framework for this configuration
        if [ "$CONFIGURATION" = "Release" ] && [ "${REQUIRE_SPARKLE:-false}" = "true" ]; then
            log_error "CRITICAL: Sparkle framework is required for Release builds but was not found"
            log_error "Set REQUIRE_SPARKLE=false to allow builds without Sparkle, or fix the framework path"
            exit 1
        fi
    fi

    # Copy Rust library if it exists
    if [ -f "$PROJECT_DIR/whisper-rust/target/aarch64-apple-darwin/release/libwhisper_rust.dylib" ]; then
        cp "$PROJECT_DIR/whisper-rust/target/aarch64-apple-darwin/release/libwhisper_rust.dylib" "$APP_PATH/Contents/Frameworks/"
        
        # Update dylib install name
        install_name_tool -id "@executable_path/../Frameworks/libwhisper_rust.dylib" \
            "$APP_PATH/Contents/Frameworks/libwhisper_rust.dylib"
        
        # Update executable to reference the dylib (detect the actual path dynamically)
        RUST_LIB_PATH=$(otool -L "$APP_PATH/Contents/MacOS/WhisperNode" | grep libwhisper_rust.dylib | awk '{print $1}' | head -1)
        if [ -n "$RUST_LIB_PATH" ]; then
            log_info "Updating library reference from: $RUST_LIB_PATH"
            install_name_tool -change \
                "$RUST_LIB_PATH" \
                "@executable_path/../Frameworks/libwhisper_rust.dylib" \
                "$APP_PATH/Contents/MacOS/WhisperNode"
        else
            log_warning "Could not find libwhisper_rust.dylib reference in executable"
        fi
    fi
    
    log_info "App bundle created"
}

# Sign the app bundle
sign_app() {
    log_step "Signing app bundle..."
    
    # Get the signing identity from environment or use default
    SIGNING_IDENTITY="${WHISPERNODE_SIGNING_IDENTITY:-}"

    if [ -z "$SIGNING_IDENTITY" ]; then
        # Check if we have any valid signing identities
        if security find-identity -v -p codesigning | grep -qE 'Developer ID Application|Apple Development'; then
            if [ "$CONFIGURATION" = "Release" ]; then
                SIGNING_IDENTITY="Developer ID Application"
            else
                SIGNING_IDENTITY="Apple Development"
            fi
        else
            # Use ad-hoc signing for local development
            log_warning "No valid signing identity found, using ad-hoc signing"
            SIGNING_IDENTITY="-"
        fi
    fi
    
    # Choose appropriate entitlements file
    if [ "$SIGNING_IDENTITY" = "-" ]; then
        ENTITLEMENTS_FILE="$PROJECT_DIR/Sources/WhisperNode/Resources/WhisperNode-dev.entitlements"
        log_info "Using development entitlements for ad-hoc signing"
        log_warning "SECURITY WARNING: Development entitlements disable critical security features"
        log_warning "These should NEVER be used in production builds"
    else
        ENTITLEMENTS_FILE="$PROJECT_DIR/Sources/WhisperNode/Resources/WhisperNode.entitlements"
        log_info "Using production entitlements for proper signing"
        
        # Validate we're not accidentally using dev entitlements with production signing
        if [[ "$ENTITLEMENTS_FILE" == *"-dev.entitlements" ]]; then
            log_error "SECURITY ERROR: Development entitlements cannot be used with production signing"
            log_error "This would create a security vulnerability in the distributed app"
            exit 1
        fi
    fi
    
    # Verify entitlements file exists
    if [ ! -f "$ENTITLEMENTS_FILE" ]; then
        log_error "Entitlements file not found: $ENTITLEMENTS_FILE"
        exit 1
    fi

    # Sign any embedded frameworks first
    if [ -d "$APP_PATH/Contents/Frameworks" ]; then
        find "$APP_PATH/Contents/Frameworks" \( -name "*.dylib" -o -name "*.framework" \) -print0 | while IFS= read -r -d '' framework; do
            log_info "Signing framework: $(basename "$framework")"
            if [ "$SIGNING_IDENTITY" = "-" ]; then
                # Ad-hoc signing
                codesign --force --sign "$SIGNING_IDENTITY" "$framework"
            else
                # Full signing with entitlements
                codesign --force --deep --sign "$SIGNING_IDENTITY" \
                    --entitlements "$ENTITLEMENTS_FILE" \
                    --options runtime \
                    --timestamp \
                    "$framework"
            fi
        done
    fi

    # Sign the main app
    log_info "Signing main app with identity: $SIGNING_IDENTITY"
    if [ "$SIGNING_IDENTITY" = "-" ]; then
        # Ad-hoc signing with development entitlements
        codesign --force --sign "$SIGNING_IDENTITY" \
            --entitlements "$ENTITLEMENTS_FILE" \
            "$APP_PATH"
    else
        # Full signing with runtime options
        codesign --force --deep --sign "$SIGNING_IDENTITY" \
            --entitlements "$ENTITLEMENTS_FILE" \
            --options runtime \
            --timestamp \
            "$APP_PATH"
    fi
    
    if [ $? -eq 0 ]; then
        log_info "App signed successfully"
    else
        log_error "Code signing failed"
        exit 1
    fi
}

# Verify the signed app
verify_app() {
    log_step "Verifying signed app..."
    
    # Verify code signature
    if codesign --verify --deep --strict --verbose=4 "$APP_PATH"; then
        log_info "Code signature verified"
    else
        log_error "Code signature verification failed"
        exit 1
    fi
    
    # Check entitlements
    log_info "Checking entitlements..."
    if ! codesign -d --entitlements - "$APP_PATH" 2>&1 | grep -q "com.apple.security.device.microphone"; then
        log_error "Microphone entitlement not found"
        exit 1
    fi
    
    # Display signing info
    log_info "Signing information:"
    codesign -dvv "$APP_PATH" 2>&1 | grep -E "(Authority|TeamIdentifier|Timestamp)"
}

# Main execution
main() {
    log_info "Building WhisperNode $CONFIGURATION build"
    log_info "Project directory: $PROJECT_DIR"
    
    check_requirements
    clean_build
    build_rust
    build_app
    create_app_bundle
    sign_app
    verify_app
    
    log_info "✅ Build completed successfully!"
    log_info "App location: $APP_PATH"
    
    if [ "$CONFIGURATION" = "Release" ]; then
        log_info ""
        log_info "Next steps for distribution:"
        log_info "1. Test the app: open '$APP_PATH'"
        log_info "2. Notarize the app: $PROJECT_DIR/scripts/notarize-app.sh '$APP_PATH'"
        log_info "3. Create DMG: $PROJECT_DIR/scripts/create-dmg.sh '$APP_PATH'"
    fi
}

# Run main function
main