# Pocket (alpha)

## Ordinary-arrow input and startup boundary — build 45

This fixes the horizontal native arrow, clicks on neighbouring publishers, and
the startup section map.
A foreign transparent status hit window can remain above MenuBarAgent after
its publisher is hidden. Raising an `NSStatusItem` backing window does not
produce a real owned WindowServer window on this host. A narrow event router
instead claims balanced ordinary clicks inside Draplet's independently
identified native slot. That also avoids the system's pressed gray capsule,
which the native host continues to draw despite empty button-cell highlight
masks. Right-click and Option-click retain Draplet's existing actions.

For other rendered status slots the router acts only when a different managed
publisher's small level-26–29 hit window is frontmost at that point. It retains
the target from mouse-down and revalidates the same publisher, AX element and
rectangle before invoking its actual hosted Accessibility action. It never
falls back to an unscoped coordinate click. A publisher's own hit surface,
Pocket's frontmost control and higher popups retain their input. Ordinary
unobstructed icons, native Command drags and tagged placement keep their native
delivery. Releasing outside, changing identity/geometry, losing the slot or
changing Command cancels a claimed action. Standard menu-only extras expose
AXPress for both buttons; a distinct AXShowMenu action is preferred when offered.

The router creates no overlay window and adds no capture stream. It uses the
shared window-metadata snapshot and a bounded asynchronous native-slot read;
no Accessibility walk occurs in the event tap. It stops with disabled/paused
right management and cannot act while system presentation suppresses the bar.
Command changes invalidate its native geometry before another click.

Startup classification formerly remembered the arrow before the asynchronous
publisher walk, while native status hosting was still rearranging it. This
could hide TextInputMenuAgent even though its visible slot was right of the
arrow. Both the controller's backing window and publisher AX backing positions
can lag the actual native host. `HostedMenuBarInventory` replaces rendered
publishers' positions from one MenuBarAgent snapshot and publishes its owned
arrow before completing the inventory callback. Unrendered overflow keeps its
existing source metadata. The production engine uses the controller's verified
boundary provider and fails open while that geometry is unavailable. The
regressions first fail against the old paths; no language publisher is hardcoded
always-visible.

The native fixture's `block-arrow` creates a disposable transparent hit window
above the actual horizontal arrow. Its `click-arrow` posts a paired mouse click
only at that owned fixture window, through WindowServer; AXPress would bypass
the bug. The baseline records a stolen click with the strip still expanded.
The repaired controller opens/closes the strip while the blocker receives zero
clicks. This is injected native input evidence, not a hardware gesture claim.

`scripts/qa-status-input.py` adds a second native publisher. The blocker's real
WindowServer window covers that other process's rendered status slot. Before
the fix the blocker receives the click and the intended menu never opens.
Afterward ten left clicks and two right clicks open the intended publisher's
real menu, observed by its menu delegate, with zero blocker clicks. Optional
static screenshots compare Draplet's actual arrow at rest and while held;
they are not a continuous runtime capture feature.

The return regressions additionally preserve the native horizontal arrow's
position. Native capture temporarily compresses the bar, and its restored
geometry can differ from the staged drop geometry. Return remembers the
disclosure's adjacent publisher, keeps Command through the HID mouse-up and
refreshes its target while dragging. It restores only Draplet's own disclosure
relative to that neighbour after the normal layout returns. No private global
position table or foreign application preferences are written. Successful
compatible return requires a physical hidden-side slot, not just an on-screen
rectangle. Pending synthetic mouse-up is retained for cancellation/quit.

When the expanded bar is restricted and a returned extra has no usable native
slot, return uses this same owned-slot fallback directly. Only Draplet's own
status item is dragged; foreign menu buttons are invoked only for their real
actions. A fitting original item still returns by ordinary unpinning. The
fallback uses the existing last-good native glyph cache, so changing counters
or artwork need **Refresh Icons**; it is not a live visual replica. If the
original later becomes physically renderable, the redundant slot is removed.

Compatibility section persistence uses fresh native-host geometry and retains
the previous section when that geometry is missing. It never falls back to the
old backing-window insertion position. A genuine Command change invalidates
those observations; subsequent hosted reads refresh both the arrow and mirrors.
The independent compatibility observer waits for MenuBarAgent to publish the
visibility change after `NSStatusItem.isVisible` changes; a transient stale AX
row is not by itself evidence of surviving pixels.

