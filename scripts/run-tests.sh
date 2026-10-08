#!/bin/bash
# The test suite. There is no XCTest target: each harness compiles the shipped sources it guards,
# so a harness that stops compiling means a decision leaked out of a pure layer. See docs/testing.md.
#
# Never join a compile and its run with `&&`: `set -e` ignores a failure in a non-final AND-OR list
# member, which is how CI reported success over a harness that had not compiled since phase 10.

set -uo pipefail

# Absolute: the workers re-enter this script after the cd, where a relative $0 would not resolve.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.." || exit 1

BIN="${TMPDIR:-/tmp}/fredie-harness"
mkdir -p "$BIN"

# `--exec` is the worker half: xargs re-enters here once per queued harness.
if [ "${1:-}" = "--exec" ]; then
    shift
    name=$1 opt=$2
    shift 2
    : > "$BIN/$name.running"
    trap 'rm -f "$BIN/$name.running" "$BIN/$name.time"' EXIT
    fail() {
        printf '\033[31mFAIL\033[0m  %-25s %s\n' "$name" "$1"
        : > "$BIN/$name.failed"
        exit 0
    }
    TIMEFORMAT=%1R
    if ! compiled=$( { time swiftc -swift-version 6 "$opt" "$@" "Tests/$name.swift" -o "$BIN/$name" > "$BIN/$name.log" 2>&1; } 2>&1 ); then
        fail "did not compile"
    fi
    { time "$BIN/$name" > "$BIN/$name.log" 2>&1; } 2> "$BIN/$name.time" &
    pid=$!
    # macOS ships no `timeout`, so the worker polls; a wedged harness must fail, not stall the suite.
    ticks=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$ticks" -ge $((FREDIE_TEST_TIMEOUT * 5)) ]; then
            { pkill -KILL -P "$pid"; kill -KILL "$pid"; wait "$pid"; } 2>/dev/null
            printf '\n[run-tests] killed after %ss without finishing\n' "$FREDIE_TEST_TIMEOUT" >> "$BIN/$name.log"
            fail "timed out after ${FREDIE_TEST_TIMEOUT}s"
        fi
        ticks=$((ticks + 1))
        sleep 0.2
    done
    wait "$pid"
    status=$?
    took=$(< "$BIN/$name.time")
    if [ "$status" -gt 128 ]; then fail "crashed (signal $((status - 128))) after ${took}s"; fi
    if [ "$status" -ne 0 ]; then fail "assertion failed after ${took}s"; fi
    printf '\033[32mok\033[0m    %-25s %5ss  \033[2m(compile %ss)\033[0m\n' "$name" "$took" "$compiled"
    exit 0
fi

