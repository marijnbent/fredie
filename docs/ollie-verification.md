# Ollie verification

## Build 17 app-wide diagnostics — 13 October 2026

General owns the sole Diagnostics switch. It defaults off and immediately controls optional
window-switcher, clipboard, snippet, Dictation, extension and notification diagnostics, plus
performance signposts. The old Window Switcher control and the separate clipboard preference
are removed. Essential warnings and errors remain available with static event names readable;
user-derived details remain private. Clipboard counts and timing metrics stay readable.
Dictation transcript history, recording retention and credentials are unchanged.

Two Opus source reviews informed the scope and caught a missing extension-harness dependency,
a stale manual test command and logging privacy/usability issues; these were corrected.
All 91 harnesses passed in 128 seconds. Signed Debug builds with no new warnings; lint passes
with existing nonblocking warnings. Model import and diff checks pass.

Native checks on the installed build confirmed General > Diagnostics starts off, turns on, and
persists `diagnosticsEnabled = 1`. Search returns one Diagnostics result under General and opens
that page. Window Switcher has only Shortcuts and Windows sections, with no diagnostic control.
Diagnostics was restored to off and General Settings left open. No feature switches or credentials
were changed. The screenshot confirmed the compact native toggle row.

Signed Release build 17 was installed and opened from `/Applications/Ollie.app`. Deep strict
signature verification passes with the existing Apple Development identity and team X44F5HTS6P.
The installed executable matches the release output:
`ed9ce06a4ba65e8bd9098191d64abcf2b452645f910ac7991dddb9a122c11f38` (SHA-256).
The installed process was verified running.

## Build 16 feature settings consistency — 13 October 2026

Feature pages now use shared permission, notice, removal and setting rows, named native Form
sections, and consistent secret fields. Snippets use the shared editor panel. Dictation uses one
grouped Form with pinned tabs and shared prompt, language and app picker panels; prompt previews
and lazy history loading are retained. Prompt bindings resolve their identity on every access.
Features remains the only place for master switches. No stored preference or credential keys changed.

Two Opus source reviews informed the changes. The second caught editor modifiers attached to a
Group, which could present multiple panels; each is now attached to one view. It also informed
the pinned tabs, history loading, prompt binding and permission status layout fixes.

All 90 harnesses passed in 109 seconds. The final signed Debug build has no new compiler warnings.
Host lint passes with existing/nonblocking warnings; settings-search, model import and diff checks
pass. The isolated native harness mounted all 17 settings panes in light and dark and exited 0.
This mounting check does not prove native Form rendering or every Dictation subtab interaction.

Native testing in the isolated verification app confirmed the Clipboard layout, shortcut recorder
opening and Escape cancellation, and the new Snippet editor layout with Save disabled for empty
input. After Cancel, native capture returned `cgWindowNotFound` for both the preview and installed
app, including after reconnecting and restarting the preview. The preview process remained alive.
Further page/editor interaction checks were blocked by capture failure. No OS grants, real feature
switches, credentials or user snippets were changed. The verification app was closed afterward.

Signed Release build 16 was installed and launched from `/Applications/Ollie.app`. Deep strict
signature verification passes, and its executable matches the release output:
`ee5cb768218ed8a3cef40fe04e993774b69dbbb67decd2d52e734c155b8141eb` (SHA-256).
The installed process was verified running. Native capture still returned `cgWindowNotFound`
after installation, so the final installed window was not visually confirmed.

## Build 15 Launcher disable focus fix — 13 October 2026

Disabling Launcher called the palette dismissal path even when its panel was already hidden.
That path restored the previously focused external app and put Settings behind it; the window
was still open, with Launcher off. Disabling now dismisses only a visible launcher palette and
does not restore another app's focus.

All 90 harnesses passed in one full run. Signed Debug builds with no new warnings; lint,
settings-search consistency, model import and diff checks pass.

Signed build 15 was installed and opened from `/Applications/Ollie.app`. Native testing enabled
Launcher, observed Applications and Emoji appear in the sidebar, then disabled it and observed
both panes disappear while Features stayed open with the Launcher switch focused. Launcher was
left off and Settings open. One native capture failure and one stale-state rejection required
refreshing accessibility state; neither caused an app crash.

## Build 14 Settings crash fix — 13 October 2026

Opening Settings in build 13 crashed with `EXC_BAD_ACCESS` inside the optimized
`Set.contains` call in `SettingsTab.visible(for:)`. The native tool's transient-window errors
had obscured the app crash. The shipping settings harness reproduced it with `-O`, both with
and without whole-module optimization; its unoptimized run had passed.

