# Consult: unified Ollie — first round

The smallest architecture that works is the one you have already started: sibling sources ported into `Ollie/Features/<Feature>/` inside the single app target, with one coordinator per feature owned by `AppCore`. Network enforcement is not deliverable with the current signing setup; only monitoring is. Nothing was edited, built or installed.

## Problems in the code already landed

The tree was changing while I read it, so re-check each of these against the current files.

- **`Ollie/Features/Network/UI/NetworkCoordinator.swift`, `receive(_:start:end:)`:** the `rates = Dictionary(uniqueKeysWithValues: …)` statement ends in a stray `}, center: center))`. It looks like a replace-all meant for the two `NotificationToken` lines. As read, it does not compile.
- **Same file, `fail(_:)`:** the logger subsystem is still `"nl.bentjes.nettie"`.
- **`scripts/lib/release_common.sh` and `scripts/build-dmg.sh:12`:** still hard-code `Ollie.app` and `MacOS/Ollie` (see section 1).
- **`CompactMenuController.applyVisibility()`:** it obeys only `showInMenuBar`. With Launcher off and that setting off, nothing opens Settings. Treat the item as visible whenever the Launcher is off.
- **`SettingsTab.swift:67`:** the section title is a literal `"Ollie"`. `Bundle.main.appDisplayName` keeps "Ollie Dev" correct.
- **`TypingSounds/Service/KeystrokeMonitor.swift`:** the tap callback hops with `Task { @MainActor }` for every key. The source is on the main run loop, so `MainActor.assumeIsolated` (as in `ModifierTapMonitor`) removes a scheduling hop from every key sound.
- **`TypingSoundsCoordinator.apply()`:** it requires `CGPreflightListenEventAccess()`. Ollie's `ModifierTapMonitor` is listen-only and its code refers only to Accessibility (`needsAccessibility`). I did not test whether the preflight returns true with Accessibility alone. If it does not, try `monitor.start()` first and ask for Input Monitoring only when `tapCreate` fails.

## 1. Heads, identity and release boundary

- **Siblings:** all clean on `main`: clippie `17002ea`, talkie `dbf93dd`, tabbie `83d5533`, typie `0f9ea25`, importie `9a1a3ae`, nfty-notifier `e1fe09f`, nettie `1c5a5ed`. Mailie has two dirty files and is untouched.
- **Ollie:** `main` at `7775cb92`, clean when I started. It now carries your uncommitted work: 12 modified files plus `Features/TypingSounds/`, `Features/Network/`, `App/CompactMenu*.swift` and 13 `Tool-*` image sets.
- **Stale plan line:** `PLAN.md` says Ollie has uncommitted Emoji/launcher changes; the tree was clean at `7775cb92` when I started.
- **Unversioned:** the workspace root and `plans/` are in no git repo.
- **Running now:** Ollie, Clippie, Talkie, Tabbie, Importie, Ntfy Notifier and Nettie. Typie is not. `/Applications/Ollie.app` does not exist yet.

`PRODUCT_NAME: Ollie` keeps the bundle id `nl.bentjes.fredie`, so the defaults domain, `~/Library/Application Support/nl.bentjes.fredie/` and the Keychain service prefix `nl.bentjes.fredie.<scope>` are unchanged. I expect permission grants to carry over too, since the bundle id and certificate are unchanged, but I did not test that. It does change the bundle path and the executable name, which breaks:

| File | Lines | What is hard-coded |
| --- | --- | --- |
| `scripts/lib/release_common.sh` | 5, 6 | `build/Release/Ollie.app`, `/Applications/Ollie.app` |
| same | 17–23 | `pgrep …/Contents/MacOS/Ollie` |
| same | 59–65 | staged `Ollie.app` |
| `scripts/build-dmg.sh` | 12 | `Ollie.app` |
| `docs/release.md` | 5, 7 | both paths |

The `-scheme Ollie` and `Ollie.xcodeproj` references stay valid, and `verify-signature.sh` derives the executable from the bundle name.

Two things the install step must also do:
- Quit and remove `/Applications/Ollie.app` once `Ollie.app` verifies. Otherwise two bundles share one bundle id.
- Re-register the login item if it was on, since it was registered from the old path. I did not verify how macOS handles the move.

