# Signing

Fredie's local release uses the existing Apple Development certificate selected in
`release/Release.plist`. It must appear in `security find-identity -v -p codesigning`.
The project uses team `X44F5HTS6P`; Xcode signs the app and embedded helpers during the build.

The release scripts fail if the identity is unavailable, signing fails, an embedded helper is
missing, or strict signature verification fails. They never fall back to unsigned or ad-hoc output.
The stable bundle identifier and signing identity keep macOS permissions consistent across rebuilds.

This is a local development-signed release, not a notarized public distribution. Public releases
would need a separate Developer ID and notarization setup. No certificates or private keys are
stored in the repository.