## Native-filter compatibility return — build 44

On the tested macOS 27 host, the native allow-list failed to expose a real
publisher launched from `~/Applications`; the same unchanged publisher worked
from `/Applications`. Registering it again, path/identifier aliases and an
`/Applications` directory symlink did not resolve the former case. Draplet now
has a return fallback that does not move or modify the publisher.

After a Pocket return, Draplet first tries the original native status item. If
it cannot remain rendered under the restored restriction, an unrestricted
staging pass must prove that the original is actually available. Only then can
Draplet create its own `NSStatusItem` using the source's last-good native glyph.
Clicking that control invokes the original publisher's Accessibility action,
not a reconstructed application menu. The compatibility slot follows the
accordion, can be pinned back to Pocket and restores from its stable saved
identity after restarting Draplet. A pinned unsupported publisher completes
unpinning and compatible return in one operation.

Success requires independent native-host evidence after visibility restoration.
Owned PID plus unique AX identifier joins the physical slot to the source;
bounded 4-point hit-padding overlap is allowed only for those owned controls.
Parked or substantially overlapping slots remain unrendered. If the original
later becomes renderable under the restriction, the redundant slot is removed.
Incoming Command-drag uses a fresh host read rather than a cached click point.
The arrow's actual hosted frame is refreshed by the existing inventory scan.
Every native return also waits for its actual hosted arrow after temporary
staging. The backing `NSStatusItem` window can report a different position at
that moment, so it cannot define the drop target. The move targets the arrow's
leading half, and its tagged release cannot trigger an accidental toggle.

This is a cached visual substitute, not a universal live replica. Animated
glyphs and changing counters need **Refresh Icons** in the horizontal arrow's
context menu. That action reuses the bounded one-shot native capture path and
retains the last-good image if capture fails. No new continuous screen-capture
stream is added. Custom per-app popup and right-click behavior still depends
on the original application's Accessibility implementation.

`scripts/qa-pocket-compatibility.py` runs a single real publisher outside
`/Applications` through the actual Pocket cell/controller and production native
move. Its independent observer checks the hosted slot, and the publisher's menu
delegate confirms a real menu opened. The test seeds only that disposable
publisher's image from its real status button to isolate initial return; it
then changes the published glyph and verifies an explicit screenshot refresh.
It also checks three accordion cycles, restart persistence, re-pinning and a
one-operation pinned return. Real pins and the fixture's previous cache records
are preserved, and the installed app is relaunched normally. This is local
native integration evidence, not acceptance of a hardware Command-drag gesture
or every third-party publisher.

## No-loss membership correction — build 43

The width estimate and absence of the system overflow button no longer prove
that every eligible publisher is visible. On the actual daily scene, after all
QA publishers were removed, TypeWhisper and Telegram were rendered in the strip,
but MenuBarSpotify was absent under the native restriction despite spare room.
Pausing Draplet made it reappear; resuming the restriction removed it again.
Build 42's capacity guard then omitted it from Pocket as well.

Membership now keeps every eligible, unrendered candidate reachable in Pocket
after a valid settled expanded-host read. Already rendered items remain out of
Pocket, and a collapsed or unreadable host still cannot classify membership.
Explicit pins, macOS-disallowed publishers and always-hidden exclusions retain
their existing separate handling. This restores access; it does not claim that
macOS's allow-list compatibility with MenuBarSpotify has been repaired.

`.build/membership43/verification43.json` records the no-fixture daily-app check:
Crisp, Shottr, Spotlight and MenuBarSpotify are all reachable, Spotify has a real
cached glyph, saved pins are unchanged, and no capture stream or shield remains.
The actual Pocket AX tree exposes all four cells; the native window screenshot
also shows Spotify's glyph. `/tmp/Draplet-membership43-tests.log` records 337
passing checks, including the spare-capacity/unrendered-publisher regression.

## Return and drop-position correction — build 42

The pin destination anchors to the actual Command mouse-down point, including
its original display. It no longer spawns at a fixed offset beside the notch
or follows a later pointer location during asynchronous source discovery.