One identity risk I did not read far enough to settle: `Features/Updates/` still checks for releases with a `Ollie` User-Agent. Confirm it cannot install an upstream build over Ollie.

## 2. Integration architecture

**Choice: port into `Features/<Feature>/{Model,Service,UI,Settings}` in the one app target.**

- **Collisions are small once the shells go.** I scanned top-level type names. After deleting each sibling's `AppDelegate`, `AppMenuBuilder`, `SettingsWindowController`, `SettingsView`, `MainWindowController` and `main.swift`, these remain:
  - Against Ollie: Tabbie's `AppSettings` and `SpaceSwitcher`; Talkie's `SettingsTab`, `GeneralSettingsView` and `AboutView`, which are settings UI you rewrite anyway.
  - Between siblings: `SettingsStore` (talkie, tabbie, typie, importie), `DiagnosticsLog` (clippie, tabbie), `HistoryLimit` and `ShortcutAction`.
  - That is about ten renames in total.
- **Per-feature Xcode targets cost more than they save.** Ported UI has to use Ollie's `DesignSystem`, `DialogController`, `HotKeyManager`, `Paster` and `AppSettings`, which live in the app target. A library target cannot import the app, so each would need a public facade and inverted protocols for a dozen host services.
- **Namespace enums** touch every declaration for the same ten renames.
- **NettieCore as plain source** (what you did) settles the plan's open "target or source group" question without SwiftPM.

Swift 6 and isolation:
- `project.yml` sets Swift 6 and complete strict concurrency but no default actor isolation. "`@MainActor` by default" is a convention; each type must be annotated.
- Talkie, Tabbie, Typie, Importie and Ntfy already build in Swift 6 mode. Moving them is renames and house rules, not concurrency repair.
- **Clippie is the exception** (`swiftLanguageModes: [.v5]`). `ClipboardStore`, `ClipboardWatcher`, `SnippetStore` and `SettingsManager` are unisolated classes on `DispatchQueue` and `NSLock`. Make the first two `@MainActor @Observable` and move disk work to `nonisolated static` functions called from `Task.detached`.
- **House rules nothing enforces.** `.swiftlint.yml` has no custom rules, so add grep gates to `scripts/lint.sh` for:
  - `ObservableObject`: clippie 6 classes, talkie 5, tabbie 3, importie 2.
  - `NSAlert`: `clippie/Views/HistoryWindow.swift:219,244`, `importie/…/UI/SettingsView.swift:132`, `nfty-notifier/…/AppDelegate.swift:261,309`.
  - `URLSession.shared`: talkie `OpenRouterClient.swift:29`, `CelerisClient.swift:21`, `DeepgramPrerecordedClient.swift:29`, `ElevenLabsPrerecordedClient.swift:36`; ntfy `NtfySubscriber.swift:46`.
- `Bundle.module` appears once (`TalkieApp.swift:38`) and goes away with the shell.

Launcher off needs gating in `AppCore.start()`, which today always runs `appIndex.start`, `appIndex.refresh()`, `emojiIndex.load` and wires `hotKeys.onTogglePalette`. Have `hotKeys.allowsAction` return false for `.togglePalette` and launcher-only commands.

## 3. Seams per sibling

| Sibling | Event tap | Shortcut | New permission | Data to adopt |
| --- | --- | --- | --- | --- |
| Clippie | modifying, `Services/SnippetExpansionController.swift:55` | Carbon ⌥/ (`Services/HotkeyManager.swift`) | none | `~/Library/Application Support/clippie/` (185 MB: `history.json`, `images/`, `texts/`); defaults `savedSnippets`, `historyLimit` |
| Talkie | modifying, HID level, `Runtime/Adapters.swift:446–493` | hold/toggle, `Talkie.Shortcuts` | Microphone | `~/Library/Application Support/Talkie/` (136 MB: `transcript-history.json`, `HistoryAudio/`); 20 defaults keys |
| Tabbie | modifying, `ShortcutMonitor.swift:89` | intercepted in the tap | none | defaults `tabbie.settings` (one JSON blob) |
| Typie | listen-only (ported) | none | Input Monitoring, possibly | 7 defaults keys, volumes as `Double` 0–1 |
| Importie | none | none | removable volumes | `Importie/ImportLedger.json`; defaults `Importie.PreferredLocations` |
| Ntfy | none | none | Notifications | defaults `subscribedTopics` |
| Nettie | none (ported) | none | none | `~/Library/Application Support/Nettie/usage.sqlite` (+ `-wal`, `-shm`) |

