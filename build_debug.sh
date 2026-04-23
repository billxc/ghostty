#!/bin/bash
set -e

PROJECT="/Users/xiaocw/code/ghostty/macos/Ghostty.xcodeproj"
SCHEME="Ghostty"
CONFIG="Debug"
BUILD_DIR="/Users/xiaocw/code/ghostty/build"

echo "==> Building Ghostty (Debug)..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
    SYMROOT="$BUILD_DIR" \
    build 2>&1 | tail -5

echo "==> Done! App at: $BUILD_DIR/$CONFIG/Ghostty.app"
