# Pocket (alpha)

Pocket keeps overflow and deliberately pinned status items reachable in a compact
native popover. This document describes 0.5.0 build 45. See
[release validation](RELEASE_READINESS.md) for the tested scope and remaining limits.

## Reveal and auto-hide

Enable **Settings → Right → Use Pocket**. The horizontal right arrow keeps its
native accordion behavior, including click, hover, Option-click and the shortcut.
While that strip is expanded, a separate down-chevron sits leftmost, before all
visible right status icons. It points up while Pocket is open. It replaces the
native overflow slot or uses verified free space before the first physical slot.
With no eligible overflow or running pinned items, it is absent.

With Curtain selected, Pocket's chevron and the status icons reveal under the
same mirrored curtain at the selected pace. Collapse immediately hides the
chevron and closes Pocket; late inventory callbacks cannot bring it back.

The expanded strip, chevron and popover share pointer retention. Native menus,
capture/action work, transitions and drags also hold reveal. Leaving all of them
starts the configured auto-hide delay (five seconds by default); re-entry resets
it. Escape, an outside click, unrelated application activation, Space/display
changes, pause and fullscreen/system presentation dismiss the popover.

## Placement and gestures

- **Keep in Pocket / Return to Menu Bar** is available in Right settings and item
  context menus. Pins use bundle identifiers and survive application restarts.
- Hold **⌘** while dragging a native status icon into Pocket's highlighted target
  to pin its app. This temporary target can open even when the strip is collapsed
  or Pocket is empty, and anchors to the drag's starting point and display.
- Hold **⌘** from mouse-down through release to drag a Pocket item back onto the
  right menu bar. Pinned items unpin; automatic overflow items request a native
  slot, subject to native visibility and compatibility constraints.
- Hold **⌘** and drag within Pocket to reorder cells. The insertion marker shows
  the destination. Grid order persists independently of physical menu-bar order.
- Escape, releasing Command early, stale sessions and outside drops cancel.
  Ordinary clicks invoke the original status-item action. Right-click offers
  **Open Application Menu** and placement actions.

On the macOS 27 backend, pinning groups all status items from the same app.
Shared system controls and input agents cannot be pinned; individually hosted
items require a verified distinct owner. Saved pins can still be removed when
the native hiding backend is unavailable. The guarded gesture paths are
implemented; automated callbacks do not establish physical drag acceptance on
all hardware or publishers.

## Membership and compatibility returns

Automatic membership uses a settled, readable native host and exact unrendered
item identities, including individual siblings from one app. Spare estimated
width or an absent system overflow button does not prove that an item is
rendered. Explicit pins stay separate. Always-hidden items are excluded unless
that section is explicitly revealed; Control Center-disallowed publishers are
excluded from capture while their saved pins remain intact.

A native return must remain physically rendered after the normal visibility
policy restores. If an original item cannot render under that policy, Draplet
can create an owned native compatibility slot with its last-good real glyph.
Its action belongs to the original app, not a reconstructed menu. The slot
follows the accordion, can be pinned again and restores from a saved identity.
If the original becomes renderable, the redundant slot is removed.

Compatibility slots are cached visual substitutes. Changing artwork and
counters need **Refresh Icons**; arbitrary custom popup/right-click behavior
depends on the original app's Accessibility implementation. Draplet does not
move or modify the source application. Native placement uses paired, tagged
Command events and restores only Draplet's disclosure beside its prior neighbour;
it never writes foreign preferences or the private global position table.
Pending synthetic releases are balanced on cancellation and quit.

## Native appearance and images

Pocket is a downward-opening native `NSPopover` with a top pointer, native
material, border and shadow. The icon-only grid has 34-point minimum cells,
4-point gaps and 10-point insets, with up to three columns and five visible rows
before scrolling. Wide glyphs span cells. Native logical size, Retina backing,
monochrome tint and original colored imagery are preserved. Names belong in
tooltips and accessibility labels; there is no launcher header or footer.

