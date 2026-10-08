# Backup

Export and import of Fredie's own data as a single `.fredie` file, plus the entry point for
importing a Raycast export. The feature lives in `Features/Backup/`.

A backup carries three independently selectable categories, ticked on export and again on import:
**Settings & Shortcuts**, **Notes** and **Launcher Learning**.

## Invariants

- **`SettingsBackup`'s mirror is hand-written, and reflection is never the fix.** `AppSettingsKey` owns
  every key `AppSettings` persists; `SettingsBackupCoverage` says which of them `SettingsData` carries,
  which are sourced from somewhere other than `UserDefaults`, and which are excluded **with a reason**.
  `settings-backup-test` fails when a key is none of those. Adding a setting means editing
  `SettingsBackupCoverage` in the same commit.
- **A flag that grants a capability is never carried by a backup**, whether it is excluded from
  `SettingsBackupCoverage` like `extensionsEnabled` or kept out of `AppSettings` entirely. Importing a
  config must not be able to grant something the user never granted. `FallbackStore` is the second
  case: its order and checkboxes live on their own `UserDefaults` keys precisely so an import cannot
  arm **Run Shell Command** in someone's launcher. This change adds *content*, never a capability.
- **The file carries a format version and a reader accepts only its own.** That is a guard, not a
  migration: the comparison is `==`, so an older and a newer file fail identically and by the same
  statement. Writing it any other way is the first line of a migration, and the project has none.
- **Extensions, AI chat history, Keychain material and anything in `Caches` never travel.** An
  extension is third-party code and third-party data; chat history and API keys stay on the Mac that
  had them; a cache regenerates on its own.
- **`BackupCategory` names every category, and its `descriptor` switch is exhaustive.** A new case
  fails to build until it names a label, a symbol, a bundle subpath and a count noun — the same
  bargain `AppEntry.Kind` makes, and why the bundle layout is never spelled out twice.

## Layout

| File | Role |
| --- | --- |
| `Model/BackupCategory.swift` | The categories and the descriptor every one of them must name |
| `Model/BackupManifest.swift` | The table of contents, the format constant and its guard |
| `Model/BackupBundle.swift` | The payload directory's layout and part-by-part encode/decode |
| `Model/BackupArchive.swift` | Directory ⇄ `.fredie`; the only file importing `AppleArchive` |
| `Model/SettingsBackup.swift` | The settings, fixed/per-item hotkey payloads, and their `Codable` shape |
| `Model/SettingsBackupCoverage.swift` | The coverage declaration the harness checks |
| `Model/RaycastImport.swift` | The importable categories, the `Result` and its per-category trim |
| `Model/RaycastImportError.swift` | The three failures an import reports |
| `Service/BackupStaging.swift` | One scratch tree, created on init and removed on discard |
| `Service/BackupComposer.swift` | Stores → staging; `plan` on main, `write` off it |
| `Service/BackupApplier.swift` | Staging → stores, returning a per-category summary |
| `Service/BackupActions.swift` | The effectful half: file pickers, the archive calls, dialogs, the settings-file switch |
| `Service/RaycastDecoder.swift` | Container recognition, decrypt and decode |
| `Service/RaycastImportReader.swift` | Raycast → Fredie field mapping |
| `Service/Scrypt.swift`, `Platform/Compression/Zlib.swift` | The crypto and decompression primitives |
| `Settings/BackupCategorySelection.swift` | The category checkboxes, on both halves of the pane |
| `Settings/BackupSettingsView.swift` | The pane, which also holds the [settings file](settings-file.md) switch |

## Inside the file

```
manifest.json              format, app version, createdAt, per-category counts
settings.json              SettingsBackup, exactly as it encoded before
notes/<name>.md            copied verbatim
learning/{ranking,emoji,calculator}.json
```

A category the user didn't tick has no key in `counts` and no files in the archive, which is how the
import picker greys a row out instead of importing nothing and saying nothing.

**AppleArchive, LZFSE, and a deliberately narrow keyset.** `"TYP,PAT,DAT,MOD,MTM"` rather than
`.defaultForArchive`: no `UID`/`GID`, which would restore another Mac's numeric owner, and no `IDX`,
whose hardlink dedup would record a link to a blob outside the staged tree. `MTM` stays because the
note list sorts on modification date.

**Extraction is filtered, not trusted.** `BackupArchive.open` passes an `ArchiveHeader.EntryFilter`
that returns `.skip` for any entry whose path is absolute or contains `..`, and then refuses an extract
holding a symbolic link — a link entry names no `..` at all, so the path filter passes it, and reading
through one would leave the tree the caller chose. Composing resolves a link for the same reason, so a
symlinked note travels as a file. `backup-archive-test` builds both hostile archives header-by-header
and asserts nothing escapes.

**Staging lives in `Caches`, not `temporaryDirectory`.** Leaving the Settings pane discards a tree the user opened but never imported; `BackupStaging` sweeps
anything a day old on the next run, since a run killed mid-flight leaves its tree behind.

## Coverage, and why it is spelled out

`SettingsBackupCoverage` holds three tables:

- `mirrored` — each `SettingsData` field paired with the `AppSettings` key it carries.
- `externallySourced` — fields no `AppSettings` key stands behind, each saying what it reads instead.
  `launchAtLogin` comes from `LaunchAtLogin`, which owns the login item.
- `deliberatelyExcluded` — keys kept out on purpose, each with its reason as a string.

`settings-backup-test` asserts that every `AppSettingsKey` appears in exactly one table, that no field
claims a key twice, that every exclusion names a real key and carries a non-empty reason, and that each
capability-granting key — `extensionsEnabled`, `calendarEnabled`,
`autoJoinMeetings`, `cameraPreview`, `quickActionsEnabled` — is named individually as excluded. The
duplication between `AppSettings` and this file is the point: it forces a decision about every new
setting rather than defaulting it into a backup.

## Importing

Applying an import writes through `AppSettings` like any other change, so feature switches reproject into
the launcher through the normal observation path. An import reports a summary of what it applied — it is
not silent, because a settings file that quietly changes hotkeys is hostile.

Per category:

- **Settings** merge field by field, and a file carrying custom commands or their shortcuts still hits
  `confirmExecutableImport` first.
- **Notes** land as new files through `NotesRepository.importNotes`, which suffixes a title that is
  already taken rather than overwriting it.
- **Learning** replaces. Merging two Macs' frecency tables produces a table describing neither.

The old flat `Fredie-Settings-*.json` export is gone rather than deprecated, and nothing reads it.

Raycast import is documented separately in [raycast-import.md](raycast-import.md).