All Pocket cells offer the local return region. Explicitly pinned publishers
retain their existing unpin path. Automatic overflow instead borrows a native
exposure behind a one-shot menu-bar snapshot, waits for a fresh stable rendered
frame, and completes a native Command status-item move to the nearest slot
before the accordion arrow. The production events are tagged so the incoming
pin detector cannot mistake them for a new drag into Pocket. Every down is
paired with up, and cursor restoration respects intervening pointer movement.

Success requires the icon to remain genuinely rendered after the original
visibility policy restores. The temporary shield passes the owned native move
through and closes on the main actor. A delayed notification from explicitly
closing the source popover must not cancel the return task. This uses a bounded
one-shot snapshot, not a new continuous capture stream. It does not write the
macOS preferred-position table or add an external binary dependency.

The isolated native fixture check in `.build/return42/result.json` has exercised
an unpinned automatic-overflow cell through the actual SwiftUI control and the
production native move, independently reading the host's rendered frame. It
preserved all real pins and observed no Mission Control, no remaining shield
and no streaming capture. Hardware acceptance of the final build is separate.
`/tmp/Draplet-return42-tests.log` records 336 checks, including source-relative
anchor geometry on primary and negative-coordinate secondary displays.

## Current drag refinement — build 41

The Pocket-to-Pocket and Pocket-to-menu-bar gestures are now process-local.
The source control handles Command mouse-down, movement, release, Escape and
modifier cancellation directly; a passive image follows the pointer. No system
`NSDraggingSession` is started for this path. Return regions are passive windows
that cannot intercept the source's release; the exact current token, location
and Command state are checked on release. Genuine native status-item drags into
Pocket keep their existing separate path.

The user confirmed build 40 starts the physical drag, but reported Mission
Control appearing when moving upward; return acceptance was therefore not met.
Build 41's local path addresses that conflict without changing global Dock,
Mission Control, hot-corner or trackpad settings. The user confirmed Mission
Control no longer appears. The next two diagnostic gestures
both delivered Command mouse-up at correct menu-bar coordinates; both sources
were unpinned automatic-overflow items, so no return region existed and neither
changed saved placement. This does not establish hardware acceptance for an
explicitly pinned source. `/tmp/Draplet-drag41-tests.log` records 333 checks,
including actual control callbacks, no system-drag source, passive return-region
validation and persistent grid ordering. The signed native build passed in
`/tmp/Draplet-drag41-build.log`.

The subsequent process-local native integration check in
`.build/return41/result.json` drives an actual SwiftUI-backed fixture cell across
a run-loop turn through the complete return callback. It successfully removes
only `org.drapletqa.native` from saved pins, preserving every real pin. The same
fixture-only path is included in `scripts/qa-native.py`; it does not synthesize
global hardware input and cannot substitute for physical drag acceptance.

## Current drag refinement — build 40

Build 40 separates Command gesture handling into the actual AppKit control's
`mouseDown`, `mouseDragged` and `mouseUp` callbacks, registers Pocket cells as
local drag destinations, and saves order by stable native-item identity.
Ordinary clicks retain native menu actions. Releasing Command before the drop
or dropping outside the valid targets leaves placement unchanged.

Crisp retains a transparent menu-bar hit window at level 26. The Pocket button
now stays at the curtain's level during animation and rises to level 27 only
when unmasked, so that transparent window cannot steal its clicks. The small
return destination uses the same interactive level during an active drag.

`/tmp/Draplet-drag40-tests.log` records 327 passing checks, including real
AppKit control callbacks up to the native-session boundary, admission,
cancellation, saved cell ordering and masked/unmasked window ownership.
`/tmp/Draplet-drag40-build.log` records a successful build/signing pass.
The physical Command-drag path is awaiting the current live check; these tests
alone do not constitute hardware acceptance. Earlier capture/animation evidence
below remains scoped to the build that produced it.

Enable **Settings → Right → Use Pocket**. The original horizontal right arrow
retains native accordion reveal, including click, hover, Option-click and the
shortcut. Pocket's separate down-chevron becomes an up-chevron while open. This
control appears **only while the right strip is expanded** and sits **leftmost,
before every visible right status icon**. With native overflow it replaces that
leading slot. When only pinned apps need Pocket and the native bar fits, it uses
verified empty space before the first physical status slot. Collapsing hides it
immediately; late scans cannot restore it. Saved pins remain available after
expanding the original horizontal arrow. With neither overflow nor eligible running pinned
items, the control is absent. It does not reserve a permanent half-control beside
the original arrow.

