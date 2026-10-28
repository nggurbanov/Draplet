# Alpha release validation — 0.5.3 build 48 candidate

Version 0.5.3 retains the persistent self-signed Alpha identity introduced in
0.5.2 and the permanent automatic-update floor of build 47. It improves native
rendering and capture ownership without adding Rune or Rust. This section records
candidate evidence; it does not claim publication or updater acceptance.
Validation was performed on 2026-10-28, macOS 27.0.1 / Apple silicon with one
physical display.

| Candidate check | Result |
| --- | --- |
| Lifecycle, preferences, rendering and animation suite | 405 checks passed, including held capture callbacks and the modal-loop Quit regression |
| Native render/lifecycle harness | 11 checks passed; Cached stream retirement, unchanged policy deliveries, repeated curtain toggles, Live Quit and startup Quit |
| Live Quit with an active stream | One registered stream at cleanup; zero pending callbacks before exit, about 80 ms after the final run's Quit request |
| Unchanged-scene observation | No new snapshots, display requests, draws or presentation-policy transitions during a 1.52-second observation; a changing scene separately produced new snapshots and redraws |
| Native QA state preservation | Preference snapshots matched before/after; no controlled app left running; installed app not replaced |
| Signed optimized candidate | Built without compiler warnings and satisfied the installed app's designated signing requirement |

The capture registry tracks streams before start through stop acknowledgement,
serializes start/stop for each stream and waits for retiring streams during
normal AppKit termination. A three-second deadline bounds Quit. Stop errors and
deadline expiry are reported; neither is proof of successful daemon cleanup.
Acknowledgements and the deadline run in modal mode as well as common modes,
fixing the native Live-Quit hang reproduced during this pass.

These native runs used a shell-launched app, so their access to capture is not
independent LaunchServices/TCC acceptance. A staged Sparkle install with active
capture and 0.5.2-to-0.5.3 permission preservation remain release acceptance work.
The broader build-45 native suites were not rerun. No battery-savings, exact GPU
cost or long-term leak claim follows from these short observations. See
[the detailed source review and evidence](RUNE_ADOPTION.md).

## Previous release: 0.5.2 build 47