QUEUE="$BIN/queue"
: > "$QUEUE"
rm -f "$BIN"/*.failed "$BIN"/*.running

failed=()
ran=0
only="${1:-}"

# `--index` merges each harness's compile command into .compile instead of running anything.
# xcodebuild never compiles the harnesses, so without this nothing in Tests/ resolves in an editor.
# The source lists below are the only copy, which is why this lives here rather than in its own script.
emit_db=0
DB="${TMPDIR:-/tmp}/fredie-compile-db.json"
if [ "$only" = "--index" ]; then
    emit_db=1
    only=""
    printf '[' > "$DB"
fi

# run [slow] [-O] [index] <name> <source...> — queue the harness. `slow` dispatches it in the first
# wave; `index` claims editor flags for a harness that is compiled by hand rather than by the suite.
run() {
    local opt=-Onone pri=1 index_only=0
    while :; do
        case "$1" in
            slow)  pri=0; shift;;
            -O)    opt=-O; shift;;
            index) index_only=1; shift;;
            *)     break;;
        esac
    done
    local name=$1
    shift
    if [ -n "$only" ] && [ "$name" != "$only" ]; then return 0; fi
    if [ "$index_only" -eq 1 ] && [ "$emit_db" -eq 0 ]; then return 0; fi
    ran=$((ran + 1))

    # Absolute paths throughout: sourcekit-lsp resolves the command itself and does not apply
    # `directory` to relative arguments, so a relative path there silently yields no index.
    if [ "$emit_db" -eq 1 ]; then
        local sources=()
        for source in "$@" "Tests/$name.swift"; do sources+=("$PWD/$source"); done
        [ "$ran" -gt 1 ] && printf ',' >> "$DB"
        printf '{"directory":"%s","command":"swiftc -swift-version 6 -sdk %s' \
            "$PWD" "$(xcrun --show-sdk-path --sdk macosx)" >> "$DB"
        printf ' %s' "${sources[@]}" >> "$DB"
        # Claim every file under `Tests/`: the harness and any helper compiled beside it. A shipped
        # source stays unclaimed, because it would get this short command instead of the app's full
        # one and `.compile` is last-wins — but the app never compiles anything in `Tests/`.
        local claimed=""
        for source in "${sources[@]}"; do
            case "$source" in *"/Tests/"*) claimed="$claimed${claimed:+,}\"$source\"";; esac
        done
        printf '","files":[%s]}' "$claimed" >> "$DB"
        return 0
    fi

    # xargs splits the queue on whitespace, so no harness source path may contain a space.
    printf '%s %s %s %s\n' "$pri" "$name" "$opt" "$*" >> "$QUEUE"
}

L=Fredie/Features/Launcher/Model
run slow -O fuzz-test      $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/EntryNaming.swift $L/LauncherOrder.swift \
                           $L/LauncherRankingStore.swift $L/LauncherSuggestions.swift
run file-search-test       $L/SearchRelevance.swift \
                           Fredie/Features/FileSearch/Model/*.swift
run file-search-session-test Fredie/Platform/Signposts.swift \
                             $L/SearchRelevance.swift \
                             Fredie/Features/FileSearch/Model/*.swift \
                             Fredie/Features/FileSearch/Service/*.swift
run menu-search-test       $L/SearchRelevance.swift \
                           Fredie/Features/MenuSearch/Model/*.swift \
                           Fredie/Features/MenuSearch/Service/*.swift
run window-switch-test     $L/SearchRelevance.swift \
                           Fredie/Features/WindowSwitcher/Model/*.swift
run index file-search-performance Fredie/Platform/Signposts.swift \
                           $L/SearchRelevance.swift \
                           Fredie/Features/FileSearch/Model/*.swift \
                           Fredie/Features/FileSearch/Service/FileSearchService.swift
run ranking-test           $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/LauncherRankingStore.swift
run scopes-test            $L/SearchScopes.swift
run app-name-test          Fredie/Platform/AppDisplayName.swift \
                           Fredie/Platform/BundleLocalization.swift \
                           $L/SearchRelevance.swift
run favorites-test         $L/FavoriteSlots.swift
run launcher-file-test     $L/LauncherFileFormat.swift \
                           Fredie/Features/Settings/Model/SettingsFileJSON.swift
run launcher-settings-file-test \
                           $L/LauncherFileFormat.swift $L/CommandID.swift $L/CommandCatalog.swift \
                           Fredie/Features/Launcher/Service/LauncherSettingsFile.swift \
                           Fredie/Features/Launcher/Service/AliasStore.swift \
                           Fredie/Features/Launcher/Service/VisibilityStore.swift \
                           Fredie/Features/Settings/SettingsTab.swift \
                           Fredie/Features/Settings/Model/*.swift \
                           Fredie/Features/HotKeys/Service/HotKeySettingsFile.swift \
                           Fredie/Features/HotKeys/Service/KeyShortcut.swift \
                           Fredie/Features/HotKeys/Model/HotKeyAction.swift \
                           Fredie/Features/HotKeys/Model/HotKeyBinding.swift \
                           Fredie/Features/HotKeys/Model/HotKeySpelling.swift \
                           Fredie/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Fredie/Features/HotKeys/Model/ModifierKey.swift \
                           Fredie/Features/HotKeys/Model/HyperKey.swift \
                           Fredie/Platform/ASCIIKeyboardLayout.swift \
                           Fredie/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Fredie/Features/Quicklinks/Model/Quicklink.swift \
                           Fredie/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Fredie/Features/SystemActions/Model/SystemAction.swift \
                           Fredie/Features/WindowManagement/Model/WindowCommand.swift \
                           Fredie/Features/Snippets/Model/Snippet.swift
run apple-shortcut-test    Fredie/Features/AppleShortcuts/Model/*.swift
run calc-test              Fredie/Features/Calculator/Model/*.swift
run index calc-performance Fredie/Features/Calculator/Model/*.swift
run calendar-test          Fredie/Features/Calendar/Model/*.swift
run clipboard-test         Fredie/Features/Clipboard/Model/ClipboardStore.swift \
                           Fredie/Features/Clipboard/Model/ClipboardFilter.swift \
                           Fredie/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Fredie/Features/Clipboard/Model/ColorValue.swift \
                           Fredie/Features/Clipboard/Model/ColorFormat.swift \
                           Fredie/Features/Clipboard/Model/ColorSpaces.swift
# `Q` is the URL detector a drag payload builds its link with, rather than a second one.
Q=Fredie/Features/Quicklinks/Model/QuicklinkDestination.swift
run clipboard-search-test  Fredie/Features/Clipboard/Model/*.swift $Q
run paste-sequence-test    Fredie/Features/Clipboard/Model/*.swift $Q
run clipboard-text-test    Fredie/Features/Clipboard/Model/*.swift $Q \
                           Fredie/Features/Clipboard/Service/ClipboardTextExtractor.swift \
                           Fredie/Features/Clipboard/Service/ClipboardTextIndexer.swift \
                           Fredie/Features/Clipboard/Service/ClipboardTextWorker.swift \
                           Fredie/Platform/ProcessExit.swift
run pasteboard-test        Fredie/Platform/PasteboardFiles.swift \
                           Fredie/Features/Clipboard/Model/ClipboardStore.swift \
                           Fredie/Features/Clipboard/Model/ClipboardFilter.swift \
                           Fredie/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Fredie/Features/Clipboard/Model/ColorValue.swift \
                           Fredie/Features/Clipboard/Model/ColorFormat.swift \
                           Fredie/Features/Clipboard/Model/ColorSpaces.swift \
                           Fredie/Features/Clipboard/Service/ClipboardManager.swift \
                           Fredie/Features/Clipboard/Service/Paster.swift
run index clipboard-file-performance \
                           Fredie/Platform/PasteboardFiles.swift \
                           Fredie/Features/Clipboard/Model/ClipboardStore.swift \
                           Fredie/Features/Clipboard/Model/ClipboardFilter.swift \
                           Fredie/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Fredie/Features/Clipboard/Model/ColorValue.swift \
                           Fredie/Features/Clipboard/Model/ColorFormat.swift \
                           Fredie/Features/Clipboard/Model/ColorSpaces.swift \
                           Fredie/Features/Clipboard/Service/ClipboardManager.swift
run emoji-test             Fredie/Features/Emoji/Model/EmojiCatalog.swift \
                           Fredie/Features/Emoji/Model/EmojiGridGeometry.swift \
                           Fredie/Features/Emoji/Model/EmojiData.generated.swift
run emoji-search-test      Fredie/Features/Emoji/Model/EmojiCatalog.swift \
                           Fredie/Features/Emoji/Model/EmojiData.generated.swift \
                           Fredie/Features/Emoji/Service/EmojiIndex.swift \
                           Fredie/Features/Emoji/Service/FrequentEmojiStore.swift \
                           Fredie/Features/Emoji/Service/PinnedEmojiStore.swift \
                           Fredie/Features/Launcher/Model/SearchRelevance.swift \
                           Fredie/Platform/AppPaths.swift Fredie/Platform/Memo.swift
run index emoji-search-performance \
                           Fredie/Features/Emoji/Model/EmojiCatalog.swift \
                           Fredie/Features/Emoji/Model/EmojiData.generated.swift \
                           Fredie/Features/Emoji/Service/EmojiIndex.swift \
                           Fredie/Features/Emoji/Service/FrequentEmojiStore.swift \
                           Fredie/Features/Launcher/Model/SearchRelevance.swift \
                           Fredie/Platform/AppPaths.swift Fredie/Platform/Memo.swift
run palette-selection-test Fredie/Features/PaletteRowIndex.swift \
                           Fredie/Features/Emoji/Model/EmojiGridGeometry.swift
run appearance-test        Fredie/Platform/Appearance.swift \
                           Fredie/DesignSystem/Theme.swift \
                           Fredie/DesignSystem/InterfaceMetrics.swift \
                           Fredie/Features/Settings/AppAppearance.swift
run interface-size-test    Fredie/Platform/Appearance.swift \
                           Fredie/DesignSystem/Theme.swift \
                           Fredie/DesignSystem/InterfaceMetrics.swift \
                           Fredie/Features/Settings/InterfaceSize.swift \
                           Fredie/Features/Extensions/Model/ExtensionFormMetrics.swift
run palette-placement-test Fredie/Platform/Appearance.swift \
                           Fredie/DesignSystem/Theme.swift \
                           Fredie/DesignSystem/InterfaceMetrics.swift \
                           Fredie/Features/Settings/InterfaceSize.swift \
                           Fredie/Palette/PalettePlacement.swift
run scroll-reveal-test     Fredie/DesignSystem/Scrolling/SelectionReveal.swift
run redaction-test         Fredie/DesignSystem/RedactedPlaceholder.swift
run keyboard-focus-test    Fredie/DesignSystem/Interaction/KeyboardFocus.swift
run ai-instructions-test   Fredie/Features/AI/Model/AIInstructions.swift \
                           Fredie/Features/AI/Model/AIPreamble.swift
run hover-arming-test      Fredie/Palette/HoverArming.swift \
                           Fredie/Palette/PaletteState.swift \
                           Fredie/Palette/PaletteMode.swift \
                           Fredie/Features/Emoji/Model/EmojiCatalog.swift \
                           Fredie/Features/Clipboard/Model/ClipboardStore.swift \
                           Fredie/Features/Clipboard/Model/ClipboardFilter.swift \
                           Fredie/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Fredie/Features/FileSearch/Model/FileSearchFilter.swift \
                           Fredie/Features/Clipboard/Model/ColorValue.swift \
                           Fredie/Features/Clipboard/Model/ColorFormat.swift \
                           Fredie/Features/Clipboard/Model/ColorSpaces.swift \
                           Fredie/Features/Quicklinks/Model/Quicklink.swift \
                           Fredie/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Fredie/Features/CustomCommands/Model/CustomCommand.swift
run palette-escape-test    Fredie/Palette/PaletteMode.swift \
                           Fredie/Palette/PaletteEscapeAction.swift \
                           Fredie/Palette/CommandEscapeTap.swift \
                           Fredie/Features/Settings/EscapeKeyBehavior.swift \
                           Fredie/Features/Quicklinks/Model/Quicklink.swift \
                           Fredie/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Fredie/Features/CustomCommands/Model/CustomCommand.swift
run palette-navigation-test Fredie/Palette/PaletteState.swift \
                           Fredie/Palette/PaletteMode.swift \
                           Fredie/Palette/HoverArming.swift \
                           Fredie/Features/Emoji/Model/EmojiCatalog.swift \
                           Fredie/Features/Clipboard/Model/ClipboardStore.swift \
                           Fredie/Features/Clipboard/Model/ClipboardFilter.swift \
                           Fredie/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Fredie/Features/FileSearch/Model/FileSearchFilter.swift \
                           Fredie/Features/Clipboard/Model/ColorValue.swift \
                           Fredie/Features/Clipboard/Model/ColorFormat.swift \
                           Fredie/Features/Clipboard/Model/ColorSpaces.swift \
                           Fredie/Features/Quicklinks/Model/Quicklink.swift \
                           Fredie/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Fredie/Features/CustomCommands/Model/CustomCommand.swift
run palette-filter-test    Fredie/Palette/PaletteMode.swift \
                           Fredie/Palette/PaletteFilterAction.swift \
                           Fredie/Features/Quicklinks/Model/Quicklink.swift \
                           Fredie/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Fredie/Features/CustomCommands/Model/CustomCommand.swift
run action-menu-search-test Fredie/Palette/ActionMenuSearchQuery.swift \
                            Fredie/Features/Launcher/Model/SearchRelevance.swift
run palette-shortcut-test  Fredie/Palette/PaletteShortcut.swift
run ascii-layout-test      Fredie/Platform/ASCIIKeyboardLayout.swift
run palette-tab-test       Fredie/Palette/PaletteMode.swift \
                           Fredie/Palette/PaletteTabAction.swift \
                           Fredie/Features/Quicklinks/Model/Quicklink.swift \
                           Fredie/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Fredie/Features/CustomCommands/Model/CustomCommand.swift
run fallback-test          Fredie/Features/Launcher/Model/Fallback.swift \
                           Fredie/Features/Launcher/Model/CommandID.swift \
                           Fredie/Features/HotKeys/Model/HotKeyAction.swift \
                           Fredie/Features/QuickActions/Model/QuickAction.swift \
                           Fredie/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Fredie/Features/QuickActions/Model/CustomQuickAction.swift \
                           Fredie/Features/Quicklinks/Model/Quicklink.swift \
                           Fredie/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Fredie/Features/SystemActions/Model/SystemAction.swift \
                           Fredie/Features/WindowManagement/Model/WindowCommand.swift \
                           Fredie/Features/Snippets/Model/Snippet.swift
run dictionary-test        Fredie/Features/Dictionary/Model/DictionaryEntry.swift \
                           Fredie/Features/Dictionary/Model/DictionaryMarkup.swift
run dictation-test         Fredie/Features/Dictation/Model/DictationModel.swift Fredie/Features/Dictation/Model/DictationIdleRelease.swift Fredie/Features/Dictation/Model/DictationTextFormatter.swift
run dictation-field-test   Fredie/Features/Dictation/Model/DictationModel.swift \
                           Fredie/Features/Dictation/Model/DictationMode.swift \
                           Fredie/Features/Dictation/Model/DictationDestination.swift \
                           Fredie/Features/Dictation/Model/DictationTextFormatter.swift \
                           Fredie/Features/Dictation/Service/DictationCoordinator.swift \
                           Fredie/Features/Dictation/Service/DictationInsertionContext.swift \
                           Fredie/Features/AI/UI/ChatComposerTextView.swift \
                           Fredie/Features/TextInjection/Service/*.swift \
                           Fredie/Features/Snippets/Model/*.swift \
                           Fredie/Platform/AccessibilityText.swift \
                           Fredie/Platform/PasteboardFiles.swift \
                           Fredie/Platform/Appearance.swift Fredie/DesignSystem/Theme.swift
run dictation-volume-test  Fredie/Features/Dictation/Model/DictationVolumeSnapshot.swift \
                           Fredie/Features/Dictation/Service/DictationAudioDucker.swift \
                           Fredie/Platform/AppPaths.swift
run index -O dictation-performance Fredie/Platform/ProcessExit.swift \
                           Fredie/Features/Dictation/Model/DictationModel.swift \
                           Fredie/Features/Dictation/Service/DictationWire.swift
run dictation-inference-test Fredie/Features/Dictation/Model/DictationAudioChunks.swift \
    Fredie/Features/Dictation/Service/DictationSpectrum.swift \
    Fredie/Features/Dictation/Helper/DictationTensor.swift Fredie/Features/Dictation/Helper/DictationTokenizer.swift \
    Fredie/Features/Dictation/Helper/DictationMel.swift
run dictation-worker-test  Fredie/Features/Dictation/Model/DictationModel.swift \
                           Fredie/Features/Dictation/Model/DictationIdleRelease.swift \
                           Fredie/Features/Dictation/Service/DictationWire.swift \
                           Fredie/Features/Dictation/Service/DictationWorker.swift \
                           Fredie/Features/Dictation/Service/DictationModelStore.swift \
                           Fredie/Features/Dictation/Service/DictationModelDownloader.swift \
                           Fredie/Platform/ProcessExit.swift Fredie/Platform/AppPaths.swift
run hotkey-test            Fredie/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Fredie/Features/HotKeys/Model/ModifierKey.swift \
                           Fredie/Features/HotKeys/Model/ModifierKeyDetector.swift \
                           Fredie/Features/HotKeys/Model/DoubleTapDetector.swift \
                           Fredie/Features/HotKeys/Model/HotKeyBinding.swift \
                           Fredie/Features/HotKeys/Model/HotKeySpelling.swift \
                           Fredie/Features/HotKeys/Model/HyperKey.swift \
                           Fredie/Platform/ASCIIKeyboardLayout.swift \
                           Fredie/Features/HotKeys/Service/KeyShortcut.swift \
                           Fredie/Features/HotKeys/Model/HotKeyAction.swift \
                           Fredie/Features/QuickActions/Model/QuickAction.swift \
                           Fredie/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Fredie/Features/QuickActions/Model/CustomQuickAction.swift \
                           Fredie/Features/Launcher/Model/CommandID.swift \
                           Fredie/Features/Quicklinks/Model/Quicklink.swift \
                           Fredie/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Fredie/Features/SystemActions/Model/SystemAction.swift \
                           Fredie/Features/WindowManagement/Model/WindowCommand.swift \
                           Fredie/Features/Snippets/Model/Snippet.swift
run callout-test          Fredie/Platform/Appearance.swift \
                           Fredie/DesignSystem/Theme.swift \
                           Fredie/DesignSystem/InterfaceMetrics.swift \
                           Fredie/Features/HotKeys/UI/CalloutPlacement.swift
run icon-cache-test        Fredie/Platform/Appearance.swift \
                           Fredie/Platform/Images/IconCache.swift
run entry-icon-test        Fredie/Platform/Appearance.swift \
                           Fredie/Platform/Images/IconCache.swift \
                           Fredie/Platform/Images/FileIconStamp.swift
run ext-icon-test          Fredie/Platform/Appearance.swift \
                           Fredie/Platform/AppDisplayName.swift \
                           Fredie/Platform/Images/IconCache.swift \
                           Fredie/Platform/Compression/Zlib.swift \
                           Fredie/DesignSystem/Theme.swift \
                           Fredie/DesignSystem/InterfaceMetrics.swift \
                           Fredie/Features/Extensions/Model/ExtensionBootConfig.swift \
                           Fredie/Features/Extensions/Model/ExtensionLaunchType.swift \
                           Fredie/Features/Extensions/Model/ExtensionManifest.swift \
                           Fredie/Features/Extensions/Model/ExtensionRefreshPolicy.swift \
                           Fredie/Features/Extensions/Model/ExtensionRefreshState.swift \
                           Fredie/Features/Extensions/Model/RenderNode.swift \
                           Fredie/Features/Extensions/Service/ExtensionCatalog.swift \
                           Fredie/Features/Extensions/Service/ExtensionFetcher.swift \
                           Fredie/Platform/ProcessExit.swift \
                           Fredie/Features/Extensions/Service/ExtensionNodeShims.swift \
                           Fredie/Features/Extensions/Service/ExtensionOAuthKeychain.swift \
                           Fredie/Features/Extensions/Service/ExtensionOAuthSession.swift \
                           Fredie/Features/Extensions/Service/ExtensionRuntime.swift \
                           Fredie/Features/Extensions/Service/ExtensionIconCache.swift \
                           Fredie/Features/Extensions/UI/ExtensionAnimatedImage.swift \
                           Fredie/Features/Extensions/UI/ExtensionImage.swift \
                           Fredie/Features/Clipboard/Model/ColorValue.swift \
                           Fredie/Features/Clipboard/Model/ColorSpaces.swift
run system-action-test     Fredie/Features/SystemActions/Model/SystemAction.swift
run microphone-mute-test   Fredie/Features/SystemActions/Service/SystemActionFailure.swift \
                           Fredie/Features/SystemActions/Service/SystemActionRunner+Microphone.swift
run volume-test            Fredie/Features/SystemActions/Model/VolumeLevel.swift
run window-command-test    Fredie/Features/WindowManagement/Model/WindowCommand.swift \
                           Fredie/Features/WindowManagement/Model/WindowCycle.swift \
                           Fredie/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Fredie/Features/WindowManagement/Model/WindowActionMemory.swift
run window-preset-test     Fredie/Features/WindowManagement/Model/WindowCommand.swift \
                           Fredie/Features/WindowManagement/Model/WindowShortcutPreset.swift \
                           Fredie/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Fredie/Features/HotKeys/Model/ModifierKey.swift \
                           Fredie/Features/HotKeys/Model/HotKeyBinding.swift \
                           Fredie/Features/HotKeys/Model/HyperKey.swift \
                           Fredie/Platform/ASCIIKeyboardLayout.swift \
                           Fredie/Features/HotKeys/Service/KeyShortcut.swift
run space-gesture-test     Fredie/Features/WindowManagement/Model/WindowCommand.swift \
                           Fredie/Features/WindowManagement/Model/SpaceGesture.swift
run window-layout-test     Fredie/Features/WindowManagement/Model/WindowCommand.swift \
                           Fredie/Features/WindowManagement/Model/WindowCycle.swift \
                           Fredie/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Fredie/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           Fredie/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           Fredie/Features/WindowManagement/Model/WindowLayout.swift \
                           Fredie/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           Fredie/Features/WindowManagement/Model/WindowLayoutPlan.swift \
                           Fredie/Features/WindowManagement/Model/WindowLayoutStore.swift \
                           Fredie/Features/WindowManagement/Model/CustomWindowSize.swift \
                           Fredie/Features/WindowManagement/Model/CustomWindowSizeStore.swift
run window-room-test       Fredie/Features/WindowManagement/Model/WindowCommand.swift \
                           Fredie/Features/WindowManagement/Model/WindowCycle.swift \
                           Fredie/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Fredie/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           Fredie/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           Fredie/Features/WindowManagement/Model/WindowLayout.swift \
                           Fredie/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           Fredie/Features/WindowManagement/Model/WindowLayoutPlan.swift \
                           Fredie/Features/WindowManagement/Model/RoomLayoutKind.swift \
                           Fredie/Features/WindowManagement/Model/RoomLayoutEngine.swift \
                           Fredie/Features/WindowManagement/Model/RoomGrid.swift \
                           Fredie/Features/WindowManagement/Model/RoomWindow.swift \
                           Fredie/Features/WindowManagement/Model/Room.swift \
                           Fredie/Features/WindowManagement/Model/RoomWindowMatcher.swift \
                           Fredie/Features/WindowManagement/Model/RoomParking.swift \
                           Fredie/Features/WindowManagement/Model/RoomPlan.swift \
                           Fredie/Features/WindowManagement/Model/RoomArrangement.swift \
                           Fredie/Features/WindowManagement/Model/RoomStore.swift \
                           Fredie/Features/WindowManagement/Model/RoomMinimumSizeStore.swift \
                           Fredie/Features/WindowManagement/Model/RoomParkingLedger.swift
run window-file-test       Fredie/Features/WindowManagement/Model/WindowCommand.swift \
                           Fredie/Features/WindowManagement/Model/WindowCycle.swift \
                           Fredie/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Fredie/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           Fredie/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           Fredie/Features/WindowManagement/Model/WindowLayout.swift \
                           Fredie/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           Fredie/Features/WindowManagement/Model/CustomWindowSize.swift \
                           Fredie/Features/WindowManagement/Model/Room.swift \
                           Fredie/Features/WindowManagement/Model/RoomWindow.swift \
                           Fredie/Features/WindowManagement/Model/RoomLayoutKind.swift \
                           Fredie/Features/WindowManagement/Model/RoomGrid.swift \
                           Fredie/Features/WindowManagement/Model/RoomLayoutEngine.swift \
                           Fredie/Features/WindowManagement/Model/WindowManagementFileFormat.swift \
                           Fredie/Features/Settings/Model/SettingsFileJSON.swift \
                           Fredie/Features/Settings/Model/SettingsFileIdentity.swift
run custom-command-test    Fredie/Platform/PseudoTerminal.swift \
                           Fredie/Platform/ProcessExit.swift \
                           Fredie/Features/CustomCommands/Model/CustomCommand.swift \
                           Fredie/Features/CustomCommands/Model/RaycastScriptImport.swift \
                           Fredie/Features/CustomCommands/Service/ShellCommandRunner.swift
run uninstall-test         Fredie/Features/Uninstall/Model/UninstallTarget.swift \
                           Fredie/Features/Uninstall/Model/UninstallSearchRoot.swift \
                           Fredie/Features/Uninstall/Model/UninstallRules.swift \
                           Fredie/Features/Uninstall/Model/UninstallProtection.swift \
                           Fredie/Features/Uninstall/Model/UninstallPlan.swift
run quicklink-test         Fredie/Features/Quicklinks/Model/Quicklink.swift \
                           Fredie/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Fredie/Features/Quicklinks/Model/QuicklinkStore.swift \
                           Fredie/Features/Quicklinks/Model/QuicklinkArchive.swift \
                           Fredie/Features/Quicklinks/Model/RaycastQuicklinkImport.swift
run quicklink-coordinator-test Fredie/Features/Quicklinks/Model/Quicklink.swift \
                           Fredie/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Fredie/Features/Quicklinks/Model/QuicklinkStore.swift \
                           Fredie/Features/Quicklinks/Model/QuicklinkArchive.swift \
                           Fredie/Features/Quicklinks/UI/QuicklinkCoordinator.swift \
                           Fredie/Features/Quicklinks/UI/QuicklinkArgumentsAccessory.swift \
                           Fredie/Features/Snippets/Model/Snippet.swift \
                           Fredie/Features/Snippets/Model/SnippetTemplateEngine.swift
run slow snippets-test     Fredie/Platform/NotificationToken.swift \
                           Fredie/Platform/HealthTicker.swift \
                           Fredie/Platform/AccessibilityText.swift \
                           Fredie/Features/Snippets/Model/*.swift \
                           Fredie/Features/Snippets/Service/*.swift \
                           Fredie/Features/TextInjection/Service/*.swift
run notes-test             Fredie/Platform/Signposts.swift \
                           $L/SearchRelevance.swift \
                           Fredie/Features/Notes/Model/*.swift \
                           Fredie/Features/Notes/Service/*.swift
run notes-editor-test      Fredie/Platform/Signposts.swift \
                           Fredie/Platform/Appearance.swift \
                           Fredie/DesignSystem/Theme.swift \
                           Fredie/DesignSystem/InterfaceMetrics.swift \
                           Fredie/Platform/NotificationToken.swift \
                           Fredie/Features/TextInjection/Service/InjectableTextView.swift \
                           Fredie/Features/Notes/Model/NoteDocument.swift \
                           Fredie/Features/Notes/Model/NoteMarkdown.swift \
                           Fredie/Features/Notes/Model/NoteMarkdownParser.swift \
                           Fredie/Features/Notes/Model/NoteInlineScanner.swift \
                           Fredie/Features/Notes/Model/NoteEditPlan.swift \
                           Fredie/Features/Notes/Model/NoteEditAction.swift \
                           Fredie/Features/Notes/Model/NoteFormatting.swift \
                           Fredie/Features/Notes/Model/NoteMarkdownEditing.swift \
                           Fredie/Features/Notes/Model/NoteRevealPolicy.swift \
                           Fredie/Features/Notes/UI/NoteMarkdownTypography.swift \
                           Fredie/Features/Notes/UI/NoteBlockDecoration.swift \
                           Fredie/Features/Notes/UI/NoteMarkdownStyler.swift \
                           Fredie/Features/Notes/UI/NoteMarkdownRenderer.swift \
                           Fredie/Features/Notes/UI/NoteCheckboxGeometry.swift \
                           Fredie/Features/Notes/UI/NoteBlockLayoutFragment.swift \
                           Fredie/Features/Notes/UI/NoteLayoutFragmentProvider.swift \
                           Fredie/Features/Notes/UI/NoteTextViewEditing.swift \
                           Fredie/Features/Notes/UI/NoteTextView.swift \
                           Fredie/Features/Notes/UI/NoteEditorView.swift
run -O index notes-editor-performance \
                           Fredie/Platform/Signposts.swift \
                           Fredie/Platform/Appearance.swift \
                           Fredie/DesignSystem/Theme.swift \
                           Fredie/DesignSystem/InterfaceMetrics.swift \
                           Fredie/Platform/NotificationToken.swift \
                           Fredie/Features/TextInjection/Service/InjectableTextView.swift \
                           Fredie/Features/Notes/Model/NoteDocument.swift \
                           Fredie/Features/Notes/Model/NoteMarkdown.swift \
                           Fredie/Features/Notes/Model/NoteMarkdownParser.swift \
                           Fredie/Features/Notes/Model/NoteInlineScanner.swift \
                           Fredie/Features/Notes/Model/NoteEditPlan.swift \
                           Fredie/Features/Notes/Model/NoteEditAction.swift \
                           Fredie/Features/Notes/Model/NoteFormatting.swift \
                           Fredie/Features/Notes/Model/NoteMarkdownEditing.swift \
                           Fredie/Features/Notes/Model/NoteRevealPolicy.swift \
                           Fredie/Features/Notes/UI/NoteMarkdownTypography.swift \
                           Fredie/Features/Notes/UI/NoteBlockDecoration.swift \
                           Fredie/Features/Notes/UI/NoteMarkdownStyler.swift \
                           Fredie/Features/Notes/UI/NoteMarkdownRenderer.swift \
                           Fredie/Features/Notes/UI/NoteCheckboxGeometry.swift \
                           Fredie/Features/Notes/UI/NoteBlockLayoutFragment.swift \
                           Fredie/Features/Notes/UI/NoteLayoutFragmentProvider.swift \
                           Fredie/Features/Notes/UI/NoteTextViewEditing.swift \
                           Fredie/Features/Notes/UI/NoteTextView.swift \
                           Fredie/Features/Notes/UI/NoteEditorView.swift
run slow -O raycast-test   Fredie/Features/Backup/Model/RaycastImportError.swift \
                           Fredie/Features/Backup/Service/RaycastDecoder.swift \
                           Fredie/Features/Backup/Service/Scrypt.swift \
                           Fredie/Platform/Compression/Zlib.swift \
                           Fredie/Features/Clipboard/Model/RaycastClipboardImport.swift \
                           Fredie/Features/Clipboard/Model/ClipboardStore.swift \
                           Fredie/Features/Clipboard/Model/ClipboardFilter.swift \
                           Fredie/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Fredie/Features/Clipboard/Model/ColorValue.swift \
                           Fredie/Features/Clipboard/Model/ColorFormat.swift \
                           Fredie/Features/Clipboard/Model/ColorSpaces.swift
run settings-backup-test   Fredie/Features/Settings/AppSettingsKey.swift \
                           Fredie/Features/Backup/Model/SettingsBackupCoverage.swift
run settings-file-test     Fredie/Features/Settings/Model/*.swift \
                           Fredie/Features/Settings/Service/SettingsFileMonitor.swift \
                           Fredie/Features/Settings/Service/SettingsFileRepository.swift \
                           Fredie/Platform/AppPaths.swift
run backup-archive-test    Fredie/Platform/AppPaths.swift \
                           Fredie/Features/Backup/Model/BackupArchive.swift \
                           Fredie/Features/Backup/Model/BackupBundle.swift \
                           Fredie/Features/Backup/Model/BackupCategory.swift \
                           Fredie/Features/Backup/Model/BackupClipboardItem.swift \
                           Fredie/Features/Backup/Model/BackupManifest.swift \
                           Fredie/Features/Backup/Service/BackupStaging.swift
E=Fredie/Features/Extensions
run symbols-test           $E/Service/SymbolCatalog.swift
run ext-cleanup-test       $E/Service/ExtensionCleanup.swift \
                           $E/Service/ExtensionCatalog.swift \
                           Fredie/Platform/AppDisplayName.swift \
                           $E/Model/ExtensionManifest.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift
run ext-refresh-test       $E/Model/ExtensionManifest.swift \
                           Fredie/Platform/AppDisplayName.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift
run ext-metadata-test      $E/Model/ExtensionCommandMetadata.swift \
                           $E/Model/ExtensionMenuBarSnapshot.swift \
                           $E/Service/ExtensionCommandMetadataStore.swift
run ext-version-test       $E/Model/ExtensionListing.swift \
                           $E/Service/ExtensionVersionStore.swift
run ext-store-test         $E/Model/ExtensionGitHubSource.swift \
                           $E/Model/ExtensionListing.swift \
                           $E/Model/ExtensionPackageManager.swift \
                           $E/Model/ExtensionStoreResponse.swift
run ext-form-test          $E/Model/ExtensionFormMetrics.swift \
                           $E/Model/ExtensionFormField.swift \
                           $E/UI/ExtensionFormKey.swift \
                           $E/Model/ExtensionDateExpression.swift \
                           $E/UI/ExtensionListKey.swift \
                           Tests/ext-list-key-test.swift
run ext-image-size-test   $E/Model/ExtensionImageSize.swift
run ext-accessory-test     $E/Model/RenderNode.swift \
                           $E/Model/ExtensionPickerItem.swift \
                           $E/Model/ExtensionSearchAccessory.swift \
                           $E/Service/ExtensionStorage.swift
run slow ext-test          -parse-as-library \
                           Tests/ext-menu-bar-test.swift \
                           Tests/ext-fetch-test.swift \
                           $E/Model/ExtensionLaunchError.swift \
                           $E/Model/ExtensionMenuBarSnapshot.swift \
                           $E/Service/ExtensionStorage.swift \
                           $E/Service/ExtensionMenuBarManager.swift \
                           $E/Model/ExtensionCommandMetadata.swift \
                           $E/Service/ExtensionCommandMetadataStore.swift \
                           $E/UI/ExtensionMenuBarController.swift \
                           $E/UI/ExtensionMenuBarImage.swift \
                           Fredie/Platform/Appearance.swift \
                           Fredie/Platform/AppDisplayName.swift \
                           Fredie/Platform/Images/IconCache.swift \
                           Fredie/DesignSystem/Theme.swift \
                           Fredie/DesignSystem/InterfaceMetrics.swift \
                           $E/Model/ExtensionBootConfig.swift \
                           $E/Model/ExtensionDeepLink.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionFormField.swift \
                           $E/Model/ExtensionGridLayout.swift \
                           $E/Model/ExtensionManifest.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift \
                           $E/Model/RenderNode.swift \
                           $E/Model/ExtensionPickerItem.swift \
                           $E/Model/ExtensionSearchAccessory.swift \
                           $E/Service/ExtensionCatalog.swift \
                           $E/Service/ExtensionFetcher.swift \
                           Fredie/Platform/ProcessExit.swift \
                           $E/Service/ExtensionIconCache.swift \
                           $E/Service/ExtensionNodeShims.swift \
                           $E/Service/ExtensionOAuthKeychain.swift \
                           $E/Service/ExtensionOAuthSession.swift \
                           $E/Service/ExtensionRuntime.swift \
                           $E/Service/ExtensionNameResolver.swift \
                           $E/Service/ExtensionWebSocketBridge.swift \
                           $E/UI/ExtensionAnimatedImage.swift \
                           $E/UI/ExtensionImage.swift \
                           $E/UI/ExtensionScreen.swift \
                           $L/SearchRelevance.swift \
                           Fredie/Platform/Compression/Zlib.swift \
                           Fredie/Features/Clipboard/Model/ColorValue.swift \
                           Fredie/Features/Clipboard/Model/ColorSpaces.swift
run settings-history-test  Fredie/Features/Settings/SettingsTab.swift \
                           Fredie/Features/Settings/SettingsHistory.swift \
                           Fredie/Features/Settings/SettingsAnchor.swift \
                           Fredie/Features/Settings/SettingsNavigationState.swift \
                           Fredie/Features/Settings/SettingsSearchCatalog.swift \
                           $L/SearchRelevance.swift
run updates-test           Fredie/Features/Updates/Model/*.swift \
                           Fredie/Features/Updates/Service/BundleSignature.swift
run update-check-test      Fredie/Features/Updates/Model/*.swift \
                           Fredie/Features/Updates/Service/UpdateCheckStore.swift \
                           Fredie/Platform/AppPaths.swift
run support-test           Fredie/Features/Support/Model/*.swift
run ai-provider-test       Fredie/Features/Settings/AppSettingsKey.swift \
                           Fredie/Features/AI/Model/*.swift \
                           Fredie/Features/AI/Settings/AISettingsStore.swift
run ai-chat-test           Fredie/Features/AI/Model/AIRequest.swift \
                           Fredie/Features/AI/Model/AIConnection.swift \
                           Fredie/Features/AI/Model/AppleIntelligence.swift \
                           Fredie/Features/AI/Model/AIAttachmentPolicy.swift \
                           Fredie/Features/AI/Model/AIRetention.swift \
                           Fredie/Features/AI/Model/AITool.swift \
                           Fredie/Features/AI/Model/JSONValue.swift \
                           Fredie/Features/AI/Model/ChatMessage.swift \
                           Fredie/Features/AI/Model/ChatSession.swift \
                           Fredie/Features/AI/Model/ChatChoices.swift \
                           Fredie/Features/AI/Model/ChatReferences.swift \
                           Fredie/Features/AI/Model/ChatTitle.swift \
                           Fredie/Features/AI/Model/ChatFind.swift \
                           Fredie/Features/AI/Model/ChatCitations.swift \
                           Fredie/Features/AI/Model/ChatToolScope.swift \
                           Fredie/Features/AI/Model/MarkdownBlock.swift \
                           Fredie/Features/AI/Model/MarkdownMath.swift \
                           Fredie/Features/AI/Model/MathFormula.swift \
                           Fredie/Features/AI/Model/MathNode.swift \
                           Fredie/Features/AI/Model/MathSymbolCatalog.swift \
                           Fredie/Features/AI/Service/AIProvider.swift \
                           Fredie/Features/AI/Service/ChatHistoryStore.swift \
                           Fredie/Features/AI/Service/AIToolLoopProvider.swift \
                           Fredie/Features/AI/UI/AIChatState.swift \
                           Fredie/Features/AI/UI/AIChatSurfacesState.swift \
                           Fredie/Features/AI/UI/ChatFindState.swift
run chat-markdown-test     Fredie/Platform/Appearance.swift \
                           Fredie/DesignSystem/Theme.swift \
                           Fredie/DesignSystem/InterfaceMetrics.swift \
                           Fredie/Features/Settings/InterfaceSize.swift \
                           Fredie/Features/AI/Model/AIRequest.swift \
                           Fredie/Features/AI/Model/AITool.swift \
                           Fredie/Features/AI/Model/JSONValue.swift \
                           Fredie/Features/AI/Model/ChatMessage.swift \
                           Fredie/Features/AI/Model/ChatChoices.swift \
                           Fredie/Features/AI/Model/ChatReferences.swift \
                           Fredie/Features/AI/Model/ChatCitations.swift \
                           Fredie/Features/AI/Model/ChatFind.swift \
                           Fredie/Features/AI/Model/MarkdownBlock.swift \
                           Fredie/Features/AI/Model/MarkdownMath.swift \
                           Fredie/Features/AI/Model/MathFormula.swift \
                           Fredie/Features/AI/Model/MathNode.swift \
                           Fredie/Features/AI/Model/MathSymbolCatalog.swift \
                           Fredie/Features/AI/UI/ChatTextHighlight.swift \
                           Fredie/Features/AI/UI/ChatMarkdownRenderer.swift \
                           Fredie/Features/AI/UI/MathAttachmentCell.swift \
                           Fredie/Features/AI/UI/MathBox.swift \
                           Fredie/Features/AI/UI/MathFont.swift \
                           Fredie/Features/AI/UI/MathLayoutEngine.swift
run mcp-test               Fredie/Features/Settings/AppSettingsKey.swift \
                           Fredie/Features/AI/Model/AIConnection.swift \
                           Fredie/Features/AI/Model/AppleIntelligence.swift \
                           Fredie/Features/AI/Model/AITool.swift \
                           Fredie/Features/AI/Model/AIToolServer.swift \
                           Fredie/Features/AI/Model/JSONValue.swift \
                           Fredie/Features/MCP/Model/*.swift \
                           Fredie/Features/MCP/Settings/MCPSettingsStore.swift
run -O text-diff-test      Fredie/Features/QuickActions/Model/TextDiffEngine.swift
run index text-diff-performance Fredie/Features/QuickActions/Model/TextDiffEngine.swift
run quick-action-test      Fredie/Features/Settings/AppSettingsKey.swift \
                           Fredie/Features/AI/Model/AIConnection.swift \
                           Fredie/Features/AI/Model/AppleIntelligence.swift \
                           Fredie/Features/AI/Model/ChatGPTSubscription.swift \
                           Fredie/Features/AI/Model/InstalledAI.swift \
                           Fredie/Features/QuickActions/Model/*.swift \
                           Fredie/Features/QuickActions/Settings/QuickActionSettingsStore.swift
run apple-intelligence-test Fredie/Features/Settings/AppSettingsKey.swift \
                           Fredie/Features/AI/Model/*.swift \
                           Fredie/Features/AI/Service/AIProvider.swift \
                           Fredie/Features/AI/Service/AppleIntelligenceProvider.swift
run mcp-oauth-test         Fredie/Platform/ExecutableLocator.swift \
                           Fredie/Platform/ProcessExit.swift \
                           Fredie/Platform/KeychainSecretStore.swift \
                           Fredie/Features/Settings/AppSettingsKey.swift \
                           Fredie/Features/AI/Model/AIConnection.swift \
                           Fredie/Features/AI/Model/AppleIntelligence.swift \
                           Fredie/Features/AI/Model/AITool.swift \
                           Fredie/Features/AI/Model/AIToolServer.swift \
                           Fredie/Features/AI/Model/AIStreamDecoder.swift \
                           Fredie/Features/AI/Model/AIThinkTagDecoder.swift \
                           Fredie/Features/AI/Model/AIRequest.swift \
                           Fredie/Features/AI/Model/JSONValue.swift \
                           Fredie/Features/MCP/Model/*.swift \
                           Fredie/Features/MCP/Service/*.swift
run slow mcp-stdio-test    Fredie/Platform/ExecutableLocator.swift \
                           Fredie/Platform/ProcessExit.swift \
                           Fredie/Platform/KeychainSecretStore.swift \
                           Fredie/Features/Settings/AppSettingsKey.swift \
                           Fredie/Features/AI/Model/AIConnection.swift \
                           Fredie/Features/AI/Model/AppleIntelligence.swift \
                           Fredie/Features/AI/Model/AITool.swift \
                           Fredie/Features/AI/Model/AIToolServer.swift \
                           Fredie/Features/AI/Model/AIStreamDecoder.swift \
                           Fredie/Features/AI/Model/AIThinkTagDecoder.swift \
                           Fredie/Features/AI/Model/AIRequest.swift \
                           Fredie/Features/AI/Model/JSONValue.swift \
                           Fredie/Features/MCP/Model/*.swift \
                           Fredie/Features/MCP/Service/*.swift
run slow codex-turn-test   Fredie/Platform/AppPaths.swift \
                           Fredie/Features/AI/Model/*.swift \
                           Fredie/Features/AI/Service/AIProvider.swift \
                           Fredie/Features/AI/Service/ChatGPTSubscriptionManager.swift \
                           Fredie/Features/AI/Service/CodexAppServerClient.swift \
                           Fredie/Features/AI/Service/InstalledAIProbe.swift \
                           Fredie/Platform/ExecutableLocator.swift \
                           Fredie/Platform/ProcessExit.swift \
                           Fredie/Features/AI/Service/CodexTurnRunner.swift
run installed-ai-test     Fredie/Features/AI/Model/*.swift \
                          Fredie/Features/AI/Service/AIProvider.swift \
                          Fredie/Platform/AppPaths.swift \
                          Fredie/Platform/ExecutableLocator.swift \
                          Fredie/Platform/ProcessExit.swift \
                          Fredie/Features/AI/Service/InstalledCLIProvider.swift \
                          Fredie/Features/AI/Service/InstalledAIProbe.swift \
                          Fredie/Features/AI/Service/InstalledAIManager.swift

if [ "$emit_db" -eq 1 ]; then
    printf ']\n' >> "$DB"
    [ -f .compile ] || echo '[]' > .compile
    node -e '
const fs = require("node:fs");
const [comp, db] = process.argv.slice(1);
const existing = JSON.parse(fs.readFileSync(comp, "utf8"));
const harnesses = JSON.parse(fs.readFileSync(db, "utf8"));
const kept = existing.filter((e) => !(e.files || []).some((f) => f.includes("/Tests/")));
fs.writeFileSync(comp, JSON.stringify([...kept, ...harnesses], null, 1));
console.log(harnesses.length + " harness entries indexed into .compile");
' .compile "$DB"
    exit 0
fi

if [ "$ran" -eq 0 ]; then
    echo "No harness named '$only'." >&2
    exit 2
fi

# `sort -s` is stable, so the slow harnesses lead and everything else keeps its declaration order.
JOBS="${FREDIE_TEST_JOBS:-4}"
export FREDIE_TEST_TIMEOUT="${FREDIE_TEST_TIMEOUT:-300}"
started=$SECONDS

# Numbers each result, and names what is still running whenever the output goes quiet.
report() {
    local finished=0 line asked running file
    while :; do
        asked=$SECONDS
        if IFS= read -r -t 15 line; then
            case "$line" in "dispatch "*) return "${line#dispatch }";; esac
            finished=$((finished + 1))
            printf '[%*d/%d] %s\n' "${#ran}" "$finished" "$ran" "$line"
            continue
        fi
        # Bash 3.2 returns the same status for a timeout and EOF; only EOF comes back at once.
        if [ $((SECONDS - asked)) -lt 10 ]; then return 1; fi
        running=""
        for file in "$BIN"/*.running; do
            [ -e "$file" ] && running="$running $(basename "$file" .running)"
        done
        printf '        \033[2mstill running after %ds:%s\033[0m\n' $((SECONDS - started)) "$running"
    done
}

# Without this the suite reports "all passed" whenever dispatch itself dies and no harness ran.
if ! { sort -s -k1,1n "$QUEUE" | cut -d' ' -f2- | xargs -P "$JOBS" -L1 "$SELF" --exec; echo "dispatch $?"; } | report; then
    echo "harness dispatch failed; no result below can be trusted" >&2
    exit 1
fi
elapsed=$((SECONDS - started))

# A compiler diagnostic is far longer than PIPE_BUF, so the workers log it and it is replayed here.
while read -r _ name _; do
    if [ -f "$BIN/$name.failed" ]; then failed+=("$name"); fi
done < "$QUEUE"

if [ ${#failed[@]} -gt 0 ]; then
    for name in "${failed[@]}"; do
        printf '\n\033[31m--- %s ---\033[0m\n' "$name"
        cat "$BIN/$name.log"
    done
    printf '\n\033[31mFAILED\033[0m  %d of %d harness(es) failed in %ds: %s\n' \
        "${#failed[@]}" "$ran" "$elapsed" "${failed[*]}" >&2
    exit 1
fi
printf '\n\033[32mPASSED\033[0m  All %d harness(es) passed in %ds.\n' "$ran" "$elapsed"