With Curtain selected, the chevron and right status icons reveal together under
the existing mirrored right curtain at the user's selected pace. Both follow the
same reveal progress; an isolated early chevron followed by all icons appearing
at once is a regression, not a replacement animation. Other animation choices
remain available. Collapse still hides the Pocket control immediately.

Automatic overflow contains only the exact nonfitting status items, including
individual siblings from the same app. Known always-hidden applications are
excluded unless that section is explicitly revealed. New status applications
are discovered without restarting Draplet.

## Placement and gestures

- **Keep in Pocket / Return to Menu Bar** is available in Right settings and
  each item's context menu. Saved pins use bundle identifiers, survive app/PID
  changes and appear in Settings even when an app is not running.
- Hold **⌘** while dragging a real native status icon into Pocket's highlighted
  target to pin its app. This transient genuine-drag target can open independently
  of strip expansion, even when Pocket is empty; it is not an idle button.
  Its label names the actual dragged status item, such as Spotlight.
- Hold **⌘** from mouse-down through the drop while dragging a pinned Pocket icon
  onto the right menu-bar area to return its app. Escape, an outside drop or a
  released Command key leaves the pin intact. Unrelated drags are not accepted.
- Hold **⌘** and drag within Pocket to rearrange its cells. A small insertion
  marker shows whether the item will land before or after the target cell.
  This order persists across restarts and does not rearrange the physical menu
  bar. Automatic-overflow cells can be rearranged too; returning to the physical
  bar removes an explicit pin and remains subject to available native space.
- An ordinary click invokes the actual status-item action or menu. Right-click
  offers **Open Application Menu** and the placement action.

The macOS 27 native backend hides by application: all status icons from one
pinned app move together. Removing a pin restores that app's original native
section; an item that still does not fit can remain in automatic overflow. Shared
system controls and input agents cannot be pinned. Individually hosted items such
as Spotlight require a verified distinct owner. Placement requires the available macOS 27 native
hiding backend; saved pins can still be removed when it is unavailable.

Command-drag is implemented in both directions; both still need physical
acceptance. Automated source/policy checks cover guards and cancellation;
they do not establish that macOS completes every hardware drag correctly.

## Native surface and retention

Pocket is a downward-opening native `NSPopover` with a top pointer, native
translucency, border and shadow. Its icon-only grid has a 34-point minimum cell
width and 34-point cell height, 4-point gaps and 10-point content insets. It uses
up to three columns and five visible rows before scrolling. Wide status imagery
can span columns; native logical image size and Retina resolution are preserved.
Monochrome glyphs follow the native appearance tint; colored status imagery keeps
its original colors.
Names live in tooltips and accessibility labels. There is no title toolbar,
permanent caption or footer. A last-good native image stays visible and clickable
if refresh fails. Items without a usable glyph can show a loading/unavailable
state or be omitted after capture failure; application artwork is never a
status-image replacement. Explicit macOS Control Center `isAllowed=false` items
are excluded from inventory/capture while their pins remain saved. The inspected
live Vorssaint entry has that flag; this is not universal app incompatibility.
Right-click the Pocket chevron for **Refresh Icon Images** or **Arrange Icons…**.

The expanded right strip, chevron and popover share pointer retention. Native
menus, capture/action work, drags and transitions also hold reveal. Leaving all
of them starts the full configured auto-hide delay, five seconds by default;
re-entry resets it. The left curtain uses the same delay and retains reveal
during right-side interaction. Explicit collapse immediately hides the Pocket
chevron and closes the popover before the native bar. Escape,
an outside click, Space/display changes, unrelated application activation,
pause and fullscreen/system presentation suppression dismiss it.

## Capture, permissions and native actions

Accessibility supplies identities and native actions. On macOS 27, MenuBarAgent
hosts the glyphs. The host must match the actual target display and expose
rendered status-button slots before geometry and owner identities are resolved.
Read layout only after native placement activation is accepted and its geometry
has settled. Matching window bounds alone are insufficient: a parked application catalog can
share those bounds. A verified native overflow slot can anchor the control; a pins-only gap requires
rendered physical slots. Without a readable host, automatic membership is empty
while explicit pins remain separate.
A generic `AXExtrasMenuBar` can
describe another display, including a virtual Sill display; its slots are not
evidence of physical menu-bar glyphs. Ambiguous identity or geometry fails safely.