A failed refresh retains the last-good image and its action. An item without a
usable glyph may show loading/unavailable state or be omitted after failure.
Application artwork is never substituted for actual status imagery. The chevron
context menu offers **Refresh Icon Images** and **Arrange Icons…**.

## Capture and cache

Accessibility supplies native identities, geometry and actions. On macOS 27,
MenuBarAgent must expose the actual target display's rendered slots. Parked
backing-window frames or a generic extras catalog cannot establish physical
placement. `HostedMenuBarInventory` reconciles native-host geometry before
completing the publisher scan; unavailable verified geometry fails open.

Screen & System Audio Recording permission is required for real glyph capture,
even with background matching disabled. No audio is captured. Small one-shot
snapshots cover temporary native staging; capture waits for rendering and fresh
host geometry, then restores visibility. Pocket does not add a persistent image
stream. Fullscreen detection uses window metadata and bounded AX queries.

Last-good glyphs persist under `~/Library/Caches/com.tyrell.Draplet/Pocket-v1/`,
bounded to 128 records. A soft 120-second age makes an image eligible for idle
refresh; failures back off for 30/120/600/3600 seconds without clearing it.
Display changes preserve pixels, and normal quit drains pending cache writes.
Collapsed prewarming uses a matched prefix shield ending before the arrow and
system controls, preserving visible native capacity. New images may still need
foreground capture. A matching prepared layout skips the repeated 300 ms warm
settling delay while still awaiting native activation. Cold preparation and
retries can take longer; caching is not a zero-latency guarantee.

## Input ownership

A narrow event router prevents transparent foreign status hit windows from
stealing clicks on Draplet's verified native arrow and other rendered slots.
For another publisher it claims a balanced ordinary click only when a different
managed publisher's small hit window is frontmost, retains the exact target
through release and revalidates its identity and frame before its native action.
It does not replay a click at an unscoped coordinate. Genuine Command drags,
tagged placement, a publisher's own hit surface and higher popups retain native
input. Invalidated geometry or release outside cancels the action.

The arrow's balanced click route also avoids the native pressed gray capsule.
The router adds no overlay or capture stream, performs no AX walk in the event
tap and stops while right management is disabled, paused or presentation-suppressed.

Cells are native accessible buttons. Arrow navigation follows the spanning grid;
Enter or Space invokes the focused item. AXPress is the primary action and
AXShowMenu is preferred for an explicit application-menu action. A timed-out AX
operation has an unknown outcome and is never replayed. Safe fallback routing
requires definite unsupported-action results and fresh geometry. Complete
keyboard/VoiceOver and arbitrary custom-publisher acceptance remain unverified.

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

Do not restore an older build as QA cleanup. An optional
`--screenshot-helper` accepts a local screenshot script; the harness's current
crop coordinates are specific to the tested physical display. They must be
adapted before using another display arrangement.

## Compatibility limits

The release was validated locally on macOS 27, Apple silicon and one physical
display. Older macOS, Intel and multiple physical displays need hardware testing.
Native fixtures do not replace physical held-Command gestures or every third-party
fullscreen/popover regression. Long-running animated icons, GPU/WindowServer
attribution, battery and long-term memory behavior remain outside this pass.

The dynamically resolved native backend can change with macOS. Missing geometry
or unavailable native visibility fails open to preserve access. Cold glyph
capture, compatibility-slot imagery and publisher-specific actions retain the
limits described above. See [release validation](RELEASE_READINESS.md).

## Licensing

Draplet is GPL v3. Ice-derived capture/window/event adaptations are documented in
[Vendor/Ice/ORIGIN.md](../Vendor/Ice/ORIGIN.md), and Thaw-derived native geometry in
[Vendor/Thaw/ORIGIN.md](../Vendor/Thaw/ORIGIN.md). Original Draplet MIT, Hidden Bar
and Sparkle notices remain intact.

Binary releases include matching corresponding source with build scripts,
vendored adaptations, required dependency sources and build instructions.
`scripts/prepare-source.py` creates the source archive and manifest. See
[UPDATES.md](UPDATES.md) for the release procedure.
