# Alpha release validation — 0.5.1 build 46

**Rollout paused on October 26:** the ad-hoc public update invalidated macOS
Accessibility grants on an existing installation. The missing left arrow and
right-arrow Settings fallback were consequences of that permission loss.
Restoring the installation's previous certificate identity on the same 0.5.1
code restored Accessibility, Screen Recording and both controls without new
grants. The feed has been returned to build 45. See
[permission recovery](UPDATES.md#permission-recovery-after-051).

The installer fixtures below verified replacement and application preferences,
not macOS permission preservation: their isolated identities had no privacy
grants. This gap blocks further ad-hoc automatic releases.

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
DRAPLET_SIGNING_IDENTITY=- bash build.sh
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
- `scripts/prepare-update-test.py`: isolated good, bad-signature, unavailable-feed
  and scheduled-review updater fixtures. See [UPDATES.md](UPDATES.md).
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
- Alpha builds are ad-hoc signed, not Developer ID signed or notarized. First
  launch may require Open Anyway. Test any later signing-identity transition
  separately because macOS can require granting permissions again.

## Release integrity

The release includes a DMG, updater ZIP, SHA-256 file, candidate appcast and
complete corresponding-source archive. The archive contains the application
snapshot, license notices, build scripts and Sparkle 2.10.0 source with its
vendored dependencies. SOURCE-MANIFEST.json records the source commit, file
hashes and packaged executable hash. The production feed was activated only
after the public downloads were verified. Follow [UPDATES.md](UPDATES.md) for
subsequent releases; do not move an existing release tag to a documentation commit.