Screen & System Audio Recording permission is required for real status-image
capture, even when background matching is disabled. Draplet captures no audio.
A one-shot frozen right-bar strip covers temporary per-app native visibility
staging. On the native path, uncached items must be explicitly staged before
capture: stable AX geometry can precede compositor rendering and describe the
neighbour's glyph. Capture waits for the renderer, resolves fresh hosted geometry
and restores visibility afterward without writing icon positions. Capture uses
small cursor-free snapshots rather than a persistent Pocket image stream.

Last-good native glyphs persist locally under
`~/Library/Caches/com.tyrell.Draplet/Pocket-v1/`, bounded to 128 records. Their
120-second age is a soft idle-refresh threshold, not an expiry that removes
pixels. Consecutive failures back off for 30, 120, 600 and then 3600 seconds;
an existing image remains clickable during failed refreshes. Display changes
preserve cached pixels and make them eligible for refresh. **Refresh Icon Images**
requests recapture without first discarding the last-good image. Normal quit
drains pending cache writes.

While the strip is collapsed and idle, prewarming can stage native glyphs behind
a background-matched prefix shield that ends before the original arrow and
system controls. It preserves visible native items rather than forcing extra
capacity. A newly encountered glyph may therefore still need its first
foreground capture when hidden native capacity is insufficient. Dismissal
cancels stale work and restores staging; locked or inactive sessions suppress
capture. Cold first opens can still wait for rendering and retries.

A matching verified prepared layout bypasses the repeated 300 ms warm-reveal
settling delay. Native activation is still awaited; invalidated or cold layouts
retain the full preparation path. Neither caching nor prewarming establishes
instant response, universal first-open timing or absence of capture flashes.

Each cell is a native accessible button. Arrow navigation follows the spanning
grid; Enter or Space invokes the focused item. Primary activation uses AXPress;
**Open Application Menu** tries AXShowMenu. Native mouse routing is allowed only
after a definite unsupported-action result and safe live geometry. A timeout
(`cannotComplete`) has an unknown outcome and is never replayed. Unavailable
actions direct the user to Return to Menu Bar or native section reveal. Settings
remains the only reason to show Draplet in the Dock.

## Current evidence — build 38 pending

Current build-38 validation is pending. Build-37 motion was not accepted;
the following 36/37 cache timings are predecessor evidence only.

Predecessor build 37 passed **308 unit/policy checks** in
`/tmp/Draplet-latency37-tests.log`; native build/signing passes in
`/tmp/Draplet-latency37-build.log`. Focused checks in
`.build/responsive37/checks.json` verify idle prewarming before opening Pocket,
eight distinct fixture glyphs plus Shottr/Spotify, four cached opens at 32–38 ms
without extra captures, failed-refresh retention, and a fresh-process disk-cache
open at 68 ms with ten disk hits/images and no capture request. The first prepared
open took 53 ms; these are prepared-image timings on this Mac, not cold capture.

The matched background prefix shield spans x=824–1197, leaving the original
x=1197–1239 arrow and system controls outside. One original-arrow action
interrupts warming. An in-process display-change notification preserved all ten
images and native collapse continued to work; this is not physical display-change
acceptance. Actual CUA button open/close and current dark/light 130 × 168-point
captures also passed. Current build-38 warm-pixel timing, bounded native backoff
and final normal-launch restoration evidence are still pending.

Predecessor `.build/native-motion36-results.json` measures two warm first-ink
latencies of 183 and 188 ms. Build-36 cached opens measured 32–43 ms, while first
capture of missing native siblings still took about 4.1 seconds. These timings
do not establish current build-38 acceptance or eliminate cold capture waits.

## Historical local evidence — build 33

Build 33 passes **290 unit/policy checks** in
`/tmp/Draplet-pocket33-tests.log`; the build/signing log is
`/tmp/Draplet-pocket33-build.log`. The fresh full finish review in
`.build/impeccable-finish33.md` returned **SHIP for the narrow local refinement**,
with no material fixes. It preserves the incumbent native material, typography
and compact geometry.