**Clippie**
- Replace its private synthetic marker (`0x425546464552`, line 17) with `Paster.ollieEventTag`, and subscribe the tap to `HealthTicker`.
- Make the shortcut a new `CommandID`. `HotKeyAction.builtInActions` then makes it bindable with no new case.
- `ClipboardStore.init(storageDirectory:)` already takes a directory. Use a `Clipboard/` subfolder: Ollie's own App Support still holds `clipboard.sqlite3` and `images/` from the feature removed in `0c37d7e0`.
- Teardown order, from `clippie/AppDelegate.swift:53–60`: `stopWatching()`, `finishPendingProcessing()`, `flushPendingHistorySave()`, then stop the tap. All are synchronous, so they fit `prepareForTermination()`.
- The watcher learns about its own pasteboard writes through `.bufferDidWritePasteboard`. `Paster.pasteString` must report its writes the same way, or the launcher's pastes land in history.

**Talkie**
- `TalkieApp.swift` is already a ports-and-adapters composition root (`Runtime/Ports.swift`). `DictationCoordinator` is that file without the `NSApp`, menu and icon lines.
- `HotKeyManager.register` has only `onKeyDown`, so keep Talkie's `ShortcutRuntime` and `ShortcutStateMachine` as the trigger. Add a reserved-bindings closure to `HotKeyManager.conflictOwner` so conflicts are still reported, and pause the runtime while `hotKeys.recordingAction != nil`.
- `Adapters.swift:408–414` posts an untagged ⌘V. Tag it, or typing sounds click on it and snippet expansion reads it.
- Keep `PasteRuntime` and `PasteVerification`: they do the snapshot, restore and verification that `Paster` lacks.
- Store paths hard-code "Talkie" at `TranscriptHistoryStore.swift:58–62` and `RawRecordingStore.swift:155–163`. Inject the directory.
- **Data-loss check before the first launch on adopted data:** `TalkieApp.swift:140` prunes recordings the history does not reference. If history entries hold absolute URLs into the old folder, every copied audio file would be pruned. I did not confirm the stored format.
- **Secrets:**
  - Five API keys sit in plain defaults (`nl.bentjes.talkie`): `Talkie.ApiKey`, `Talkie.ElevenLabsApiKey`, `Talkie.MuseApiKey`, `Talkie.OpenRouterApiKey`, `Talkie.CelerisApiKey`.
  - AssemblyAI is in the Keychain: service `nl.bentjes.talkie.assemblyai`, account `api-key`.
  - `KeychainSecretStore` accounts are UUIDs, so add a scope with six fixed UUID constants.
  - Reading Talkie's Keychain item from Ollie will probably raise a macOS prompt. Do that read only on an explicit import click, or have that one key re-entered.
- Restore `com.apple.security.device.audio-input` and `NSMicrophoneUsageDescription`.
- Teardown (`TalkieApp.swift:61–69`): `runtimeCoordinator.stop()`, `escCancelMonitor.stop()`, `sessionState.flushHistory()`. Quit while recording belongs in `AppDelegate.applicationShouldTerminate`, which already returns `.terminateLater`.

**Tabbie**
- It prompts for Input Monitoring itself (`ShortcutMonitor.swift:52–58`) and polls for Accessibility (`WindowDiscovery.swift:77–83`). Remove both and route through the Permissions pane.
- Replace its private `healthTimer` with `HealthTicker`.
- Rename `AppSettings` to something like `SwitcherSettings`, and compare its `SpaceSwitcher` with the one in Ollie's `WindowManagement` before renaming.

**Importie**
- `FFmpegService.swift:9–10` searches `/opt/homebrew/bin` and `/usr/local/bin`. Use `Platform/ExecutableLocator.swift`.
- Stop is `AppState.stop()` (line 306).
- With the feature off, `SourceMonitor` must not run at all.
- Adopt `ImportLedger.json`, or the next card shows everything as new.
- Delete the automatic login-item registration (`SettingsStore.swift:105–119`).

