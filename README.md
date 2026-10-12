# Ollie

A native macOS utility combining Fredie’s launcher, clipboard history and snippets, dictation,
window switching, typing sounds, camera imports, ntfy notifications, and network usage.
Mailie stays separate. The name Ollie is temporary; the existing Fredie repository and bundle
identity remain in use. The launcher is forked from [Tinycast](https://github.com/abue-ammar/tinycast).

The menu is a compact strip of actions with live activity above it. Native grouped settings hold
independent feature switches, a shared shortcuts page, permissions, and explicit imports from the
original apps. Network provides monitoring; it does not claim to block connections.

Open Settings from the menu strip. New capture features start off. To bring over an existing app,
quit that app, import it under Settings → Backup, then enable the corresponding feature. Notification
topics import from the Notifications pane. Existing Fredie preferences stay in place.

Requires macOS 26+, Xcode 26, and XcodeGen (`brew install xcodegen`).

## Build and install

```sh
./scripts/release-local.sh
```

Quits Ollie or the previous Fredie if it is running, builds a signed Release bundle, verifies the bundle,
installs `/Applications/Ollie.app`, and opens it. Signing uses the existing Apple Development
identity recorded in `release/Release.plist`. A missing identity or signing failure stops the
release; there is no unsigned fallback.

Separate steps:

```sh
./scripts/build-release.sh
./scripts/install-release.sh
```

The build is at `build/Release/Ollie.app`. Version and build number live in `project.yml`.
For a signed disk image, run `./scripts/build-dmg.sh`.

## Development

```sh
xcodegen generate
xcodebuild -project Fredie.xcodeproj -scheme Fredie -configuration Debug build
./scripts/run-tests.sh
./scripts/lint.sh
```

Release uses `nl.bentjes.fredie`; Debug uses `nl.bentjes.fredie.dev` and is named `Ollie Dev`.
Preferences, files, permissions, URL scheme (`fredie://`), and backups are separate from Tinycast.
Update checks use only `marijnbent/fredie`. No Fredie GitHub release has been published yet.

See [unified app](docs/ollie.md), [development](docs/development.md), [release](docs/release.md), and [testing](docs/testing.md).
The inherited `website/` is upstream material, not a published Fredie website; its deployment
workflows remain restricted to the upstream repository.

## License and attribution

Fredie retains Tinycast's [AGPL-3.0 license](LICENSE), original copyright notices, and
[third-party notices](NOTICE.md). Tinycast was created by Abue Ammar. The inherited icon and
core launcher features are retained. In-app support links explicitly support the upstream Tinycast project.
