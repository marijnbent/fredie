# Fredie

A native macOS menu-bar launcher, forked from [Tinycast](https://github.com/abue-ammar/tinycast).
SwiftUI and AppKit, with app search, hotkeys, quicklinks, window
management, and native Raycast extension support.

Requires macOS 26+, Xcode 26, and XcodeGen (`brew install xcodegen`).

## Build and install

```sh
./scripts/release-local.sh
```

Quits Fredie if it is running, builds a signed Release bundle, verifies the bundle,
installs `/Applications/Fredie.app`, and opens it. Signing uses the existing Apple Development
identity recorded in `release/Release.plist`. A missing identity or signing failure stops the
release; there is no unsigned fallback.

Separate steps:

```sh
./scripts/build-release.sh
./scripts/install-release.sh
```

The build is at `build/Release/Fredie.app`. Version and build number live in `project.yml`.
For a signed disk image, run `./scripts/build-dmg.sh`.

## Development

```sh
xcodegen generate
xcodebuild -project Fredie.xcodeproj -scheme Fredie -configuration Debug build
./scripts/run-tests.sh
./scripts/lint.sh
```

Release uses `nl.bentjes.fredie`; Debug uses `nl.bentjes.fredie.dev` and is named `Fredie Dev`.
Preferences, files, permissions, URL scheme (`fredie://`), and backups are separate from Tinycast.
Update checks use only `marijnbent/fredie`. No Fredie GitHub release has been published yet.

See [development](docs/development.md), [release](docs/release.md), and [testing](docs/testing.md).
The inherited `website/` is upstream material, not a published Fredie website; its deployment
workflows remain restricted to the upstream repository.

## License and attribution

Fredie retains Tinycast's [AGPL-3.0 license](LICENSE), original copyright notices, and
[third-party notices](NOTICE.md). Tinycast was created by Abue Ammar. The inherited icon and
core launcher features are retained. In-app support links explicitly support the upstream Tinycast project.
