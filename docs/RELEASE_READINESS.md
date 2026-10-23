# Alpha release readiness — 0.5.0 (build 45)

Build 45 protects the horizontal arrow and neighbouring rendered status icons
from transparent foreign hit windows, removes the arrow's native press capsule,
and fixes startup classification using an unsettled arrow boundary.
See [Pocket](POCKET.md#ordinary-arrow-input-and-startup-boundary--build-45).
The lifecycle/preference/rendering/animation suite passes **378 checks** in
`/tmp/Draplet-arrow45-tests.log`; the optimized build passes in
`/tmp/Draplet-arrow45-build.log`. Neither fix adds an overlay window or a
continuous capture stream.

The isolated native blocker reproduces the stolen click before the fix, both
on the arrow and on a separate publisher's rendered native slot.
`.build/arrow45/native-full/results.json` adds a regression of 20 paired
WindowServer clicks to the broader native harness. The input is restricted to
the disposable fixture; it does not establish physical Command-drag acceptance.
Current restoration evidence is recorded under `.build/arrow45/`.
The two-publisher input regression is `scripts/qa-status-input.py`; its source
publisher's menu delegate establishes actual opening rather than relying on an
Accessibility success code. Ten left clicks and two right clicks pass in
`.build/arrow45/target-final/results.json`, with zero foreign blocker clicks.
The actual held-arrow screenshots are compared as decoded pixels, including
verification that the glyph remains present. The native return regressions now
also assert the user's disclosure position before/after the move; menu opening
alone was insufficient to establish a correct placement.

Native return keeps Command through release, refreshes its drop target after
pulling the source out, and restores the owned disclosure beside its original
neighbour after assessment-mode reflow. It never writes another publisher's
preferences or the private global status-position table. A pending synthetic
mouse-down is balanced during cancellation and quit. Section persistence uses
verified hosted rectangles rather than stale compatibility backing windows.
Under the expanded native restriction, an extra which cannot fit returns via
that owned native slot, avoiding synthetic drags on foreign menu buttons. Its
real application still handles the action. As with the existing compatibility
fallback, the glyph is cached and changing counters/artwork need Refresh Icons.

`HostedMenuBarInventory` reconciles visible publisher geometry with the same
native host that supplies the owned arrow. Missing verified geometry fails
open. The actual app's normal startup and language-indicator checks are recorded
under `.build/arrow45/normal-startup.json` and `daily-final.json`.

The final scoped native reports are `.build/arrow45/native-full/results.json`
(17 scenarios, including 20 WindowServer arrow clicks),
`.build/arrow45/target-final/results.json` (12 clicks over a different native
publisher) and `.build/arrow45/compatibility-final-verified/` (six compatibility
stages with the disclosure-position invariant). Final install/cleanup readback
is `.build/arrow45/verification45.json`. These remain local alpha checks, not a
public release or hardware acceptance of every publisher's custom UI.

## Build-45 release packaging

On 2026-10-23, the 378-check suite passed again and the ad-hoc alpha was
rebuilt with `scripts/prepare-release.sh`. The mounted DMG passed checksum,
strict signature, executable equality and Applications-link verification.
The updater ZIP's Ed25519 signature was independently verified using the public
key embedded in Info.plist; the same signature rejected modified bytes.
The candidate appcast advertises build 45, arm64 and macOS 14.2 minimum.

An isolated copy of this app's complete binary updated build 100 to 101 via
Sparkle's real installer on ordinary quit and remained closed. A separate
modified-archive fixture failed signature verification before extraction and
remained build 100. An unavailable-feed fixture reported a network error and
also retained build 100. These fixtures do not run the menu-bar engines or change the
daily app. This is local installer evidence, not delivery from the public feed.

The release exporter includes the exact application source snapshot, license
notices, build scripts and Sparkle 2.10.0 source with vendored dependencies.
SOURCE-MANIFEST.json identifies the packaged executable and per-file hashes.
Release publication and feed activation are separate actions; the historical
GitHub draft must be replaced before it can represent this candidate.

## Predecessor build-44 scope

Build 44 adds the native-filter compatibility return described in
[Pocket](POCKET.md#native-filter-compatibility-return--build-44). An unsupported
publisher can return using an owned native status slot, its cached real glyph
and its original Accessibility menu action, without moving the application.
Cached glyphs are refreshed explicitly; live counters and arbitrary custom
popups are not universally replicated. No continuous capture stream is added.

The predecessor lifecycle/preference/rendering/animation suite passes **346 checks**
in `/tmp/Draplet-compat44-final-tests.log`. The optimized app build and deep
strict signing check pass in `/tmp/Draplet-compat44-final-build.log`.
Compatibility/native integration evidence is recorded below. Final restoration
is verified in `.build/compat44/verification44.json`: matching installed/built
executable hashes, verified signing, a normal launch without test flags, all six
real pins preserved and no QA helpers or compatibility fixture keys left behind.
No public release or update-feed publication is part of this local change.

The build-36/37 cache and motion timings below remain predecessor evidence.
Build 33's finish verdict is historical and does not accept newer behavior.

## Build-44 native evidence

`.build/compat44/final-optimized/` exercises the unchanged disposable publisher
in `~/Applications`. The original is absent under the restriction while one
owned native slot is physically rendered. The real publisher's menu opens;
three accordion cycles, process restart, explicit refresh after changing the
publisher's glyph, re-pinning and a one-operation pinned return all pass.
`refreshed.png` contains the newly captured glyph, not the seeded initial image.
The actual hosted accordion arrow retains its position before/after return.
The test's cache seeding isolates initial return from unrelated image capture;
only the later refresh proves acquisition of changed source pixels.

All **16 broad native scenarios** pass in
`.build/compat44/native-full/results.json`, including first-frame overflow coverage, 40 rapid
reversals, 40 real control actions, five-second departure auto-hide, eight
distinct pinned glyphs, native menu activation, repeated cached Pocket opens,
restart, native fullscreen suppression and desktop restoration. Its fresh
process open can use the disk cache; it is not a cold-image-capture benchmark.
Exact duplicate AX overflow rectangles are consolidated by the independent
test observer; distinct physical positions still fail its geometry assertion.

Physical held-Command gestures, arbitrary custom publisher panels, Intel and
older macOS, multiple physical displays and long-term resource measurements
remain outside this local pass. Local owned-fixture controller/event checks do
not replace those hardware acceptance scenarios.

## Current behavior

- The original horizontal arrow retains native accordion reveal. Pocket's
  down/up chevron appears only while the strip is expanded and is always leftmost,
  before every visible right status icon. Native overflow supplies its leading
  slot; a fitting pins-only layout uses verified empty space before the first
  physical slot. Collapse hides it immediately, and late scans cannot restore it.
  Only a rendered physical-slot snapshot can establish that space.
  Saved pins remain accessible after expanding the original arrow. With neither
  overflow nor eligible running pins, no Pocket control is shown.
  With Curtain selected, Pocket and the icons reveal together under the existing
  mirrored right curtain, with the same progress and selected pace. No isolated
  early chevron or all-at-once replacement is accepted.
- Automatic overflow resolves exact item identities, including nonfitting
  siblings. An unreadable host creates no automatic membership; explicit pins
  remain separate. Deliberate pins persist by bundle identifier; the macOS 27 native
  backend moves all status icons from a pinned app together. Settings and item
  menus expose Keep in Pocket / Return to Menu Bar.
  Individually hosted items such as Spotlight require a verified distinct owner;
  shared system controls and input agents remain excluded.
- Command-drag into Pocket and back to the native menu bar is implemented with
  Command/session/target guards and cancellation. Ordinary click invokes the
  real status-item action. Policy tests do not constitute physical drag acceptance.
  The transient genuine-drag drop target can open independently of normal strip
  expansion; it is not a persistent idle control.
- A compact native `NSPopover` retains real status imagery at its native logical
  size. Last-good native glyphs remain clickable after refresh failure; app
  artwork is never substituted. Explicit Control Center `isAllowed=false` items
  are excluded from capture while their pins stay saved. The inspected live
  Vorssaint entry has this flag; it does not prove universal incompatibility.
- The bar, chevron and popover retain reveal together. Native menus, captures,
  actions, transitions and drags also hold it. Departure begins the full
  configured delay, five seconds by default; re-entry resets it.
- The persistent local native-glyph cache is bounded to 128 records. Images are
  eligible for idle refresh after a soft 120 seconds; failures back off for
  30/120/600/3600 seconds while prior pixels remain usable. Display changes retain
  them, and normal quit drains writes.
- Collapsed idle prewarming uses a matched prefix shield ending before the
  original arrow/system controls and preserves visible native capacity. A new
  glyph can still require first foreground capture if hidden capacity is
  insufficient. Staging restores native visibility and never writes positions.
- A matching verified prepared layout skips the repeated 300 ms warm settling
  delay. Native activation is still awaited; cold preparation remains intact.

## Historical build-38 validation note

Candidate 38 retained native glyph persistence, idle prewarming and warm-reveal
preparation changes; its native validation and final restoration were pending
at that point. Build-37 motion was not accepted.

The following cache evidence belongs to predecessor build 37, not current
acceptance.

`/tmp/Draplet-latency37-tests.log` records **308 passing checks** and
`/tmp/Draplet-latency37-build.log` records native build/signing success.
`.build/responsive37/checks.json` passes idle prewarm, eight real fixture glyphs
(ten images including Shottr/Spotify), four cached opens at 32–38 ms without
recapture, last-good retention after an injected failure, and a fresh-process
disk-cache open at 68 ms with ten disk hits/images and zero capture requests.
The first prepared open took 53 ms. These prepared-image timings do not measure
first capture of a new glyph.

Its dark/light 130 × 168-point captures and actual CUA button open/close passed.
The matched prefix shield ends at the original arrow's x=1197 boundary, leaving
it and system controls available; one arrow action interrupts prewarming.
An in-process display-change notification preserves all ten images and working
native collapse. Physical display changes remain outside this evidence.
Current build-38 warm-pixel timing, bounded native backoff and final normal-launch
restoration are still pending. No instant-response, zero-cold-wait or complete
build-38 acceptance claim is made.

Predecessor `.build/native-motion36-results.json` records two warm first-ink
measurements of 183 and 188 ms. Build-36 cached opens took 32–43 ms, while the
first capture of missing native siblings still took about 4.1 seconds. This is
bounded predecessor evidence, not current build-38 acceptance.

## Historical build-33 local evidence

The finish review in `.build/impeccable-finish33.md` accepted the earlier narrow
local Pocket/right-reveal refinement, with no material fixes. These artifacts
predate the persistent cache and warm-path changes.

- `/tmp/Draplet-pocket33-tests.log` records **290 passing checks**.
  `/tmp/Draplet-pocket33-build.log` records the native build/signing pass.
- All seven historical PNGs and state metadata under `.build/native-capture33/` are valid.
  They cover collapsed saved pins, expanded overflow, pins-only placement,
  dark/light Pocket, the Spotlight target and its pinned magnifier. That build's
  `checks.json` passes stable placement, four interrupted-reveal cancellations,
  actual native overflow replacement, eight real 15.5 × 33-point glyphs and
  Spotlight capture. Native material and the 130 × 168-point grid match the
  incumbent design. Vorssaint appeared as a warning in that build; the current
  inventory honors its explicit Control Center disallowance instead.
- `.build/native-capture33/cold-no-recorder.json` verifies **cold placement
  without recording**: the first published control remains at x=989. Whole
  native preparation plus reveal took about **1.60 seconds cold** and
  **0.75 seconds warm**. Native pin visibility must converge before final
  geometry is accepted; bounded waits fail open. This is status/geometry evidence,
  not cold pixel-motion acceptance.
- `.build/native-motion33-results.json` verifies **two warm pixel recordings**.
  The 25 and 27 closed-preparation frames contain no early glyph ink; both
  reveals have five distinct partial levels. The chevron shares the curtain
  mask and occupied-region progress. Quick remains 180 ms reveal / 160 ms hide;
  native preparation adds time before that animation.
- Predecessor `.build/native-qa-build28/results.json` completed **seven of
  fourteen broader native scenarios**, including four independent first-frame
  placements, forty direct reversals, forty actual arrow actions and departure
  auto-hide. No complete current fourteen-scenario pass is claimed.
  `.build/spotlight25/results.json` separately covers actual Spotlight source
  resolution, target, native hiding/capture and return; physical held-Command
  gestures remain unverified.
- Actual CUA Show → popover → Hide clicks are recorded for build 32 in
  `.build/native-capture32/actual-click-states.json`. The relevant hierarchy and
  open/close source are unchanged in 33. This used a QA-held setup. Holding
  requires both `--test-controls` and `--qa-hold-pocket`; normal launches remain
  transient, and system presentation still cancels the held surface. Held
  appearance captures do not establish normal dismissal or auto-hide.
- `.build/native-restoration33.json` confirms installed 0.5.0 (33), matching
  built/installed executable hashes, verified signing and a normal launch with
  no test flags. The two real pins are unchanged; only Sparkle's last-check
  timestamp differs from the preference snapshot. The fixture was unregistered
  and retired under ignored `.build` storage; no QA helpers remained. Cleanup
  restored the same installed successor, without an obsolete build-15 rollback.

## Historical build-21 resource sample

`.build/resources-build21-idle.json` records a **20.23-second Cached idle** sample
with Settings and Pocket closed: **0.49% of one CPU core** and **75.3–75.7 MiB
RSS**. A separate `sample` report in `.build/resources-build21.sample` records a
**14.8M physical footprint**, with the same peak. RSS and physical footprint are
different measurements. These are historical short diagnostics, not current
build-38 profiling, a controlled energy benchmark or proof of long-term leak
freedom. GPU, WindowServer attribution and battery use were not measured.

## Remaining limits

Physical Command-drag in either direction remains unverified. CUA rejected a
pure modifier key press (`keyPressIncludedNoNonModifierKeys`), so no
held-Command hardware gesture was synthesized. Full keyboard/VoiceOver, fresh
Mission Control and Fladder/Minecraft, macOS 14.2–26, Intel, multiple physical
displays, long-running animated icons, GPU/WindowServer cost, battery and
long-term memory stability remain outside this pass. A virtual Sill display
was present; only the actual physical host supplies glyph-slot evidence.
A disposable native fullscreen fixture does not establish another app's
fullscreen regression.

Cold placement and two warm pixel recordings do not establish cold pixel motion,
universal no-flash behavior or zero-latency capture. The earlier build-25 cold
image load took 6.72 seconds. Current mounted-DMG and updater delivery have not
been repeated. No public successor binary or feed publication is claimed.
GPL v3 corresponding source and license resources must match any exact binary
before distribution; see [UPDATES.md](UPDATES.md).

The public native harness and reproducible fixture app-bundle instructions are
in [Pocket QA](POCKET.md#native-qa-harness). QA must end by reopening the same
installed successor normally.

## Historical build-13 stability and release evidence

Everything below predates Pocket. The updater and mounted-DMG checks have not
been rerun for the current Pocket successor.

### Fixed during the stability pass

- Invalid stored shortcut indices no longer crash startup; invalid values disable the shortcut.
- A completely empty Accessibility menu inventory leaves status icons visible instead of hiding every third-party application.
- Capture/setup requirements follow the enabled features and Accessibility permission. Native right-side Hidden Bar mode alone does not require background capture.
- Transient background failures retry twice (0.5 s, then 1.5 s), with stale callbacks cancelled on stop/reconfiguration. An incomplete initial capture times out rather than leaving Setup spinning indefinitely. Settings shows the actual failure detail.
- Scheduled updates remain prominent when background downloads are disabled: a persistent Settings action and a deferrable reminder lead to Sparkle's download/install flow.
- Permission polling runs asynchronously, at most once per second, with one request in flight. Display geometry and Dock identity are cached until invalidated; unchanged left indicator metadata is not repeatedly assigned.
- Release and updater-test signing use the same identity throughout the Sparkle helper graph. Repeated updater fixtures use separate bundle identifiers and refuse to overwrite running copies.

### Verified

- 168 lifecycle, preference, rendering, animation, permission-monitor, retry-policy and updater-selector checks passed; native build and deep strict code-signature verification passed.
- Regression tests first reproduced the invalid shortcut, empty inventory and permission-policy failures before their fixes.
- In the preceding build-12 updater audit, real isolated signed-archive build 100 → 101 installation worked, including normal-quit installation without relaunch, explicit immediate relaunch and preserved preferences. Corrupt archive and unavailable-feed failure paths were exercised.
- In that updater audit, with automatic downloads disabled, a scheduled update showed the custom reminder, persisted a one-hour deferral, remained actionable in Settings and completed the actual Sparkle download/install/relaunch path. This fixture used an entirely ad-hoc-signed helper graph.
- An injected interruption through the real capture failure handler recovered in the same process. Live mode streamed; Cached mode returned to ready with streaming stopped.
- Final build 13 suppressed its title, hit target and covers in a disposable native fullscreen window and restored them on return. Window metadata also recorded cover removal during Mission Control. Earlier native tests covered the same entry/exit paths before the metadata cache change.
- Build-13 native Settings captures cover Appearance in light/dark. Closing/recreating Settings preserved Right navigation and correctly removed/restored the Dock icon. Earlier General/Shortcuts/Left and updater ready/error captures remain historical evidence.
- The DMG checksum, mounted application signature/executable and real Applications shortcut passed packaging verification. The updater candidate feed is separately Ed25519 signed.

### Limits before broader beta claims

- This is Apple-silicon hardware on macOS 27. Intel, macOS 14.2–26, multiple physical displays, sleep/wake and repeated slow gesture reversal still need a hardware matrix. Legacy systems use the divider layout described in README.
- Fullscreen acceptance here uses a disposable AppKit host; it does not replace another user acceptance run in Fladder/Minecraft after this revision.
- The original spontaneous background interruption's cause was not proven; automatic recovery was verified by fault injection.
- Resource profiling and repeatable measurement instructions are in [PERFORMANCE.md](PERFORMANCE.md). GPU utilization, WindowServer attribution, battery life and long-term memory stability were not quantified. A Live sample on the current opaque menu-bar background is not an animated-wallpaper worst-case benchmark.
- The empty-inventory fix does not prove every partially missing AX inventory safe. macOS system-owned icon and per-application grouping limits remain.
- Public alpha artifacts are ad-hoc signed, not Developer ID signed or notarized; initial Gatekeeper approval may still be required.

### Build-13 resource pass

The repaint regression first failed against WindowServer-rounded indicator coordinates and passed after normalization/unchanged-layout suppression. Shared window discovery, foreground KVO/scalar caching, one shared 20 Hz pointer/presentation tick and a bounded frame-delivery gate retain the fast system-presentation path. Native scanline reconstruction fell from about 2.66 to 0.34 ms/frame in a synthetic 2940×66 benchmark, with equal signatures.

Sequential same-Mac process samples before the final timer consolidation measured build 12 at 7.287% of one core / 44.99 MiB footprint, and build 13 at 1.999% / 22.99 MiB before opening Settings (20 seconds each, 5-second warm-up). The current Live/opaque-background sample was 2.347% / 24.49 MiB; it published only one changed desktop frame. Native fullscreen measured 0.476% over five seconds. These are short diagnostics on a Mac in use, with possible foreground/window/layout differences, not a controlled energy benchmark.

After real Settings use, the new process retained 52–55 MiB and reached about 138 MiB lifetime peak: AppKit/SwiftUI caches remain after hosting views/windows are released. The cold-start improvement must not be presented as a universal halving of RAM or proof that leaks cannot occur.

Final shared-clock build-13 follow-up: a 20-second Cached sample (three-second warm-up) measured 2.449% of one core, 24.19 MiB footprint and 2.95 package-idle wakeups/s. The earlier build-12 reference measured 7.287%, 44.99 MiB and 6.15 wakeups/s. Wakeups vary with scheduling/system activity; this does not establish battery savings. Final native entry/exit and Mission Control entry/exit removed all covers, restored them after fresh background and preserved left auto-hide. Capture-failure injection recovered with the shared clock, and pause stopped capture/overlays.

A final shared-clock Live/opaque-background sample measured 2.757% CPU and 26.13 MiB over 10.005 seconds; changed animated-wallpaper throughput and GPU utilization remain unmeasured.
