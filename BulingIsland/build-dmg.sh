#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="BulingIsland"
VERSION=$(defaults read "$SCRIPT_DIR/$APP_NAME/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")
DMG_NAME="${APP_NAME}_v${VERSION}.dmg"
DMG_DIR="$SCRIPT_DIR/dist"
DMG_PATH="$DMG_DIR/$DMG_NAME"
STAGING_DIR="$SCRIPT_DIR/.dmg-staging"

# ── Step 1: Build app bundle ──
echo "==> Building $APP_NAME (release)..."
bash "$SCRIPT_DIR/build.sh"

APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: app bundle not found at $APP_BUNDLE"
    exit 1
fi

# ── Step 2: Prepare DMG staging directory ──
echo "==> Preparing DMG contents..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

cp -a "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# ── Step 3: Create DMG ──
echo "==> Creating DMG..."
mkdir -p "$DMG_DIR"
rm -f "$DMG_PATH"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

# ── Step 4: Cleanup ──
rm -rf "$STAGING_DIR"

echo ""
echo "==> Done!"
echo "    DMG: $DMG_PATH"
echo "    Size: $(du -h "$DMG_PATH" | cut -f1)"
echo ""
echo "    To install: open the DMG and drag $APP_NAME to Applications"
