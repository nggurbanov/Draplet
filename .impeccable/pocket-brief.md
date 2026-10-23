# Pocket — current user contract

Mode: Operate. This is an ordinary native macOS refinement. Preserve the
incumbent `DESIGN.md` and `.impeccable/design.json`; no new world, palette, type
scale or visual tokens are needed.

## Reveal and placement

The original horizontal arrow/curtain retains native accordion reveal, click,
hover, Option-click and shortcut behavior. Pocket's separate down/up chevron is
visible only while the right strip is expanded and is always leftmost, before
every visible right status icon. Replace native overflow's leading slot; in a
fitting pins-only layout use verified empty space before the first physical
status slot. Collapse hides it immediately; late scans cannot restore it. Saved
pins are reached by expanding the original horizontal arrow. With neither
overflow nor eligible running pinned items, there is no Pocket control. Never reserve a
permanent half-control beside the original arrow.
When Pocket replaces native overflow, no native double-chevron remains beside it.
With Curtain selected, Pocket and the right icons reveal together under the
existing mirrored curtain, following its progress, direction and selected pace.
No isolated early chevron or all-at-once replacement of the icon reveal is
accepted. Preserve the other animation choices. Collapse still hides Pocket
immediately.
Use a verified native overflow slot, or a gap proven by rendered physical slots.
Without either anchor, keep the chevron hidden. An unavailable host cannot turn
unknown items into automatic overflow; explicit pins remain separate.

Automatic overflow contains exact nonfitting item IDs, never every sibling
merely because one app icon does not fit. Automatic overflow respects
always-hidden membership unless explicitly revealed. Deliberate pins persist by
bundle identity and remain accessible after expansion without automatic overflow.
The macOS 27 native backend
groups all status icons from one pinned app. Keep in Pocket / Return to Menu Bar
is available in Settings and item context menus; return restores the original
section and remains subject to available native space. Individually hosted items
such as Spotlight require a verified distinct owner; shared system controls and
input agents remain excluded.

Command-drag a real native status icon into the highlighted Pocket target to pin
its app, including when the target starts empty. This genuine-drag target can
open independently of strip expansion; it is not a persistent idle button.
Name the actual dragged status item, such as Spotlight, in that target.
Command-drag a pinned Pocket icon back onto the right menu bar to return its app.
Hold Command throughout.
Escape, outside drops, stale sessions and unrelated drags must not change pins.
Ordinary clicks invoke the real native status-item action/menu. The guarded
gesture paths are implemented; policy checks are not physical gesture acceptance.

## Surface and interaction

Visual authority remains the user's 2026-10-18 23.19.25 macOS emoji-picker
reference: a much smaller downward-opening native `NSPopover` with a top pointer,
translucent material, native border/shadow and a dense icon-only grid. Preserve
native logical glyph size, Retina backing images and native monochrome tint.
Preserve the original colors of colored status imagery. No application artwork
substitution, launcher tiles, permanent captions, title toolbar or footer.
Names belong in tooltips/accessibility. Keep the last-good real glyph clickable
when refresh fails; never substitute app artwork. Items with no usable image may
show loading/unavailable state or be omitted after capture failure. Exclude
explicit macOS Control Center `isAllowed=false` items from capture while keeping
their pins. Live Vorssaint has this flag; do not call it universally incompatible.

Persist last-good native glyphs locally, bounded to 128 records. Use a soft
120-second idle-refresh age and failure backoff of 30/120/600/3600 seconds without
clearing old pixels. Display changes preserve images; normal quit drains writes.
Collapsed idle prewarming uses a matched prefix shield ending before the original
arrow/system controls and preserves visible native capacity. A new glyph may
still need first foreground capture when hidden capacity is insufficient.
A matching verified prepared layout bypasses the repeated 300 ms warm settling
delay; native activation is still awaited and the cold preparation path remains.

The expanded strip, Pocket chevron and popover form one pointer-retention region.
Departure starts the configured delay, five seconds by default; re-entry resets
it. Native menus, capture/action work, transitions and drags hold reveal. Explicit
collapse immediately hides the chevron and closes Pocket before the native bar.
Escape/outside click, pause, Space/display changes and fullscreen/system
suppression preserve their normal
dismissal roles. Cold capture waits and warning states must not be represented
as universal zero-latency or complete third-party compatibility.

## Current evidence — build 38 pending

Current build-38 validation is pending. Build-37 motion was not accepted;
the following 36/37 cache timings are predecessor evidence only.

Predecessor build 37 passed **308 unit/policy checks** in
`/tmp/Draplet-latency37-tests.log`; native build/signing passes in
`/tmp/Draplet-latency37-build.log`. `.build/responsive37/checks.json` verifies idle
prewarm, eight real fixture glyphs plus Shottr/Spotify, four cached opens at
32–38 ms without recapture, failed-refresh retention and a fresh-process disk
open at 68 ms with ten cached images and zero capture requests. The first prepared
open took 53 ms; these are prepared-image timings, not cold capture.

Its dark/light native 130 × 168-point captures and actual CUA button open/close
passed. The matched prefix shield x=824–1197 excludes the original arrow at
x=1197–1239 and system controls; an arrow action interrupts warming. An in-process
display-change notification preserves ten images and working native collapse.
It does not establish physical display-change acceptance. Current build-38 warm-pixel
timing, bounded native backoff and final normal-launch restoration remain pending.