The filter now unwraps the feature explicitly and calls `enabled.contains(feature)` directly.
The same optimized harness passes all 137 assertions, and the suite now keeps this harness
optimized. Signed Debug builds with no new warnings; lint, settings-search consistency,
model import and diff checks pass. The full suite passed 89 of 90 harnesses; the unrelated
switcher cancellation timing check passed on an isolated rerun.

Signed build 14 was installed at `/Applications/Ollie.app`. Native Command-Comma opened the
Features window successfully: all ten switches were visible, Launcher was on, and the other nine
were off. Only the enabled Launcher's Applications and Emoji panes appeared beside the common
settings pages. Settings was left open; no feature switches or credentials were changed.

## Previous build 13 — 12 October 2026

## Features and standalone-app removal

- Features is the default settings page and contains all ten master switches. Disabled feature
  settings disappear from the sidebar, search and navigation history. Stale links open Features.
  Launcher owns Applications and Emoji; launcher-specific General controls also hide when disabled.
- Per-feature master toggles, standalone-app notices, launch/quit observation, reconciliation polling,
  coexistence guards, old-app imports and their dead reload helpers were removed.
- All 90 remaining harnesses passed: the full run passed 89 and found one outdated expected pane
  list; the corrected settings harness passed again, including visibility, search and stale-route
  checks. The removed adoption feature's harness was deleted.
- Signed Debug compiled with no Swift compiler warnings. Xcode emitted its existing AppIntents
  metadata-skipped notice. Lint and settings-search consistency checks passed with existing style
  warnings. Model import checks and `git diff --check` passed.

## One-time local settings transfer

The user explicitly requested copying current settings and keys, and closing the original apps.
A temporary local helper performed the transfer while Ollie was stopped, then independently verified
exact preference and Keychain values without printing secrets. No runtime migration remains in Ollie.

- 34 settings copied, including dictation provider, prompts, language and microphone choices,
  shortcuts, clipboard retention, 11 snippets, switcher options, typing sounds and import destinations.
- Six configured dictation keys and two notification topics verified in seven Ollie Keychain records.
  New records allow the installed Ollie app and the temporary transfer helper to read them.
- Fredie's preferences and credentials already use Ollie's stable identity and were retained.
  Nettie has no persisted feature preferences beyond window/onboarding state to transfer.
- Feature enable switches were left unchanged. Original preferences, histories and media are intact.
  Ollie's previous preferences were backed up with owner-only permissions beneath
  `~/Library/Application Support/nl.bentjes.fredie/SettingsTransferBackup/`.
- Importie, Ntfy Notifier, Talkie, Nettie, Clippie and Tabbie were gracefully quit. Typie was already
  stopped. Process verification after installation found none of these standalone apps running.
  Mailie was excluded.

## Installed artifact and native-check limit

Version 0.1.0, build 13 is installed and running from `/Applications/Ollie.app`.
The stable identifier is `nl.bentjes.fredie`. Host `codesign --verify --deep --strict` passed using
`Apple Development: marijnbent@gmail.com (S4ZHLE3A52)`, team `X44F5HTS6P`.
Installed and release executables match at SHA-256
`31fa1e275c1d54277f7bbfce266da979afc66dcdac452124286870c3a9ab1072`.

Native control of the newly restarted launcher again rejected Settings navigation with
`The user changed '/Applications/Ollie.app'` and `noWindowsAvailable`, following a timeout.
The user has been asked to open stable Settings manually. The new page's live toggle interaction
and visual check remain pending; passing model tests and a signed build do not prove those checks.
Earlier native results below apply to build 12, not the new Features page.

## Previous build 12 verification

Version 0.1.0, build 12. Product Ollie; stable identity `nl.bentjes.fredie`.

## Automated checks

- All 91 repository harnesses passed again in 157 seconds after the native lifecycle fix,
  including five new Ollie harnesses.
- The dictation harness compiles the shipping runtime and tests recording start/stop cancellation,
  reconnect, finalization, late callbacks, provider failure, shutdown, verified paste restoration,
  preserving a newer clipboard copy, and persistence failure/retry.
- After a Release-only cache conformance failure, the caches were changed from NSCache subclasses
  to owning instances. The icon, entry-icon, and extension-icon harnesses all passed again,
  including an additional optimized whole-module cache test.
- Clipboard tests cover full large-text retention/search, duplicate capture, payload path and symlink
  rejection, failed write retry, corrupted history preservation, and snippets.
