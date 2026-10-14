# Hotkeys (in-house, zero dependencies)

`Features/HotKeys/` holds:

- `KeyShortcut` — Sendable model, Carbon keycode + modifiers, layout-aware glyphs via `UCKeyTranslate`.
- `HotKeyBinding` — what an action is bound to: `.combo(KeyShortcut)`,
  `.doubleTap(DoubleTapModifier)`, sided `.modifier` / `.doubleModifier`, `.globe`, or `.doubleGlobe`.
- `HotKeyCenter` — the Carbon `RegisterEventHotKey` layer, pausable.
- `DoubleTapModifier` / `DoubleTapDetector` — the double-tap recognizer.
- `ModifierKey` / `ModifierKeyDetector` — reported sides, lone presses, taps and holds.
- `ModifierTapMonitor` — the shared modifier-only tap.

`HotKeyManager` owns them all: persistence, conflict lookup, and dispatch. Every action reads and
writes one `HotKeyBinding`, so all cases share persistence, conflict detection, the recorder and
the keycap rendering — only the _engine_ differs.

Carbon's dispatcher enters through an explicit `@MainActor` callback. Press and release handlers
return `OSStatus` synchronously, preserving event order and hold-to-talk release handling.

## Invariants

- Feature availability gates both registration and dispatch. Disabling a capability unregisters its
  Carbon chords and modifier taps without deleting saved bindings. Independent features retain theirs.

- **Hotkeys persist as JSON strings under `hotkey.<action>` UserDefaults keys**, and
  `HotKeyAction.defaultsKey` is the one place that computes a key — it is also the `HotKeyCenter`
  registration id, so the two cannot drift.
- **A command's shortcut and its launcher row run the same funnel.** `HotKeyAction.command(CommandID)`
  is parameterised over the whole catalog and dispatches through `LauncherCoordinator.runCommand`, so a
  new built-in command arrives bindable with no hotkey plumbing of its own, and there is one behaviour
  per command rather than one per invocation route.
- **A command that opens a palette mode toggles it.** Every one of them enters through
  `PaletteCoordinator.togglePalette(mode:)`, so a second press closes what the first opened. From a
  launcher row the palette is in `.launcher`, so the row always re-points instead.
- **`HotKeyBinding` is the one thing an action is bound to, with two engines.** A
  `.combo` is a Carbon registration; all modifier-only bindings are recognized by
  `ModifierTapMonitor`, because Carbon cannot see a lone modifier at all. Its `Codable` is the
  synthesised one.
- `KeyShortcut`'s hand-written `init(from:)` is a correctness seam, not a format one: it routes every
  decode through the initializer that masks device modifier bits off.
- **The modifier-only detectors stay Foundation-only and pure** for `hotkey-test`, with the clock
  injected as a parameter. Every `CGEvent` call lives in
  `Service/ModifierTapMonitor.swift`, which is listen-only, installs *only* while a modifier-only
  shortcut is bound, and never prompts for Accessibility.

## Persistence

Bindings persist as JSON strings under `hotkey.<action>` UserDefaults keys, computed in one place —
`HotKeyAction.defaultsKey`, which doubles as the `HotKeyCenter` registration id. The set of bound
bundle IDs lives in `boundAppBundleIDs` and is re-registered on launch. After every `AppIndex` scan,
`HotKeyManager.removeAppBindings` clears the binding of an app that is gone from both the index and
LaunchServices: its Settings row went with it, so nothing else could clear the chord. Requiring both
keeps a dropped search scope from deleting a working shortcut, and running on unchanged scans too
covers LaunchServices still resolving an app for a few seconds after it is trashed.

Shortcuts are also spelled as typeable chords (`ctrl+option+left`) in the opt-in
[settings file](settings-file.md) — all but those of content, extensions and Apple Shortcuts.
`HotKeySpelling` is that grammar; `HotKeySettingsFile` applies through `setBinding`, so `UserDefaults`
stays the one store either way.