All seven historical captures and their state metadata are under
`.build/native-capture33/`: collapsed with pins, expanded overflow, expanded
pins-only, dark/light Pocket, Spotlight target and Spotlight pinned.
`checks.json` verifies stable cold/warm placement, four interrupted reveals
leaving the control hidden, replacement of the independently observed native
overflow footprint, eight real fixture glyphs at 15.5 × 33 points, and the
Spotlight target/magnifier. The compact grid is 130 × 168 points. Shottr and
Spotify retain real imagery. Vorssaint appeared as a warning in that build;
current inventory instead honors its explicit Control Center disallowance.

Cold **placement** was sampled without a recorder in
`.build/native-capture33/cold-no-recorder.json`. The first published control
stayed at x=989 through both sampled cycles. Whole native preparation plus reveal
completed at about **1.60 seconds cold** and **0.75 seconds warm**. Native pin
visibility must converge before settled geometry is accepted; bounded waits
preserve fail-open behavior. These timings are not the animation duration or a
cold pixel-motion result.

Actual pixel-motion evidence in `.build/native-motion33-results.json` covers
**two warm recorded reveals**. Their 25 and 27 preparation frames contain no
early glyph ink, and each reveal has five distinct partial glyph levels.
Pocket shares the existing curtain mask and occupied-region progress rather
than appearing early or replacing the reveal with a single icon pop. Quick
retains its selected 180 ms reveal / 160 ms hide.

The broader predecessor run, `.build/native-qa-build28/results.json`, completed
**seven of fourteen scenarios**: collapsed absence, native overflow, four
independent first-frame placements, forty direct reversals, forty actual arrow
actions, departure auto-hide and pins-only leading placement. No complete
current fourteen-scenario pass is claimed. Focused predecessor evidence in
`.build/spotlight25/results.json` covers real Spotlight source resolution, its
target, native hiding/glyph capture and return. It does not establish a physical
held-Command gesture. Build 25's initial cold image load took 6.72 seconds;
native image capture can add a separate first-open wait.

Actual CUA Show → popover → Hide clicks were recorded on build 32 in
`.build/native-capture32/actual-click-states.json`; the relevant hierarchy and
open/close path are unchanged in 33. This isolated setup used the explicit
capture hold, requiring both `--test-controls` and `--qa-hold-pocket`. Held
appearance captures do not establish normal dismissal or auto-hide. Normal
popovers remain transient, and system-presentation suppression still cancels
the held QA surface.

`.build/native-restoration33.json` records the normal installed 0.5.0 (33)
launch without test flags, matching installed/built executable hashes and
verified signing. Both real pins remain unchanged; Sparkle's last-check
timestamp is the only stored preference delta. The fixture was unregistered
and moved to ignored retired fixtures, and no QA helpers remained. Cleanup
reopened the same installed successor; it did not restore build 15.

