#!/bin/bash

# Notarization Script for Whisper Node
# This script handles the notarization process for macOS app distribution

set -euo pipefail

# Configuration
APP_PATH="${1:-}"
BUNDLE_ID="com.whispernode.app"
TEAM_ID="${WHISPERNODE_TEAM_ID:-}"
APPLE_ID="${WHISPERNODE_APPLE_ID:-}"
APP_PASSWORD="${WHISPERNODE_APP_PASSWORD:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Validate inputs
if [ -z "$APP_PATH" ]; then
    log_error "Usage: $0 <path-to-app>"
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    log_error "App not found at: $APP_PATH"
    exit 1
fi

if [ -z "$TEAM_ID" ] || [ -z "$APPLE_ID" ] || [ -z "$APP_PASSWORD" ]; then
    log_error "Missing required environment variables:"
    log_error "  WHISPERNODE_TEAM_ID: Your Apple Developer Team ID"
    log_error "  WHISPERNODE_APPLE_ID: Your Apple ID email"
    log_error "  WHISPERNODE_APP_PASSWORD: App-specific password for notarization"
    exit 1
fi

# Get app name and version
APP_NAME=$(basename "$APP_PATH" .app)
VERSION=$(defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString)
BUILD=$(defaults read "$APP_PATH/Contents/Info" CFBundleVersion)

log_info "Notarizing $APP_NAME version $VERSION ($BUILD)"

# Step 1: Verify code signature
log_info "Verifying code signature..."
if codesign --verify --deep --strict --verbose=4 "$APP_PATH"; then
    log_info "Code signature verified successfully"
else
    log_error "Code signature verification failed"
    exit 1
fi

# Step 2: Check spctl assessment
log_info "Checking Gatekeeper assessment..."
if spctl --assess --verbose=4 --type execute "$APP_PATH" 2>&1 | grep -q "accepted"; then
    log_info "Gatekeeper assessment passed"
else
    log_warning "Gatekeeper assessment failed (expected before notarization)"
fi

# Step 3: Create ZIP for notarization
ZIP_PATH="/tmp/${APP_NAME}_${VERSION}.zip"
log_info "Creating ZIP archive at: $ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# Step 4: Submit for notarization
log_info "Submitting app for notarization..."

# Create temporary keychain item for secure credential handling
KEYCHAIN_PROFILE="whispernode-notarization"
xcrun notarytool store-credentials "$KEYCHAIN_PROFILE" \
    --apple-id "$APPLE_ID" \
    --password "$APP_PASSWORD" \
    --team-id "$TEAM_ID" 2>/dev/null || true

SUBMISSION_INFO=$(xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait 2>&1)

# Extract submission ID
SUBMISSION_ID=$(echo "$SUBMISSION_INFO" | grep "id:" | head -1 | awk '{print $2}')

if [ -z "$SUBMISSION_ID" ]; then
    log_error "Failed to submit for notarization"
    echo "$SUBMISSION_INFO"
    rm -f "$ZIP_PATH"
    exit 1
fi

log_info "Submission ID: $SUBMISSION_ID"

# Step 5: Check notarization status
log_info "Checking notarization status..."
STATUS_INFO=$(xcrun notarytool info "$SUBMISSION_ID" \
    --keychain-profile "$KEYCHAIN_PROFILE" 2>&1)

# Check if notarization was successful
if echo "$STATUS_INFO" | grep -q "status: Accepted"; then
    log_info "Notarization successful!"
else
    log_error "Notarization failed"
    echo "$STATUS_INFO"
    
    # Get detailed log
    log_info "Fetching notarization log..."
    xcrun notarytool log "$SUBMISSION_ID" \
        --keychain-profile "$KEYCHAIN_PROFILE"
    
    rm -f "$ZIP_PATH"
    exit 1
fi

# Step 6: Staple the notarization ticket
log_info "Stapling notarization ticket to app..."
if xcrun stapler staple "$APP_PATH"; then
    log_info "Successfully stapled ticket to app"
else
    log_error "Failed to staple ticket"
    rm -f "$ZIP_PATH"
    exit 1
fi

# Step 7: Verify the stapled app
log_info "Verifying stapled app..."
if xcrun stapler validate "$APP_PATH"; then
    log_info "Stapled app validated successfully"
else
    log_error "Stapled app validation failed"
    rm -f "$ZIP_PATH"
    exit 1
fi

# Final Gatekeeper check
log_info "Final Gatekeeper assessment..."
if spctl --assess --verbose=4 --type execute "$APP_PATH"; then
    log_info "✅ App is now notarized and ready for distribution!"
else
    log_error "Final Gatekeeper assessment failed"
    rm -f "$ZIP_PATH"
    exit 1
fi

# Cleanup
rm -f "$ZIP_PATH"

# Clean up temporary keychain profile
xcrun notarytool delete-credentials "$KEYCHAIN_PROFILE" 2>/dev/null || true

log_info "Notarization complete for $APP_NAME $VERSION"
log_info "The app at $APP_PATH is ready for distribution"