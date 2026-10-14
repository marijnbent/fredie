# Local release

Run `./scripts/release-local.sh` from the repository root. It quits the installed or locally
built Ollie, builds with XcodeGen and Xcode, verifies the app bundle,
replaces `/Applications/Ollie.app`, and opens the installed app.

- `./scripts/build-release.sh`: signed bundle at `build/Release/Ollie.app`.
- `./scripts/install-release.sh`: verify, install, and open the existing bundle.
- `./scripts/build-dmg.sh`: signed build packaged as `build/Ollie-<version>.dmg`.

`project.yml` owns version, build number, bundle identifiers, and targets. `release/Release.plist`
selects the installed Apple Development signing identity. No unsigned or ad-hoc fallback is allowed.

`release/Icon.png` is the 1024px Happy Pocket Otter icon master. Its macOS sizes live in
`Ollie/Assets.xcassets/AppIcon.appiconset`, selected by `project.yml` for both build configurations.
Run `node scripts/gen-app-icon.js` after replacing the master to regenerate every catalog size.
The menu bar uses the outlined Cheeks otter mark in `Ollie/Assets.xcassets/MenuBarIcon.imageset/otter.svg`
as a vector template, so macOS supplies the light or dark foreground.

A requested local release also includes committing and pushing the current Ollie repository
changes on `main`, after verification. The scripts do not perform Git operations.

## Updates

The updater reads only `marijnbent/ollie` GitHub releases. Local installation does not publish a
GitHub release. Upstream Tinycast release, Homebrew, and announcement automation was removed.
A future release must provide a signed `Ollie-<version>.zip` made with
`ditto -c -k --keepParent --sequesterRsrc`, a `vMAJOR.MINOR.PATCH` tag, and a matching bundle identity
and trusted signing identity. Intel releases need a `-Universal-` zip containing both architectures.
Debug builds never update themselves. See [updates](features/updates.md) for verification rules.