Predecessor `.build/native-motion36-results.json` measures warm first ink at
183/188 ms. Build-36 cached opens took 32–43 ms, while first missing-sibling
capture still took about 4.1 seconds. Neither those timings nor the historical
build-33 review establishes full build-38 acceptance or removes cold waits.

## Historical build-33 evidence and remaining scope

Build 33 passes **290 unit/policy checks** in
`/tmp/Draplet-pocket33-tests.log`; native build/signing passes in
`/tmp/Draplet-pocket33-build.log`. The fresh full review,
`.build/impeccable-finish33.md`, returned **SHIP for this narrow local
refinement**, with no material fixes. All seven historical captures and ten inspected
motion frames are valid. Native material, typography and compact geometry agree
with the incumbent design; no new visual tokens are needed.

`.build/native-capture33/` contains collapsed pins, expanded overflow, expanded
pins-only, dark/light Pocket, Spotlight target and pinned Spotlight captures.
Its five focused checks pass stable placement, four interrupted-reveal
cancellations, actual native overflow replacement, eight real 15.5 × 33-point
glyphs and the actual Spotlight target/magnifier. The grid is 130 × 168 points.
Vorssaint appeared as a warning in that build; current inventory honors its
explicit Control Center disallowance.

Cold **placement** is separately verified without recording in
`.build/native-capture33/cold-no-recorder.json`: first-published x=989 stays
stable. Whole native preparation plus reveal took about **1.60 seconds cold**
and **0.75 seconds warm**. Bounded waits require pin visibility to converge before
accepting final geometry and preserve fail-open behavior.

Actual pixel motion in `.build/native-motion33-results.json` covers **two warm
recorded reveals**. Their 25 and 27 preparation frames contain no early glyph
ink, and each has five distinct partial reveal levels. Shared curtain masking
and occupied-region progress preserve the selected Quick 180/160 ms animation.
These recordings do not establish cold pixel motion or zero preparation latency.

The broader predecessor `.build/native-qa-build28/results.json` completed
**seven of fourteen scenarios**, including four independent first-frame
placements, forty direct reversals, forty actual arrow actions and five-second
departure auto-hide. No complete current fourteen-scenario pass is claimed.
Focused `.build/spotlight25/results.json` establishes actual source/target,
native hiding/magnifier capture and return within that predecessor's scope;
physical held-Command acceptance remains unverified. Its initial cold image load
took 6.72 seconds.

Build-32 actual CUA Show → popover → Hide clicks are recorded in
`.build/native-capture32/actual-click-states.json`; the relevant hierarchy and
open/close path are unchanged in 33. The explicit capture hold requires both
`--test-controls` and `--qa-hold-pocket`. Such appearance captures do not prove
default dismissal or auto-hide. Normal popovers remain transient; system
presentation still cancels the held QA surface.

`.build/native-restoration33.json` records normal installed 0.5.0 (33), no test
flags, matching installed/built executable hashes and verified signing. Both real
pins are preserved; only Sparkle's last-check timestamp changed. The fixture
was unregistered and retired, with no QA helpers left running. Cleanup restored
the same installed successor, without rolling back to build 15.

The historical build-21 20.23-second Cached idle sample measured 0.49% of one
core and 75.3–75.7 MiB RSS; `sample` reported 14.8M physical footprint. These are
different measurements and are not current profiling, energy acceptance or
long-term leak proof.

Physical Command-drag in either direction remains unverified: CUA rejects a pure
held Command key. Fresh Mission Control and Fladder/Minecraft, full
keyboard/VoiceOver, Intel, macOS 14.2–26, multiple physical displays, GPU and
battery acceptance remain outside this pass. The virtual Sill display must not
supply physical glyph evidence. Current successor DMG/updater and public
binary/feed publication are not claimed. See `docs/RELEASE_READINESS.md` for
evidence and limits.

## Command drag refinement — build 40

Pocket cells support Command-only local rearrangement with a before/after
insertion marker and persistent native-item keys. Automatic overflow may be
reordered; menu-bar return remains the explicit-pin path. Keep app-group pinning
and the physical bar's native order independent of this grid order. The actual
control owns mouseDown/mouseDragged/mouseUp; ordinary clicks remain native actions.
After unmasking, Pocket's small control owns input above transparent status-window
overlays such as Crisp's level26 window. It remains beneath the shared curtain
while masked. No palette, spacing, material or original-arrow redesign.
327 automated checks pass; current physical Command-drag acceptance is pending.

## Local drag routing — build 41

Keep same-app Pocket gestures local, with a passive native-size image following
the cursor. Starting a system NSDraggingSession for a same-app return exposes
the top-edge path to Mission Control; do not change global system settings to
work around it. Commit only on Command-release inside the exact current target;
Escape, release of Command, window destruction and outside drops cancel. Native
status-item drags into Pocket retain their distinct existing implementation.
Build 40's physical start was user-confirmed, with Mission Control interrupting
return. Build 41 passes 333 checks; physical return acceptance remains pending.
