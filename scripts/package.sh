#!/usr/bin/env bash
#
# One-shot Clipo DMG packaging: clean + build + DMG + open.
#
# Composes `build-release.sh` + `make-dmg.sh` into a single command and
# wipes the old build directory first so reruns don't silently ship a
# stale DMG when an intermediate step fails halfway through. Safe to
# run repeatedly; each run produces a fresh DMG at
# build/Clipo-<version>.dmg.
#
# Usage:
#   bash scripts/package.sh              # build + DMG + open the DMG
#   bash scripts/package.sh --no-open    # skip the auto-open (headless / CI)
#   ARCHS=arm64 bash scripts/package.sh  # Apple-Silicon-only binary
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

OPEN_AFTER=1
for arg in "$@"; do
    case "$arg" in
        --no-open) OPEN_AFTER=0 ;;
        -h|--help)
            # Echo back the header comment as help text.
            sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "unknown argument: $arg" >&2
            echo "try: bash scripts/package.sh --help" >&2
            exit 2
            ;;
    esac
done

VERSION=$(sed -n 's/.*MARKETING_VERSION: *"\([^"]*\)".*/\1/p' project.yml | head -1)
VERSION="${VERSION:-0.0.0}"
DMG="$ROOT/build/Clipo-$VERSION.dmg"

echo "→ wiping previous build artifacts"
# build-release.sh cleans build/release itself, and make-dmg.sh removes
# the target DMG. Wiping everything we own up front is still worth it
# so a half-failed prior run can't leave behind a DMG the user could
# mistake for the new build.
rm -rf "$ROOT/build/release" "$ROOT/build/dmg-staging"
rm -f  "$ROOT"/build/Clipo-*.dmg

echo
bash "$ROOT/scripts/build-release.sh"

echo
bash "$ROOT/scripts/make-dmg.sh"

echo
SIZE="$(du -h "$DMG" 2>/dev/null | cut -f1)"
echo "✓ packaged $DMG  (${SIZE:-?})"

if [ "$OPEN_AFTER" = "1" ]; then
    echo "→ opening DMG in Finder"
    open "$DMG"
fi