[0.5.2 Alpha](https://github.com/nggurbanov/Draplet/releases/tag/v0.5.2) uses the
persistent self-signed Alpha identity. Its application source is tagged at
`4b25349f335109e7d5aa14b20d1884bf80c02679`; publication metadata follows on main.
Validation was performed on macOS 27 / Apple silicon with one physical display.

| Check | Result |
| --- | --- |
| Lifecycle, preferences, rendering and animation suite | 380 checks passed |
| Real-signature release policy | 15 cases passed, including legacy gating, later-release notices and unlaunchable runtime rejection |
| Published build-45 and build-46 migration gating | Review required with automatic downloads enabled; no staging or replacement on ordinary quit |
| Independent privacy baseline | A fresh LaunchServices app had Accessibility and Screen Recording both denied |
| Authorized real Sparkle update | Build 100 → 101 on ordinary quit; stayed closed; new LaunchServices process retained both grants and preferences |
| Test permission cleanup | Only the test app's entries removed; a fresh process confirmed both grants denied again |
| Old public updater → persistent Alpha signer | Public 0.5.1 code showed the actual migration notes and accepted download / Install and Relaunch; preferences preserved |
| Packaged executable | Its machine-code section matched both tested successors |
| Release integrity | Mounted DMG, symlink-preserving ZIP, original Ed25519 key, 123 corresponding-source hashes and executable hash verified |

The signing transition from old ad-hoc builds can require one-time authorization;
this release does not claim to transfer their hash-bound grants transparently.
Compatible Alpha-to-Alpha grant preservation was verified on this Mac. This is
not validation of older macOS versions, Intel or every third-party menu item.
The native hiding implementation is unchanged from build 46; broader native
acceptance remains the build-45 baseline described below.

## Previous release: 0.5.1 build 46

**Rollout paused on October 26:** the ad-hoc public update invalidated macOS
Accessibility grants on an existing installation. The missing left arrow and
right-arrow Settings fallback were consequences of that permission loss.
Restoring the installation's previous certificate identity on the same 0.5.1
code restored Accessibility, Screen Recording and both controls without new
grants. The feed was returned to build 45 pending the 0.5.2 migration. See
[permission recovery](UPDATES.md#permission-recovery-after-051).

The installer fixtures below verified replacement and application preferences,
not macOS permission preservation: their isolated identities had no privacy
grants. This gap blocks further ad-hoc automatic releases.

**Update safeguards verified on October 26:** the release gate now requires a
previous public app, checks actual designated-requirement compatibility and
rejects silent identity changes. The permanent automatic-update floor is
embedded in the candidate and cannot decrease in a successor. Recovery notes
are required even in later releases, for clients that skip the first migration.
Fifteen real-signature gate cases passed, including the self-signed runtime
incompatibility check. Isolated copies of the published
build-45 and build-46 code both required interactive review with automatic
downloads enabled; neither staged the migration or replaced itself on ordinary
exit, and fixture preferences survived. These checks verify rollout gating,
not TCC grant preservation. Independent authorized acceptance for build 47 is
reported above. Shell-child permission probes inherited the host's grants and
were rejected as acceptance evidence; a LaunchServices launch of the fresh
fixture correctly returned both permissions false.

[0.5.1 Alpha](https://github.com/nggurbanov/Draplet/releases/tag/v0.5.1) fixes the
Pocket disclosure overlapping native system status items such as Sound/AirPods.
Its source tag identifies commit `5f76f076b784bc68e30cf329b6013ed9eacf24bb`.
Validation was performed on macOS 27 / Apple silicon with one physical display.

| Patch check | Result |
| --- | --- |
| Lifecycle, preferences, rendering and animation suite | 380 checks passed |
| AirPods occupancy regression | Failed before the fix, passed after it |
| Live AirPods rendering and placement | Geometry, screenshots and three collapse/expand cycles passed on October 25, before the version bump |
| Release DMG | Checksum, mounted app signature, executable equality and Applications link passed |
| Update ZIP and corresponding source | Symlinks, source hashes, source commit and packaged executable hash matched |
| Update signature | Original Ed25519 key verified; modified bytes rejected |
| Real isolated install-on-quit | Build 100 → 101; preferences preserved; application remained closed |
| Real isolated Update and Relaunch | Build 100 → 101; preferences preserved; new normal process launched |
| Corrupted update / unavailable feed | Errors reported; installed fixture remained build 100 |
| Public artifacts | All five downloads matched local SHA-256 values |

This patch does not claim a new run of the broader build-45 native suites below.
Signing, supported architectures and known alpha limits remain unchanged. The
feed initially advertised build 46 after the public ZIP was verified, and was
subsequently rolled back because of the permission-identity regression.

## Previous release: 0.5.0 build 45

[0.5.0 Alpha](https://github.com/nggurbanov/Draplet/releases/tag/v0.5.0) is the
first public binary release. Its application source is tagged at
`0033828dc0a9f432bb749f89b33956220515c36b`; later main-branch commits maintain
release metadata and documentation. Documentation-only changes do not replace
the published DMG, updater ZIP, source snapshot or tag.

## Verified scope

Validation was performed locally on macOS 27 / Apple silicon with one physical
display. The following results apply to build 45; they are not certification of
all supported systems or third-party status publishers.

| Check | Result |
| --- | --- |
| Lifecycle, preferences, rendering and animation suite | 378 checks passed |
| Broad native fixture harness | 17 scenarios passed |
| Transparent blocker over the real horizontal arrow | 20 paired WindowServer clicks; no blocker clicks |
| Separate publisher's rendered native slot | 10 left and 2 right clicks; intended menu opened, no blocker clicks |
| Held-arrow appearance | Decoded idle/pressed pixels identical; glyph remained visible |
| Compatibility-return fixture | Six stages: real slot/menu, accordion cycles, restart, refresh, re-pin and return |
| Daily native layout | Six expand/collapse checks; input indicator remained right of the disclosure |
| Release DMG | Checksum, mounted app signature, executable equality and Applications link passed |
| Update signature | Ed25519 verified against the embedded public key; modified bytes rejected |
| Real isolated install-on-quit | Build 100 → 101; application remained closed |
| Corrupted update / unavailable feed | Errors reported; installed fixture remained build 100 |
| Public artifacts | All five downloads matched local SHA-256 values |
| Public update feed | Matched the candidate feed advertising build 45 |

The broad native harness covers first-frame masking, rapid reversals, actual
arrow actions, departure auto-hide, leftmost Pocket placement, distinct native
glyphs, return/menu activation, repeated cached opens, restart, fullscreen
suppression and desktop restoration. Native return checks preserve disclosure
position as well as menu activation. Programmatically driven fixture callbacks
and WindowServer input do not establish acceptance of a physical Command drag.

The compatibility fixture isolates initial return using the disposable source's
real glyph, then changes that glyph and checks explicit recapture. Initial
cache seeding is not evidence of cold acquisition. Last-good images and native
actions are checked separately.

## Reproduce checks

```sh
bash test.sh
DRAPLET_SIGNING_IDENTITY='<stable certificate>' \
DRAPLET_SIGNING_PROFILE=alpha \
DRAPLET_PREVIOUS_RELEASE_APP='/path/to/previous-public/Draplet.app' \
  bash scripts/prepare-release.sh
```

Build and packaging require macOS. Release signing additionally needs the
private Ed25519 key, which is never included in Git or the source archive.
For native fixture setup and safe restoration, see
[Pocket QA](POCKET.md#native-qa-harness). The public regression helpers are:

- `scripts/qa-native.py`: controllers, AX/WindowServer geometry, native menus,
  transient blocker input, fullscreen, cache and lifecycle scenarios.
- `scripts/qa-status-input.py`: independent target publisher and foreign
  transparent blocker; optional idle/pressed screenshots.
- `scripts/qa-pocket-compatibility.py`: native compatibility-slot return,
  disclosure-position preservation, persistence and glyph refresh.
- `scripts/qa-render-lifecycle.py`: unchanged drawing/presentation observations,
  Cached/Live stream retirement, repeated toggles and drained normal Quit.
- `scripts/prepare-update-test.py`: isolated good, bad-signature, unavailable-feed
  scheduled-review and legacy-migration updater fixtures. See [UPDATES.md](UPDATES.md).
- `scripts/qa-update-migration.py`: real legacy-client review, no staging and
  no install-on-quit checks against an isolated migration fixture.
- `scripts/qa-release-signing.py`: real-signature policy checks using temporary
  copies and an explicit test certificate.
- `scripts/check-update-permissions.py`: independent native privacy evidence
  with a mandatory denied baseline, authorized predecessor and successor.
- `scripts/measure-resources.py`: bounded CPU/memory sampling; see
  [PERFORMANCE.md](PERFORMANCE.md).

These helpers produce local reports; generated logs, screenshots, caches and
builds are intentionally excluded from Git. Run native suites individually on
an unlocked Mac with their documented permissions. Preserve real pins and
preferences, balance injected input, close disposable processes and restore the
same installed successor after either success or failure.

## Known alpha limits

- Downloads are arm64, target macOS 14.2+, and have current hardware validation
  only on macOS 27. Intel, older macOS and multiple physical displays are untested.
- The native hiding backend uses private, dynamically resolved APIs. Future OS
  updates may affect it; failure leaves status icons accessible.
- Physical Command-drag in both directions, complete keyboard/VoiceOver use and
  arbitrary third-party popovers/fullscreen behavior need broader acceptance.
- Cold first capture can wait for rendering/retries. Prepared cache timings do
  not establish universal no-flash or zero-latency behavior.
- A compatibility return can use a cached real glyph in an owned native slot.
  Changing counters/artwork need Refresh Icons; publisher AX support determines
  custom menu behavior. See [Pocket](POCKET.md).
- Long-running animated wallpapers/icons, GPU/WindowServer attribution, battery
  and long-term memory stability have not been quantified for this release.
  Historical resource comparisons in PERFORMANCE.md are not current benchmarks.
- Version 0.5.2 and later use a persistent self-signed Alpha identity, not Developer ID
  signing or notarization. First launch may require Open Anyway. Test a later signing-identity transition
  separately because macOS can require granting permissions again.

## Release integrity

The release includes a DMG, updater ZIP, SHA-256 file, candidate appcast and
complete corresponding-source archive. The archive contains the application
snapshot, license notices, build scripts and Sparkle 2.10.0 source with its
vendored dependencies. SOURCE-MANIFEST.json records the source commit, file
hashes and packaged executable hash. The production feed was activated only
after the public downloads were verified. Follow [UPDATES.md](UPDATES.md) for
subsequent releases; do not move an existing release tag to a documentation commit.
