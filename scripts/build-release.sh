#!/usr/bin/env bash
#
# Build Clipo.app + clipocli in Release configuration and stage the CLI
# binary inside the app's Resources/ directory so users can run
#   /Applications/Clipo.app/Contents/Resources/clipocli
# or symlink it onto their PATH.
#
# Signing: by default we use ad-hoc (CODE_SIGN_IDENTITY="-"). For
# distribution with Gatekeeper + notarization, set DEVELOPMENT_TEAM and
# override CODE_SIGN_IDENTITY to a Developer ID Application cert.
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

BUILD_DIR="$ROOT/build/release"
PRODUCT_DIR="$BUILD_DIR/Build/Products/Release"
APP_PATH="$PRODUCT_DIR/Clipo.app"
CLI_PATH="$PRODUCT_DIR/clipocli"

echo "→ cleaning $BUILD_DIR"
rm -rf "$BUILD_DIR"

# Regenerate the Xcode project from project.yml so we're always building
# against the source of truth.
if command -v xcodegen >/dev/null 2>&1; then
    echo "→ regenerating Clipo.xcodeproj"
    xcodegen generate --quiet
fi

echo "→ building Clipo.app (Release)"
xcodebuild \
    -project Clipo.xcodeproj \
    -scheme Clipo \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build >/tmp/clipo-release-app.log 2>&1 || {
    tail -80 /tmp/clipo-release-app.log
    echo "✗ Clipo.app build failed (log: /tmp/clipo-release-app.log)"
    exit 1
}

echo "→ building clipocli (Release)"
xcodebuild \
    -project Clipo.xcodeproj \
    -scheme clipocli \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build >/tmp/clipo-release-cli.log 2>&1 || {
    tail -80 /tmp/clipo-release-cli.log
    echo "✗ clipocli build failed (log: /tmp/clipo-release-cli.log)"
    exit 1
}

[ -d "$APP_PATH" ] || { echo "✗ missing $APP_PATH"; exit 1; }
[ -x "$CLI_PATH" ] || { echo "✗ missing $CLI_PATH"; exit 1; }

# Embed the CLI so distribution is self-contained.
cp "$CLI_PATH" "$APP_PATH/Contents/Resources/clipocli"

echo
echo "✓ Clipo.app   $APP_PATH"
echo "✓ clipocli    $CLI_PATH"
echo "✓ embedded    $APP_PATH/Contents/Resources/clipocli"