**Ntfy**
- `subscriber.stop()` is `async` (`NtfySubscriber.swift:69`), so it belongs beside `flushNotesForTermination()`, not in `prepareForTermination()`.
- Topic names are the only access control for a topic on ntfy.sh, and `TopicStore.swift:6–8` hard-codes one in source. Keep topics out of `settings.json` and backup, and do not copy that default into Ollie's repo.

**Nettie**
- Keeping Nettie's own pty code was right. `Platform/PseudoTerminal.swift` sends EOF to stdin, and `nettie/docs/evidence/2026-10-10-monitor.md` measured `nettop` spinning on that.
- Your store is a new `…/nl.bentjes.fredie/Network/usage.sqlite`. Copy the old database only after Nettie quits, with its WAL files.

**All siblings**
- Six are running now. Each feature should refuse to start while its sibling's bundle id is running and show that as its status. Otherwise ⌘Tab is intercepted twice, every notification arrives twice and the clipboard is recorded twice.
- `SMAppService.mainApp` cannot unregister another app's login item. Turning old login items off is a manual or per-app step.
- Never import an enabled flag during adoption.

## 4. Reusable code and tests

Ollie host pieces to reuse:
- `HealthTicker`, `NotificationToken`, `Paster.ollieEventTag`, `KeychainSecretStore(scope:)`, `AppPaths.applicationSupport()`, `ExecutableLocator`.
- `AppCore.confirm`, `choose` and `showProgress(_:onCancel:)` for dialogs and import progress.
- `UpdateActivity` (`Features/Updates/Model/UpdateReadiness.swift:4`) for recording and importing blockers.
- `SettingsTab.ownedCommands` for command ownership.
- `FeatureSwitchSection` (`DesignSystem/SettingsComponents.swift:290`). Its `showsInLauncher` binding is required, which does not fit non-launcher features.
- Commit `0c37d7e0` as the inverse wiring checklist. Do not restore its code: it was a different clipboard (SQLite) and a different dictation engine, and the user's data is in Clippie and Talkie formats.

Sibling code to lift nearly unchanged, with its tests:

| Sibling | Sources | Tests |
| --- | --- | --- |
| Talkie | `Runtime/{ShortcutStateMachine,RecordingRuntime,PasteRuntime,PasteVerification,Ports}.swift`, `TranscriptionReconnectPolicy.swift`, `ShortcutOwnershipPolicy.swift` | `Runtime/PasteRuntimeTests` (539), `Runtime/RecordingRuntimeTests` (416), `Runtime/RuntimeTestDoubles` (330), `HistoryTests` (551), `ShortcutStateMachineTests` |
| Tabbie | `WindowDiscoverySupport.swift`, `WindowRegistry.swift`, `AXWindowInventoryReader.swift`, `WindowRefreshScheduler.swift` | `WindowDiscoverySupportTests` (490), `SwitcherPanelTests` (295), `WindowActivationTests`, `ShortcutMonitorTests` |
| Clippie | `Models/`, the change tracker in `Services/ClipboardWatcher.swift`, `SnippetExpansionPolicy` | `Tests/ClipboardWatcherTests.swift` (284) |
| Importie | `ClipScanner`, `ImportService`, `ImportSupport`, `MediaDiscovery` | `ImportWorkflowTests` (384), `ImportieTests` (232) |
| Ntfy | `NtfyMessage`, `NtfySubscriber`, `EventTimeFormatter`, `TopicStore` | four files, 248 lines |
| Nettie | already ported | `MonitorTests` (87), `AppIdentityTests` (64) |
| Typie | already ported | `SoundEngineTests` (82), `KeystrokeMonitorTests` (15) |

Ollie has no XCTest target. Each suite becomes one `Tests/<name>.swift` harness plus one `run` line in `scripts/run-tests.sh` listing the shipped sources. Port the Talkie paste and recording suites and their doubles first; they guard the riskiest behaviour. Add one new harness for adoption: fixture plists and folders in a temp directory, asserting that no enabled flag is set and that secrets reach an injected store.

