#!/bin/bash

# Verify Code Signing Script for Whisper Node
# This script thoroughly checks the code signing and notarization status

set -euo pipefail

# Configuration
APP_PATH="${1:-}"

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

log_section() {
    echo -e "\n${BLUE}===== $1 =====${NC}"
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

# Get app info
APP_NAME=$(basename "$APP_PATH" .app)
log_info "Verifying: $APP_NAME at $APP_PATH"

# 1. Basic signature verification
log_section "Basic Signature Verification"
if codesign --verify --verbose "$APP_PATH"; then
    log_info "✅ Basic signature verification passed"
else
    log_error "❌ Basic signature verification failed"
    exit 1
fi

# 2. Deep verification
log_section "Deep Signature Verification"
if codesign --verify --deep --strict --verbose=4 "$APP_PATH" 2>&1; then
    log_info "✅ Deep signature verification passed"
else
    log_error "❌ Deep signature verification failed"
    exit 1
fi

# 3. Display signing information
log_section "Signing Information"
codesign --display --verbose=4 "$APP_PATH" 2>&1 | grep -E "(Identifier|Format|CodeDirectory|Signature|Authority|TeamIdentifier|Timestamp)" || true

# 4. Check entitlements
log_section "Entitlements"
codesign --display --entitlements - "$APP_PATH" 2>&1 | grep -A 50 "<dict>" || {
    log_warning "No entitlements found"
}

# 5. Verify runtime hardening
log_section "Runtime Hardening"
if codesign --display --verbose "$APP_PATH" 2>&1 | grep -q "flags=.*runtime"; then
    log_info "✅ Hardened runtime is enabled"
else
    log_warning "⚠️  Hardened runtime is NOT enabled (required for notarization)"
fi

# 6. Check for unsigned content
log_section "Checking for Unsigned Content"
UNSIGNED_COUNT=$(find "$APP_PATH" -type f -perm +111 -exec codesign -v {} \; 2>&1 | grep -c "not signed" || true)
if [ "$UNSIGNED_COUNT" -eq 0 ]; then
    log_info "✅ No unsigned executables found"
else
    log_error "❌ Found $UNSIGNED_COUNT unsigned executables:"
    find "$APP_PATH" -type f -perm +111 -exec codesign -v {} \; 2>&1 | grep "not signed" || true
fi

# 7. Verify frameworks and libraries
log_section "Frameworks and Libraries"
if [ -d "$APP_PATH/Contents/Frameworks" ]; then
    find "$APP_PATH/Contents/Frameworks" -name "*.dylib" -o -name "*.framework" | while read -r framework; do
        if codesign --verify --verbose "$framework" 2>&1; then
            log_info "✅ $(basename "$framework") is properly signed"
        else
            log_error "❌ $(basename "$framework") signature verification failed"
        fi
    done
else
    log_info "No frameworks directory found"
fi

# 8. Check Gatekeeper
log_section "Gatekeeper Assessment"
if spctl --assess --verbose=4 --type execute "$APP_PATH" 2>&1; then
    log_info "✅ Gatekeeper assessment passed"
else
    log_warning "⚠️  Gatekeeper assessment failed (normal for non-notarized apps)"
fi

# 9. Check for notarization
log_section "Notarization Status"
if spctl --assess --verbose=4 --type execute "$APP_PATH" 2>&1 | grep -q "accepted.*notarized"; then
    log_info "✅ App is notarized"
    
    # Check stapling
    if xcrun stapler validate "$APP_PATH" 2>&1; then
        log_info "✅ Notarization ticket is stapled"
    else
        log_warning "⚠️  Notarization ticket is not stapled"
    fi
else
    log_info "ℹ️  App is not notarized (required for distribution)"
fi

# 10. Security assessment
log_section "Security Assessment"
codesign --verify --verbose=4 "$APP_PATH" 2>&1 | grep -E "(satisfies|designated)" || true

# 11. Check Info.plist
log_section "Info.plist Validation"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [ -f "$INFO_PLIST" ]; then
    BUNDLE_ID=$(defaults read "$INFO_PLIST" CFBundleIdentifier 2>/dev/null || echo "Not found")
    VERSION=$(defaults read "$INFO_PLIST" CFBundleShortVersionString 2>/dev/null || echo "Not found")
    BUILD=$(defaults read "$INFO_PLIST" CFBundleVersion 2>/dev/null || echo "Not found")
    
    log_info "Bundle ID: $BUNDLE_ID"
    log_info "Version: $VERSION (Build $BUILD)"
    
    # Check for required keys
    REQUIRED_KEYS=(
        "CFBundleIdentifier"
        "CFBundleVersion"
        "CFBundleShortVersionString"
        "LSMinimumSystemVersion"
        "CFBundleExecutable"
    )
    
    for key in "${REQUIRED_KEYS[@]}"; do
        if defaults read "$INFO_PLIST" "$key" &>/dev/null; then
            log_info "✅ $key is present"
        else
            log_error "❌ Missing required key: $key"
        fi
    done
else
    log_error "❌ Info.plist not found"
fi

# Summary
log_section "Verification Summary"

ISSUES=0

# Check all critical items
if ! codesign --verify --deep --strict "$APP_PATH" &>/dev/null; then
    log_error "❌ Code signature verification failed"
    ((ISSUES++))
fi

if ! codesign --display --verbose "$APP_PATH" 2>&1 | grep -q "flags=.*runtime"; then
    log_warning "⚠️  Hardened runtime not enabled"
    ((ISSUES++))
fi

if [ "$UNSIGNED_COUNT" -gt 0 ]; then
    log_error "❌ Contains unsigned executables"
    ((ISSUES++))
fi

if [ $ISSUES -eq 0 ]; then
    log_info "✅ All critical checks passed!"
    log_info "The app is properly signed and ready for notarization."
else
    log_error "❌ Found $ISSUES critical issues that need to be fixed."
    exit 1
fi