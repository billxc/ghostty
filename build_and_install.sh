#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$SCRIPT_DIR/macos/Ghostty.xcodeproj"
SCHEME="Ghostty"
CONFIG="Release"
DEST="$HOME/Applications"

cd "$SCRIPT_DIR"

echo "==> Building Zig core (ReleaseFast)..."
zig build -Doptimize=ReleaseFast -Demit-macos-app=false

echo "==> Building Ghostty..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" build 2>&1 | tail -5

BUILD_DIR=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" -showBuildSettings 2>/dev/null \
    | grep "BUILT_PRODUCTS_DIR" | head -1 | awk '{print $NF}')

APP="$BUILD_DIR/Ghostty.app"

if [ ! -d "$APP" ]; then
    echo "ERROR: Build product not found at $APP"
    exit 1
fi

echo "==> Copying to $DEST/"
rm -rf "$DEST/Ghostty.app"
cp -R "$APP" "$DEST/Ghostty.app"

echo "==> Re-signing app bundle..."
codesign --force --deep --sign - "$DEST/Ghostty.app"

echo "==> Done! Please restart Ghostty manually."
