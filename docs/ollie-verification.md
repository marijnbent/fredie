# Ollie verification — 12 October 2026

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