The older build-21 resource sample remains historical; see
[release readiness](RELEASE_READINESS.md#historical-build-21-resource-sample).

## Native QA harness

`Tests/Native/StatusFixture.swift` is a public, disposable AppKit fixture with
eight distinct status glyphs, real native menus and a controllable fullscreen
window. `scripts/qa-native.py` drives the installed candidate's real controllers,
AX and WindowServer through test controls. Return cases drive the actual Pocket
source control with local AppKit callbacks and use the production paired, tagged
native status-item move on the disposable fixture only. This does not synthesize
or establish acceptance of a physical held-Command gesture.
The ordinary-arrow regression additionally posts 20 paired WindowServer mouse
clicks into the disposable fixture's transparent blocker. It requires that
fixture's existing event-posting authorization and never targets an arbitrary
screen coordinate or a real publisher's control.
The harness opens its own desktop QA window before exercising fullscreen, so
the test scene does not depend on the user's frontmost application.

Run on an unlocked macOS 27 Mac with Accessibility and capture permissions, Right
management and Pocket enabled, and enough status items to produce real overflow.
Keep the pointer outside the menu bar and popover for the departure check. Quit
the ordinary Draplet process first: a running copy causes the controlled launch
to exit. Build the fixture from the repository root with Xcode command-line tools:

```sh
qa_fixture=".build/Draplet QA Status.app"
mkdir -p "$qa_fixture/Contents/MacOS" "$qa_fixture/Contents/Resources"
xcrun swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos14.2" \
  -framework AppKit Tests/Native/StatusFixture.swift \
  -o "$qa_fixture/Contents/MacOS/StatusFixture"
cp Resources/Draplet.icns "$qa_fixture/Contents/Resources/"
python3 - <<'PY'
import plistlib
from pathlib import Path
info = {
    "CFBundleExecutable": "StatusFixture",
    "CFBundleIconFile": "Draplet.icns",
    "CFBundleIdentifier": "org.drapletqa.native",
    "CFBundleName": "Draplet QA Status",
    "CFBundlePackageType": "APPL",
    "LSUIElement": True,
}
Path(".build/Draplet QA Status.app/Contents/Info.plist").write_bytes(plistlib.dumps(info))
PY
codesign --force --sign - "$qa_fixture"
ditto "$qa_fixture" "/Applications/Draplet QA Status.app"
python3 scripts/qa-native.py --app /Applications/Draplet.app \
  --fixture "/Applications/Draplet QA Status.app" --report .build/native-qa
```

The fixture bundle keys match the locally exercised fixture. The example installs
the general fixture to `/Applications` because that case tests native filtering,
not the unsupported-publisher fallback. To exercise the fallback, compile
`Tests/Native/CompatibilityFixture.swift` as `Contents/MacOS/StatusFixture` in a
separate app under `~/Applications`, using the same `org.drapletqa.native` bundle
identifier and accessory app keys above. Do not run both reserved fixtures at
once. `scripts/qa-pocket-compatibility.py --fixture <that-app> --report <directory>`
requires the installed app's normal PID in `.build/membership43/normal.pid` and
verifies the executable before stopping it; it relaunches it in `finally`.

The general harness writes results and runtime logs under the report directory,
snapshots the starting
preferences, temporarily pins `org.drapletqa.native`, and removes that reserved
test pin while preserving real pins. It closes its controlled processes; the
fixture also exits on stdin EOF or its watchdog. The run exercises actual
fullscreen transitions and native menus on this Mac. The pin-cleanup check waits
for the runtime pin set to match the real starting pins. After success or failure,
reopen the **same installed successor** normally:

```sh
open /Applications/Draplet.app
```

Do not restore an old build-15 backup as QA cleanup. An optional
`--screenshot-helper` accepts a local screenshot script; the harness's current
crop coordinates are specific to the tested physical display. They must be
adapted before using another display arrangement.

## Compatibility limits

Native evidence comes from macOS 27, Apple silicon and one physical display.
Historical cold placement and warm pixel motion have separate evidence scopes;
current build-38 validation remains pending.
A virtual Sill display was present; correct physical host selection does not
establish multi-monitor acceptance. The CUA key API rejected a single-modifier
Command hold, so it could not synthesize a held-Command hardware drag. Physical
Command-drag in both directions, complete keyboard/VoiceOver use, fresh Mission
Control and Fladder/Minecraft acceptance, macOS 14.2–26, Intel, multiple physical
displays, long-running animated icons, GPU/WindowServer cost and battery use
remain unvalidated. Native fixture
fullscreen tests do not substitute for the third-party fullscreen regressions.

Ice's legacy physical move-and-return machinery is not included. If native
visibility fails, restrictions are released to preserve access. Historical
build-13 updater and mounted-DMG results predate Pocket. No current successor
DMG/updater acceptance, public binary release or feed publication is claimed.

## Licensing

Draplet as a whole is GNU GPL version 3. Ice-derived capture/window/event code
is documented in [Vendor/Ice/ORIGIN.md](../Vendor/Ice/ORIGIN.md); Thaw-derived
MenuBarAgent geometry and identity matching in
[Vendor/Thaw/ORIGIN.md](../Vendor/Thaw/ORIGIN.md). Original Draplet MIT, Hidden Bar
and Sparkle notices remain intact.

Binary releases must supply matching corresponding source, including build
scripts, vendored adaptations, required dependency sources and build instructions.
Attribution alone is insufficient. No automated corresponding-source archive
generator exists; prepare and verify this material for each release. See
[UPDATES.md](UPDATES.md). Source, tag and license resources must match the binary.