System Settings panes use `boundPaneBundleIDs`; custom commands, quicklinks, window layouts, rooms
and custom window sizes use their stable UUIDs in `boundCustomCommandIDs`, `boundQuicklinkIDs`,
`boundWindowLayoutIDs`, `boundWindowRoomIDs` and `boundCustomWindowSizeIDs`. Those five are the per-item case — unlike a fixed catalog, there is no `allCases` to walk — so each needs an index for `start()`
to re-register from
and to prune bindings whose record was deleted while Ollie wasn't running. That prune is why
`QuicklinkStore` loads at launch even when the feature is off
(see [quicklinks.md](quicklinks.md#hotkeys)).
Apple Shortcuts keep the same kind of index in `boundAppleShortcutIDs`, pruned not at launch but after
the first successful read of the library, since a failed read looks exactly like deletion
(see [apple-shortcuts.md](apple-shortcuts.md#sweeping-deleted-shortcuts)).



`HotKeyBinding` takes the synthesised `Codable`, so a `.combo` writes
`{"combo":{"_0":{"carbonKeyCode":N,"carbonModifiers":N}}}` and a `.doubleTap` writes
`{"doubleTap":{"_0":"command"}}`. `KeyShortcut` keeps a hand-written `init(from:)` — not a format seam,
but the guarantee that every decode runs through the initializer that masks device modifier bits off.
`SettingsBackup.HotkeyBackup` stores the same values, so the backup file carries this shape too; only
export → import within one build is guaranteed to round-trip.

Every built-in command is bindable: `CommandID.hotKeyAction` answers `.command(self)` by default, and
names the three exceptions. Open in Browser and Run Shell Command are query-driven — their input is the
typed text a chord has none of — and Quit is withheld so no chord can terminate the app outright. The
list is a deny-list rather than an allow-list, so a new command still arrives bindable without an edit
there. A binding therefore persists under `hotkey.<command raw value>`, as in
`hotkey.command:clipboard-history`, which is also what puts a recorder on the command's row and a
keycap on every launcher row. That row is in exactly one pane — Settings ▸ Commands, or the feature's
own pane when `SettingsTab.ownedCommands` names it. `hotkey.togglePalette` is the one fixed action with
no command row. `HotKeyManager` names them all through `CommandID`, so a conflict callout spells an
action exactly as its command row does.

Like a window command, the chord registers regardless of the launcher row. Search Files and Notes both
re-check their feature switches before opening; see [file-search.md](file-search.md#invocation) and
[notes.md](notes.md#ownership-and-enablement). A hidden launcher row does not disable its shortcut, but
disabling the feature does. `SettingsBackup.HotkeyBackup` carries them as one `commands` map keyed by
`CommandID` raw value.

System actions and window commands are the fixed-catalog case: they persist under
`hotkey.systemAction.<raw-id>` and `hotkey.windowCommand.<raw-id>`
and need **no** bound-ID index, because `start()` and `conflictOwner` can just iterate `allCases` and
`register` no-ops on an unbound item. A registered window-command shortcut still runs nothing while the
feature switch is off — `WindowCommandCoordinator.runWindowCommand` re-checks it (see
[window-management.md](window-management.md)); a system-action shortcut likewise goes through
`SystemActionCoordinator.runSystemAction(id:)`, so the confirmation gate holds for a hotkey exactly as it does for the
palette.

## Modifier-only shortcuts

Every recorder accepts a single or double press of a lone modifier, including Globe/fn. Command,
Control, Option and Shift remember the Left or Right identity reported by macOS after remapping.
Single bindings display a small L/R inside the recorder's glyph cap; double bindings display only
the two modifier glyphs while retaining their side for matching and conflicts. Ordinary key
combinations remain side-agnostic. `ModifierKeyDetector` uses injected timestamps and device
flags, so holding both sides or unwinding a chord cannot create a new lone press. Holding a modifier
while recording saves its single binding when released. Existing generic double-tap bindings keep
their meaning; conflicts with overlapping sided double taps are refused rather than overwritten.

The recorder waits briefly after the
first release so another press can select the double binding; otherwise it saves the single one.
Globally, a single modifier fires on release when no double-tap action is bound. When both are bound,
the single action waits until the double-tap window expires. Another modifier, key, or mouse click
cancels the gesture, even while a single tap awaits the second. Both the monitor and the recorder
track Globe from the physical `kVK_Function` keycode, not just the fn flag, because F-keys also carry it.
It shares the double-tap's listen-only monitor, permission warning, lifecycle and pause while
recording. macOS may perform its own Globe action too; set “Press fn/Globe key to” to “Do Nothing” in
Keyboard settings if it conflicts. Globe+key chords use Carbon registration, like other combos.



## Double-tap modifiers

Any action can instead be bound to a **double-tapped lone modifier** — ⌃, ⌥, ⇧ or ⌘. Carbon cannot
register a modifier-only shortcut at all, so this is a separate engine that meets the combo path only
at `HotKeyBinding`.

`DoubleTapDetector` is the recognizer: Foundation-only, pure, and clock-injected (`now` is a caller-
supplied monotonic timestamp), so `Tests/hotkey-test.swift` drives it without an event tap. A **tap**
is a press that starts from no modifiers held, keeps exactly one of the four held with no `fn`
alongside, sees no key press or mouse click, and is released within `maxHold` (250 ms). A **double-tap** is a second tap of the same modifier
starting within `maxGap` (300 ms) of the first one's release.

Only _momentary_ keys may feed `hasOtherModifiers`. Caps Lock must not: `maskAlphaShift` tracks the
**latch**, not a press, so testing it would disqualify every tap for as long as Caps Lock is on and
silently kill the feature. Caps Lock is ineligible as a modifier-only binding.

It **fires on the second release, not the second press**. The modifier is then already up when the
action runs, so the palette never opens with a phantom ⌘ held and focus restoration isn't polluted —
and "double-tap and hold" is a deliberate non-event.

`ModifierTapMonitor` is the one platform file. It is a **listen-only** `CGEventTap` and it installs only
while a modifier-only shortcut is bound, so users who never use the feature pay nothing. Two
details are load-bearing:

- It is `.tailAppendEventTap` and observes the delivered modifier set. Combined modifiers never
  count as a lone physical modifier; the detectors keep both single and double taps isolated.
- Like every keyboard tap it needs the **Accessibility** grant, and it never prompts for it. The
  binding records regardless; the recorder shows an inline warning that opens System Settings, and the
  one-second health timer installs the tap the moment the grant lands.

⇧ is bindable this way even though `KeyShortcut` rejects a bare ⇧ combo: a double-_tap_ is unambiguous
where a bare ⇧ combo would shadow typing.

## External remapping

Ollie records, stores and displays the literal modifiers it receives. A chord emitted by Karabiner
such as ⌃⌥⇧⌘ is handled like any other combo. Ollie does not remap physical keys, alter HID mappings,
or rewrite recorded modifier sets.

## Recorder

The settings recorder (`Features/HotKeys/UI/ShortcutRecorder.swift`) is deliberately **not** a focusable
control: the active recorder is `HotKeyManager.recordingAction` state, and keys are captured by local
NSEvent monitors while both engines are paused. It records combos and single or double modifier taps,
including their reported side, by feeding its `.flagsChanged` / `.keyDown` monitors into the same pure detectors
as the global monitor, so recording needs no event tap and no permission.

Setting `recordingAction` is what starts and stops the capture, so there is exactly **one**
`ShortcutCaptureSession` (`HotKeys/Service/`) for the app rather than one per row — which is what lets the
callout above the field render the live state from outside the row that opened it. The field itself
only ever shows the binding; the prompt, the live preview and the conflict message all live in the
callout. See [ui.md](../ui.md#the-shortcut-recorder-callout).
