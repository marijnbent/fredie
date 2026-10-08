#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/release_common.sh"

release::build_release_app
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
DMG="$ROOT_DIR/build/Fredie-${VERSION}.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP_BUNDLE" "$STAGE/Fredie.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -ov -srcfolder "$STAGE" -format UDZO -volname Fredie "$DMG"
printf '[release] Packaged %s\n' "$DMG"