- Switcher tests cover off-main AX work, queued cancellation, snapshot coalescing/stale generations,
  inventory scheduling, and Space policy.
- Services tests cover notification stream parsing/checkpoints, import identity/cancellation,
  network parsing/history, sound samples, shared synthetic input, and update activity gates.
- Adoption tests use synthetic files to verify staging, refusal of occupied destinations and symlinks,
  original data preservation, recording path rewrite/permissions, and SQLite WAL backup.
- The final signed Debug build succeeds with no Swift compiler warnings. Xcode emits its existing
  AppIntents metadata-skipped notice because this target does not link AppIntents.
- `scripts/lint.sh` and settings-search checks pass. SwiftLint emits non-blocking warnings, mainly
  line length in ported source. No model imports AppKit, SwiftUI, or Cocoa.
- The new feature directories contain no `ObservableObject`, `@Published`, `NSAlert`,
  `URLSession.shared`, `Bundle.module`, or `assumeIsolated`.

Clipboard shortcut registration is removed while both clipboard and snippets are disabled or Clippie
is still running. Existing saved bindings are retained and re-registered when the feature becomes active.
Startup conflict checks run after saved host hotkeys have loaded.

## Native view checks

The isolated, signed `nl.bentjes.ollie.verification` Debug app mounts all 16 available settings panes
in both appearances and exits successfully. It does not start capture services or access the installed
app’s data. The compact menu renders correctly in light and dark, including its icon action strip.

Offscreen PNG capture does not reliably capture native Form controls. This check proves settings
mounting, not full settings visual quality.

With the user's native testing permission, the installed app was exercised through Computer Use:

- Native Clipboard, Dictation, Permissions, Network and Notifications settings were visually inspected.
  Dictation's Recording, Shortcuts and empty History panes responded correctly. No audio was recorded
  or transmitted, and no OS permission was changed.
- Testing found that standalone-app launch/quit notifications could leave stale ownership state.
  Build 12 reconciles the running-app set through the existing shared one-second health ticker and
  excludes terminated applications. On build 12, Quit Clippie terminated its process and removed
  the notice; reopening Clippie through Finder restored the notice without restarting Ollie.
- With Clippie stopped, enabling clipboard history captured the synthetic text
  `Ollie native clipboard test 2026-10-12`. Saved items changed from zero to one; Open History showed
  the complete text in the list and preview. Clipboard history was returned to off afterward.
- Quit Tabbie removed its process and notice. Enabling Window Switcher reached its active state;
  reopening Tabbie restored the notice. The automated Command-Tab press produced no observable
  result, so actual desktop window selection remains unverified.
- Clipboard history, Window Switcher and menu-bar visibility were restored to their original off
  settings. Clippie, Tabbie and Talkie were verified running. Finder was returned to Desktop and
  Ollie's Clipboard Settings was left open. One synthetic clipboard test entry remains; no history
  was cleared or imported.

The native control tool intermittently rejected actions on the transient launcher with
`The user changed '/Applications/Ollie.app'`; stable Settings worked, and launcher-to-Settings
navigation worked after installing build 12. The compact status-menu button was not exposed in the
available native accessibility tree, so its live click interactions remain unverified. Live
microphone/provider transcription, permission prompts and cross-app paste/snippet expansion also
remain unverified. The automated harness coverage above does not replace those live checks.

## Consultation and scope

Opus round 1 informed the integration and release checks. Rounds 2 and 3 failed with Claude API rate
limits and supplied no additional review. Network monitoring is implemented; network enforcement is
not active because the configured Personal Team cannot provision the required extension capability.
The existing future protection plan is not a claim of shipped filtering. Mailie is excluded.

## Installed release

The final signed Release build succeeded and installed/opened `/Applications/Ollie.app`.
`codesign --verify --deep --strict` passes with host access to the trust store. The bundle reports
version 0.1.0, build 12,
identifier `nl.bentjes.fredie`, and the unified-app marker. The signing authority is
`Apple Development: marijnbent@gmail.com (S4ZHLE3A52)`, team `X44F5HTS6P`.
The installed executable matches the release output exactly:
`e3f184da2564ffca53ab16866647770b9c681db037379deedee4d6368ad858d7` (SHA-256).
The process was verified running from `/Applications/Ollie.app/Contents/MacOS/Ollie`.
The old `/Applications/Fredie.app` bundle was replaced. Original sibling app repositories remain clean;
no sibling app data was adopted automatically, and Mailie was not modified.
