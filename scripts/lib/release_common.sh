#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_BUNDLE="$ROOT_DIR/build/Release/Fredie.app"
INSTALLED_BUNDLE="/Applications/Fredie.app"
SIGNING_IDENTITY="$(/usr/libexec/PlistBuddy -c 'Print :SigningIdentity' "$ROOT_DIR/release/Release.plist")"

release::fail() {
    printf '[release] ERROR: %s\n' "$*" >&2
    exit 1
}

release::quit_running_app() {
    local path attempt
    for path in "$INSTALLED_BUNDLE" "$APP_BUNDLE"; do
        if pgrep -f "^$path/Contents/MacOS/Fredie( |$)" >/dev/null; then
            osascript -e "tell application \"$path\" to quit" || release::fail "Could not quit $path"
            for attempt in {1..20}; do
                pgrep -f "^$path/Contents/MacOS/Fredie( |$)" >/dev/null || break
                sleep 0.25
            done
            if pgrep -f "^$path/Contents/MacOS/Fredie( |$)" >/dev/null; then
                release::fail "Fredie is still open. Close its dialogs and quit before installing."
            fi
        fi
    done
}

release::verify_bundle() {
    local bundle="$1" item identifier
    [[ -d "$bundle" ]] || release::fail "Missing app: $bundle"
    plutil -lint "$bundle/Contents/Info.plist" >/dev/null
    identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")"
    [[ "$identifier" == "nl.bentjes.fredie" ]] || release::fail "Unexpected app identifier: $identifier"
    identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Helpers/Fredie Dictation.app/Contents/Info.plist")"
    [[ "$identifier" == "nl.bentjes.fredie.dictation" ]] || release::fail "Unexpected dictation identifier: $identifier"
    for item in "$bundle/Contents/Helpers/ClipboardTextHelper" "$bundle/Contents/Helpers/Fredie Dictation.app" "$bundle"; do
        [[ -e "$item" ]] || release::fail "Missing embedded product: $item"
        codesign --verify --deep --strict "$item"
        codesign -dvv "$item" 2>&1 | grep -Fx "Authority=$SIGNING_IDENTITY" >/dev/null || release::fail "Unexpected signing identity: $item"
    done
}

release::build_release_app() {
    security find-identity -v -p codesigning | grep -F "\"$SIGNING_IDENTITY\"" >/dev/null || release::fail "Signing identity is not installed: $SIGNING_IDENTITY"
    command -v xcodegen >/dev/null || release::fail "XcodeGen is required."
    cd "$ROOT_DIR"
    xcodegen generate
    xcodebuild -jobs 2 -project Fredie.xcodeproj -scheme Fredie -configuration Release -destination "platform=macOS,arch=$(uname -m)" \
        -derivedDataPath "$ROOT_DIR/build/DerivedData" \
        CONFIGURATION_BUILD_DIR="$ROOT_DIR/build/Release" \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" build
    release::verify_bundle "$APP_BUNDLE"
    printf '[release] Built %s\n' "$APP_BUNDLE"
}

release::install_bundle() {
    local stage
    release::verify_bundle "$APP_BUNDLE"
    stage="$(mktemp -d /Applications/.fredie-install.XXXXXX)"
    trap 'rm -rf "$stage"' RETURN
    ditto "$APP_BUNDLE" "$stage/Fredie.app"
    release::verify_bundle "$stage/Fredie.app"
    release::quit_running_app
    if [[ -e "$INSTALLED_BUNDLE" ]]; then
        mv "$INSTALLED_BUNDLE" "$stage/Previous.app"
    fi
    if ! mv "$stage/Fredie.app" "$INSTALLED_BUNDLE"; then
        if [[ -d "$stage/Previous.app" ]]; then
            mv "$stage/Previous.app" "$INSTALLED_BUNDLE"
        fi
        release::fail "Could not install Fredie."
    fi
    open "$INSTALLED_BUNDLE"
    printf '[release] Installed and opened %s\n' "$INSTALLED_BUNDLE"
}
