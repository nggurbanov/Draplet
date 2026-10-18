# Updates and alpha releases

Draplet uses Sparkle 2.10.0, pinned by SHA-256 in `scripts/fetch-sparkle.sh`.
There is one feed, `updates/appcast.xml`, served from this public repository.
No GitHub credentials are embedded in the app.

By default Draplet checks on launch and then hourly, and downloads updates in the
background. A verified, staged update installs on ordinary exit without relaunching.
“Update and Relaunch” installs immediately and reopens Draplet. Ready updates are
visible on every Settings page. The reminder can be deferred for one hour; fullscreen
and Mission Control postpone it. Turning off automatic checks stops scheduled checks;
manual checks remain available. With background downloads off, a persistent Settings
action and a deferrable reminder open Sparkle’s review/download flow. Already staged
updates remain scheduled for exit.

Archives are Ed25519-signed and verified before extraction. This signature protects
updates; it does not replace Developer ID/notarization or remove initial Gatekeeper
approval for alpha downloads. Public alpha builds are ad-hoc signed. Local development
builds may use an Apple Development identity. Changing that identity can require
re-granting macOS permissions; test the beta signing transition separately.

## Prepare a release

1. Increase both version and monotonically increasing `CFBundleVersion` in
   `Resources/Info.plist`. Add `updates/<version>.html` release notes.
2. Run `bash test.sh` and `bash scripts/prepare-release.sh` on macOS.
   It creates a DMG, symlink-preserving updater ZIP, SHA-256 file and candidate appcast
   in ignored `dist/`. It does not upload or publish anything.
3. Verify the actual N→N+1 update, failure paths, mounted DMG and current app behavior.
4. Prepare and verify GPL v3 corresponding source for the exact binary build.
   Include the matching application source, build/install scripts, vendored
   adaptations and license notices, plus required dependency sources and build
   instructions. Preserve the original MIT and component notices and confirm
   the Ice revision in `Vendor/Ice/ORIGIN.md`. A dependency download URL or an
   attribution alone is not a substitute for required corresponding source.
   No automated corresponding-source archive generator is implemented; the
   existing release script prepares binary artifacts only.
5. Publish the ZIP, DMG, SHA-256 file and matching corresponding-source material
   at GitHub tag `v<version>`. Verify the public downloads and that the source
   actually matches the packaged build.
6. Only then copy `dist/appcast-<version>.xml` to `updates/appcast.xml`, commit and push.
   Do not advertise an archive before its public URL works.

The release signer uses the `DrapletUpdates` account in the login Keychain. Keep its
private key out of Git, shell output and CI logs. The public key in Info.plist must
stay stable across releases. A new contributor can build the app without this key,
but cannot publish a trusted update. Back up the signing key securely before relying
on this feed; key rotation requires a separately tested migration.

## Current acceptance boundary

The local candidate is 0.5.0 build 14 with Pocket. The public v0.5.0 release
remains a build-13 draft and the production feed is empty. Build-13 updater and
DMG results are historical; rerun them against the final build-14 artifacts
before publication. See [release readiness](RELEASE_READINESS.md).

## Isolated update fixture

Build an ad-hoc app with `DRAPLET_SIGNING_IDENTITY=- bash build.sh`, then run
`python3 scripts/prepare-update-test.py [good|bad-signature|network|scheduled]`. Serve
`.build/update-test-http` on loopback port 18734. `scheduled` disables background downloads to exercise the review/reminder flow.
The fixtures have separate bundle
identifiers and never start menu-bar engines, capture or permission prompts.
They exercise the full app binary, Sparkle framework and real installer helpers.
`bad-signature` modifies the archive after signing; `network` serves a missing feed.
The installed fixture must remain build 100 after either failure. The successful
fixture updates from build 100 to 101; ordinary quit must leave it closed, while
Update and Relaunch must start a new process. Test settings preservation as well.
Only test bundle plists allow local HTTP. Production always uses the HTTPS feed.

Fixtures re-sign the entire helper graph through `scripts/sign-app.sh`. They refuse
to overwrite a running host. Use an alphanumeric `DRAPLET_TEST_RUN_ID` for a fresh
bundle/cache identity, or `DRAPLET_TEST_SIGNING_IDENTITY=auto` to exercise the local
Apple Development graph. Ad-hoc is the default; do not mix helper and host identities.
