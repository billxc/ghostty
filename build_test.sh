#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$SCRIPT_DIR/macos/Ghostty.xcodeproj"
SCHEME="Ghostty"
CONFIG="Debug"
DEST="$SCRIPT_DIR/build"

cd "$SCRIPT_DIR"

# --swift-only: skip Zig build, only rebuild Swift/macOS layer
if [ "$1" != "--swift-only" ]; then
    echo "==> Building Zig core..."
    zig build -Demit-macos-app=false
else
    echo "==> Skipping Zig (--swift-only)"
fi

echo "==> Building macOS app (Debug)..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" build 2>&1 | tail -20

BUILD_DIR=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" -showBuildSettings 2>/dev/null \
    | grep "BUILT_PRODUCTS_DIR" | head -1 | awk '{print $NF}')

APP="$BUILD_DIR/Ghostty.app"

if [ ! -d "$APP" ]; then
    echo "ERROR: Build product not found at $APP"
    exit 1
fi

mkdir -p "$DEST"
rm -rf "$DEST/Ghostty.app"
cp -R "$APP" "$DEST/Ghostty.app"

echo "==> Build succeeded! App at $DEST/Ghostty.app"