## 5. Signed install and network enforcement

Evidence as of today:
- **Identity:** `security find-identity` shows one valid identity, `Apple Development: marijnbent@gmail.com (S4ZHLE3A52)`, team `X44F5HTS6P`, valid until 21 March 2027. There is no Developer ID.
- **Profiles:** no provisioning profiles exist on the machine, and no installed app embeds one.
- **Earlier attempt:** `nettie` `95f5483^:docs/SIGNING.md` quotes Xcode: "Personal development teams … do not support the Network Extensions capability."
- **Earlier build:** `nettie/docs/evidence/2026-09-15-build.md` records that the filter compiled only with signing disabled, and lists all allow/block behaviour as unverified.
- **Installed state:** `systemextensionsctl list` shows no Nettie extension. No filter from this workspace has ever run on this Mac.

The boundary:
- **Deliverable now:** per-app usage monitoring through `nettop`. The UI must say "Monitoring only" (yours does) and must not carry a protection toggle.
- **Not deliverable:** any per-app allow/block. It needs a paid Apple Developer Program team and provisioning profiles for the host and the extension. I know of no unprivileged alternative; `pf` cannot filter by application.
- **Cost of doing it later:** moving Ollie to a paid team changes its signature. Expect permission grants and Keychain access to reset; decide before adoption, not after.
- **Recoverable code:** the old filter is at `nettie` commit `8556430` (`NettieFilter/`, `Tests/EngineTests`), all untested.

For the signed install, hardened runtime and manual signing work as they do today. The only entitlement change is the microphone pair, which `verify-signature.sh` checks. Mirror any usage strings from Talkie's and Importie's `Info.plist`; I did not read those.

## 6. Stage plan and risks

| Stage | Content | Why here |
| --- | --- | --- |
| 0 | Shell (see below) | everything else depends on it |
| 1 | Typing sounds, Network (landed) | finish and fix the items above |
| 2 | Notifications | small; first use of the notification permission, private session and secret topics |
| 3 | Media import | no taps; first active-work row, Cancel and quit blocker |
| 4 | Clipboard and Snippets | first modifying tap; the Swift 5 conversion |
| 5 | Window switcher | second modifying tap; ⌘Tab |
| 6 | Dictation | largest; microphone, HID tap, six secrets, quit while recording |
| 7 | Adoption per feature, then signed install | old apps and data kept until verified |

Stage 0 covers:
- release scripts
- Launcher-off gating
- a start-up order where the strip and Settings exist before any feature starts
- the `UpdateActivity` and quit hooks
- the microphone, Input Monitoring and notification rows in `Permissions.swift`
- one shared synthetic-event tag
- reserved bindings in `HotKeyManager`
- the running-sibling guard

Taps arrive one stage at a time, so interference can be bisected. Network enforcement is not a stage; it is blocked on the team.

Where the risk concentrates:
1. **Double operation during transition.** Six siblings are running; see the guard in section 3.
2. **The tap stack.** With Hyper key and the palette's escape tap active, up to eight taps share the main run loop with launcher indexing and AI streaming. A busy main actor delays every modifying tap and triggers `tapDisabledByTimeout`. Keep callbacks to scalar decisions, as `HyperKeyTap` does.
3. **Clippie's conversion** touches the tested 2,690-line `HistoryWindow.swift`. Change isolation and the two alerts only; leave the view's logic alone.
4. **Adoption data loss.** The Talkie prune is the known case. Copy, never move, and never point old and new at one folder.
5. **Identity.** The stale `/Applications/Ollie.app`, the login item and the updater.
6. **Secrets.** Five plaintext keys and the topics must never reach `settings.json` or a backup. Follow the `SettingsBackupCoverage.deliberatelyExcluded` pattern you used for typing sounds.

## Not checked

- Whether Tabbie needs Screen Recording or uses private window-server calls.
- Whether Importie's bookmarks are security-scoped; if so they will not resolve in Ollie.
- Whether Ollie already sets a `UNUserNotificationCenter` delegate.
- Whether any sibling declares its own actor, which would break the one-actor rule.
- Which test framework the sibling suites use.
