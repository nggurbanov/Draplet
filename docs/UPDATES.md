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
builds may use an Apple Development identity. Ad-hoc identity is tied to the
binary hash, so an update can invalidate existing macOS privacy grants even
when the bundle identifier stays the same. Automatic releases now require an
explicit stable signing certificate; use Developer ID Application for public
distribution. Ed25519 archive signatures do not preserve TCC permissions.

## Permission recovery after 0.5.1

The 0.5.1 automatic rollout is paused; the feed temporarily advertises 0.5.0.
Installed 0.5.1 copies are not downgraded. The release remains available manually.

If the right arrow opens Settings and the left arrow is absent, check the
Accessibility setup message. Open System Settings → Privacy & Security →
Accessibility and authorize the current `/Applications/Draplet.app`. If an old
entry stays enabled but no longer applies, remove that entry and add the current
app again. Also check Screen & System Audio Recording for background matching
and Pocket capture, then quit and reopen Draplet if macOS requests it. Draplet
captures no audio. App preferences and pins do not need resetting.

Future automatic updates must retain a compatible certificate-based designated
requirement. Test an authorized previous app updating to the candidate; the
isolated installer fixture deliberately has no privacy grants and cannot verify
their preservation. A signing-identity migration needs a separate acceptance test.

## Prepare a release

1. Increase both version and monotonically increasing `CFBundleVersion` in
   `Resources/Info.plist`. Add `updates/<version>.html` release notes.
2. Run `bash test.sh`, then set `DRAPLET_SIGNING_IDENTITY` to an explicit stable
   signing certificate and run `bash scripts/prepare-release.sh` on macOS.
   Ad-hoc, unset and automatic identity selection are rejected. Set
   `DRAPLET_PREVIOUS_RELEASE_APP` to the previous authorized app to check mutual
   requirement compatibility; also verify its real permissions after updating.
   It creates a DMG, symlink-preserving updater ZIP, SHA-256 file and candidate appcast
   and corresponding-source archive in ignored `dist/`. It does not upload or publish anything.
3. Verify the actual N→N+1 update, failure paths, mounted DMG and current app behavior.
4. Prepare and verify GPL v3 corresponding source for the exact binary build.
   Include the matching application source, build/install scripts, vendored
   adaptations and license notices, plus required dependency sources and build
   instructions. Preserve the original MIT and component notices and confirm
   the Ice and Thaw revisions in `Vendor/Ice/ORIGIN.md` and
   `Vendor/Thaw/ORIGIN.md`. A dependency download URL or an
   attribution alone is not a substitute for required corresponding source.
   `scripts/prepare-source.py` creates the matching source archive and manifest.
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

The current public alpha is [0.5.1 build 46](https://github.com/nggurbanov/Draplet/releases/tag/v0.5.1),
from source commit `5f76f076b784bc68e30cf329b6013ed9eacf24bb`.
The tag identifies the application source; subsequent main-branch commits publish
release metadata and the feed. DMG, updater ZIP, complete source snapshot and
SHA-256 checksums accompany the release. Its automatic rollout was paused after
the permission-identity regression; the feed currently advertises build 45.
Build 46 has 380 checks and current installer, signature and packaging evidence
described in [release readiness](RELEASE_READINESS.md). The first public alpha,
0.5.0 build 45, remains the broader native-test baseline. Older build-13/15 draft
results are historical and do not describe the published binaries.

Run `python3 scripts/prepare-source.py` after preparing the binary artifacts.
It exports the public source tree, exact Sparkle dependency sources (including
its vendored dependencies), source file hashes and the packaged executable hash.
It refuses source changes during export. Keep this source archive beside the
matching binary downloads. This does not publish the source or modify the feed.

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
