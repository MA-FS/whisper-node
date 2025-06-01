#!/bin/bash

# Build script for Rust whisper FFI library
# Usage: ./scripts/build-rust.sh [debug|release]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$PROJECT_ROOT/whisper-rust"

# Default to release build
BUILD_TYPE="${1:-release}"

echo "Building Rust whisper library ($BUILD_TYPE)..."

cd "$RUST_DIR"

# Ensure we have Rust toolchain for Apple Silicon
# Check if we're on a compatible platform
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Warning: Building for Apple Silicon from non-macOS platform"
fi

if ! rustup target list --installed | grep -q "aarch64-apple-darwin"; then
    echo "Installing aarch64-apple-darwin target..."
    rustup target add aarch64-apple-darwin
fi

# Build the library
if [ "$BUILD_TYPE" = "debug" ]; then
    if ! cargo build --target aarch64-apple-darwin; then
        echo "❌ Debug build failed"
        exit 1
    fi
    LIB_PATH="$RUST_DIR/target/aarch64-apple-darwin/debug"
else
    if ! cargo build --release --target aarch64-apple-darwin; then
        echo "❌ Release build failed"
        exit 1
    fi
    LIB_PATH="$RUST_DIR/target/aarch64-apple-darwin/release"
fi

echo "✅ Rust library built successfully at: $LIB_PATH"

# Verify the library was created
if [ -f "$LIB_PATH/libwhisper_rust.a" ]; then
    echo "✅ Static library: $LIB_PATH/libwhisper_rust.a"
    file "$LIB_PATH/libwhisper_rust.a"
fi

if [ -f "$LIB_PATH/libwhisper_rust.dylib" ]; then
    echo "✅ Dynamic library: $LIB_PATH/libwhisper_rust.dylib"
    file "$LIB_PATH/libwhisper_rust.dylib"
fi

echo "✅ Build complete!"