# Menu-bar Pocket (alpha)

Choose **Settings → Right → Show hidden icons in → Pocket**. Existing users keep
Menu Bar until they opt in. Click the right arrow (or use its configured hover
action) to open a compact grid below the menu bar. Wide status text spans cells;
long inventories scroll. Cell positions stay fixed while captures arrive; newly
captured wide images can span cells on the next opening. Each cell is a native,
accessible button. Arrow keys follow the actual spanning grid and stop at its
edges; Enter or Space activates only the focused cell. Refresh and Reveal in
Menu Bar retain their own native button actions. Primary clicks invoke AXPress.
Secondary clicks try AXShowMenu. Native mouse routing is allowed only after a
definite unsupported-action result and a safe native frame. Escape,
an outside click, a Space/display/application change, pause and system overview
close the panel. The auto-hide preference also applies after the pointer leaves.
**Reveal in Menu Bar** retains native-bar access. The both-sides shortcut reveals the left menus and opens Pocket when Pocket is selected.

## Implementation and permissions

The inventory uses Accessibility extras and excludes Draplet and macOS's own
shared item owners. On macOS 27 the existing native visibility engine's saved
layout identifies hidden versus always-hidden bundles. Temporary exposure never
reclassifies the user's layout. Normal Pocket excludes the always-hidden section;
Option-click can include it. macOS 27 visibility remains per application, so
siblings appear together during a temporary reveal.

Ice-derived mechanisms enumerate and capture individual status windows when
available and construct native left/right mouse events with target window/PID
fields. On macOS 27 status extras share MenuBarAgent's surface, so Pocket exposes
small batches and takes one-shot, cursor-free snapshots of their small rectangles.
It resolves AX geometry afresh after reflow and waits for the native renderer
before sampling. When a status image is unavailable, Pocket uses a bounded 48-pixel raster of the application’s actual artwork and retains its name. Icon-image failure does not disable primary access. Near-uniform
native backgrounds become alpha; monochrome icons follow panel appearance.

Screen Recording permission enables actual status images. Without it, Pocket remains usable with application artwork when background matching is otherwise disabled. There is no audio, persistent Pocket
stream or on-disk user-image cache. Images are reused for up to two minutes;
**Refresh icons** forces an update. Text badges can therefore be stale. Captures
are cancelled by generation on dismissal; stale work cannot reopen the panel.
Its 20 Hz presentation watchdog runs only while Pocket is active; after activation,
existing right-side polling waits for native interface dismissal before restoring
the normal visibility restriction. No icon arrangement is physically changed on
macOS 27. The Settings window remains the only reason to show Draplet in the Dock.

## Compatibility limits

Current hardware acceptance is macOS 27 on Apple silicon. Primary actions address
the AX element directly and do not depend on a visible coordinate. An AX timeout
(`cannotComplete`) is an unknown outcome: a tracking menu may already be open,
so Pocket never replays it as a mouse click. On legacy hiding engines,
individual-window capture can work and activation first reveals the native bar.
macOS 14.2–26, Intel and multiple physical displays remain unvalidated. Ice’s
legacy physical move-and-return machinery is not included in this alpha.

Some apps leave an AX extra without a drawable status icon. These use app artwork. If a secondary action is unsupported and the real frame is behind the notch, Pocket returns to the native bar with an explanation instead of guessing a click position. If the visibility API fails, restrictions are released and native
access is restored. GPU/battery cost and long-running animated-item behavior
have not yet been quantified for this feature.

## Local acceptance — 0.5.0 (build 14)

The 2026-10-18 pass recorded 195 passing checks, including exposure restoration,
notch-safe frames, capture isolation, fallback action policy and spanning-grid
navigation. The native build and code-signature verification passed. The final
local test log is `/tmp/Draplet-pocket-tests-final.log`; these checks do not
establish universal status-item compatibility.

Seven real status items plus two deliberately wide QA fixtures exercised overflow.
Six cells showed captured status imagery and three used application artwork. A
real click on the A1 fixture cell opened its original native menu (window layer
101, x=648, y=34), recorded in `.build/pocket-primary-final.log`. Earlier Shottr
checks exercised primary and secondary native mouse routing. These are individual
app/fixture results, not acceptance of every third-party icon.

A short closed-Pocket process sample (`.build/pocket-idle-resources.json`,
10.005 seconds) measured 1.696% of one core, 30.75 MiB footprint, 102.67 MiB RSS
and 5.1 package-idle wakeups/s. It excludes WindowServer, does not measure GPU or
battery use, and is not a controlled energy benchmark. Build-13 updater/DMG
acceptance predates Pocket and has not been repeated for build 14.

## Licensing

Draplet as a whole is GNU GPL version 3. Ice attribution, the pinned upstream
revision and local modifications are in `Vendor/Ice/ORIGIN.md`. MIT notices for
pre-existing Draplet code, Hidden Bar and Sparkle remain intact. Binary releases
must supply matching corresponding source, including build scripts, vendored
adaptations, required dependency sources and build instructions; merely adding an
acknowledgment is not sufficient. There is no automated corresponding-source
archive generator yet; prepare and verify that material for each release. Do not
publish a binary with mismatched source, tag or license resources.
