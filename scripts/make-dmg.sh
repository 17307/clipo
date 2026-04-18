#!/usr/bin/env bash
#
# Package the Release build into a distributable .dmg.
# Run `scripts/build-release.sh` first (or this script will).
#
# Output: build/Clipo-<version>.dmg
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

VERSION="$(sed -n 's/.*MARKETING_VERSION: *"\([^"]*\)".*/\1/p' project.yml | head -1)"
VERSION="${VERSION:-0.0.0}"

BUILD_DIR="$ROOT/build/release"
PRODUCT_DIR="$BUILD_DIR/Build/Products/Release"
APP_PATH="$PRODUCT_DIR/Clipo.app"
CLI_PATH="$PRODUCT_DIR/clipocli"

# Build if missing.
if [ ! -d "$APP_PATH" ] || [ ! -x "$CLI_PATH" ]; then
    echo "→ release build missing; running scripts/build-release.sh"
    bash "$ROOT/scripts/build-release.sh"
fi

STAGING="$ROOT/build/dmg-staging"
DMG_PATH="$ROOT/build/Clipo-$VERSION.dmg"

echo "→ staging $STAGING"
rm -rf "$STAGING"
mkdir -p "$STAGING"

cp -R "$APP_PATH" "$STAGING/Clipo.app"
cp "$CLI_PATH" "$STAGING/clipocli"
ln -s /Applications "$STAGING/Applications"

cat > "$STAGING/README.txt" <<'README'
Clipo — macOS Clipboard Manager

INSTALL
  1. Drag "Clipo.app" onto the "Applications" folder in this window.
  2. Launch Clipo from Applications. The first time, macOS may block
     the app ("unidentified developer"). Right-click the app icon in
     Finder and choose "Open", then "Open" again in the dialog.
  3. Grant Accessibility permission when prompted so Clipo can paste
     into other apps.

CLI (optional)
  The `clipocli` binary lets you talk to the running Clipo app from
  scripts:
      sudo cp clipocli /usr/local/bin/
      clipocli health
      clipocli read
      echo "hi" | clipocli write -

DEFAULT SHORTCUT
  ⇧⌘V toggles the Clipo panel. Change it in Settings → General.

More: https://github.com/ymoon/clipo  (update as needed)
README

echo "→ removing old $DMG_PATH"
rm -f "$DMG_PATH"

echo "→ creating DMG"
hdiutil create \
    -volname "Clipo $VERSION" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH" >/tmp/clipo-dmg.log 2>&1 || {
    tail -40 /tmp/clipo-dmg.log
    echo "✗ hdiutil failed (log: /tmp/clipo-dmg.log)"
    exit 1
}

echo
echo "✓ $DMG_PATH  ($(du -h "$DMG_PATH" | cut -f1))"

# Quick integrity sanity check.
hdiutil verify "$DMG_PATH" >/dev/null 2>&1 && echo "✓ verify passed" || echo "✗ verify failed"
