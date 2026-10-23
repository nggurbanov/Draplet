# Pocket — design contract

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

Use the native macOS emoji picker as a surface reference: a much smaller downward-opening native `NSPopover` with a top pointer,
translucent material, native border/shadow and a dense icon-only grid. Preserve
native logical glyph size, Retina backing images and native monochrome tint.
Preserve the original colors of colored status imagery. No application artwork
substitution, launcher tiles, permanent captions, title toolbar or footer.
Names belong in tooltips/accessibility. Keep the last-good real glyph clickable
when refresh fails; never substitute app artwork. Items with no usable image may
show loading/unavailable state or be omitted after capture failure. Exclude
explicit macOS Control Center `isAllowed=false` items from capture while keeping
their pins. A disabled instance does not establish universal publisher incompatibility.

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

## Drag routing and validation

Keep same-app Pocket gestures process-local with a passive native-size image.
Do not start a system dragging session for an internal return or change global
Mission Control settings. Keep physical menu-bar order independent of grid order.
Commit only on mouse release inside the current target with Command still held;
Escape, early Command release, stale sessions and outside drops cancel. Genuine
native status-item drags into Pocket retain their separate path.

Current behavior and reproducible QA are documented in docs/POCKET.md.
Release evidence and unresolved hardware limits are in docs/RELEASE_READINESS.md.
Do not interpret implemented gesture guards as hardware acceptance.
