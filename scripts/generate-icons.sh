#!/bin/bash
# generate-icons.sh
# Generate AppIcon.icns and installer-icon.icns from source logo

set -e

SOURCE_IMAGE="Sources/WhisperNode/Resources/whispernode-logo.png"
APP_ICONSET_DIR="AppIcon.iconset"
INSTALLER_ICONSET_DIR="installer-icon.iconset"

echo "🎨 Generating icons from $SOURCE_IMAGE"

# Verify source image exists
if [ ! -f "$SOURCE_IMAGE" ]; then
    echo "❌ Source image not found: $SOURCE_IMAGE"
    exit 1
fi

# Create iconset directories
mkdir -p "$APP_ICONSET_DIR"
mkdir -p "$INSTALLER_ICONSET_DIR"

echo "📐 Generating app icon sizes..."

# Generate app icon sizes
sips -z 16 16     "$SOURCE_IMAGE" --out "$APP_ICONSET_DIR/icon_16x16.png"
sips -z 32 32     "$SOURCE_IMAGE" --out "$APP_ICONSET_DIR/icon_16x16@2x.png"
sips -z 32 32     "$SOURCE_IMAGE" --out "$APP_ICONSET_DIR/icon_32x32.png"
sips -z 64 64     "$SOURCE_IMAGE" --out "$APP_ICONSET_DIR/icon_32x32@2x.png"
sips -z 128 128   "$SOURCE_IMAGE" --out "$APP_ICONSET_DIR/icon_128x128.png"
sips -z 256 256   "$SOURCE_IMAGE" --out "$APP_ICONSET_DIR/icon_128x128@2x.png"
sips -z 256 256   "$SOURCE_IMAGE" --out "$APP_ICONSET_DIR/icon_256x256.png"
sips -z 512 512   "$SOURCE_IMAGE" --out "$APP_ICONSET_DIR/icon_256x256@2x.png"
sips -z 512 512   "$SOURCE_IMAGE" --out "$APP_ICONSET_DIR/icon_512x512.png"
sips -z 1024 1024 "$SOURCE_IMAGE" --out "$APP_ICONSET_DIR/icon_512x512@2x.png"

echo "📐 Generating installer icon sizes..."

# Generate installer icon sizes (same sizes)
sips -z 16 16     "$SOURCE_IMAGE" --out "$INSTALLER_ICONSET_DIR/icon_16x16.png"
sips -z 32 32     "$SOURCE_IMAGE" --out "$INSTALLER_ICONSET_DIR/icon_16x16@2x.png"
sips -z 32 32     "$SOURCE_IMAGE" --out "$INSTALLER_ICONSET_DIR/icon_32x32.png"
sips -z 64 64     "$SOURCE_IMAGE" --out "$INSTALLER_ICONSET_DIR/icon_32x32@2x.png"
sips -z 128 128   "$SOURCE_IMAGE" --out "$INSTALLER_ICONSET_DIR/icon_128x128.png"
sips -z 256 256   "$SOURCE_IMAGE" --out "$INSTALLER_ICONSET_DIR/icon_128x128@2x.png"
sips -z 256 256   "$SOURCE_IMAGE" --out "$INSTALLER_ICONSET_DIR/icon_256x256.png"
sips -z 512 512   "$SOURCE_IMAGE" --out "$INSTALLER_ICONSET_DIR/icon_256x256@2x.png"
sips -z 512 512   "$SOURCE_IMAGE" --out "$INSTALLER_ICONSET_DIR/icon_512x512.png"
sips -z 1024 1024 "$SOURCE_IMAGE" --out "$INSTALLER_ICONSET_DIR/icon_512x512@2x.png"

echo "🔨 Converting iconsets to ICNS..."

# Convert iconsets to ICNS
iconutil -c icns "$APP_ICONSET_DIR"
iconutil -c icns "$INSTALLER_ICONSET_DIR"

echo "📁 Moving icons to target locations..."

# Move AppIcon.icns to Resources directory
mv AppIcon.icns Sources/WhisperNode/Resources/

# Keep installer-icon.icns in project root
mv installer-icon.icns .

echo "🧹 Cleaning up temporary files..."

# Clean up iconset directories
rm -rf "$APP_ICONSET_DIR"
rm -rf "$INSTALLER_ICONSET_DIR"

echo "✅ Icon generation complete!"
echo "   📱 AppIcon.icns → Sources/WhisperNode/Resources/"
echo "   💿 installer-icon.icns → project root"

# Verify generated files
echo ""
echo "🔍 Verifying generated icons..."
iconutil -l Sources/WhisperNode/Resources/AppIcon.icns
echo ""
iconutil -l installer-icon.icns