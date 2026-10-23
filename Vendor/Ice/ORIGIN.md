# Ice-derived pocket support

Upstream: https://github.com/jordanbaird/Ice
Revision: `11edd39115f3f43a83ae114b5348df6a0e1741cf` (main, retrieved 2026-10-18).
Author attribution: Jordan Baird and Ice contributors. License: GNU GPL version 3;
complete upstream license retained in this directory.

Adapted sources:
- `Ice/Bridging/Bridging.swift`: enumeration of menu-bar window IDs.
- `Ice/Utilities/ScreenCapture.swift`: isolated window-image capture, including offscreen extras.
- `Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift`: target PID/window event fields,
  left/right click construction, temporary-show/restore lifecycle.

Draplet modifications (2026-10-18): narrow Objective-C bridge with checked dynamic
symbol lookup and bounded allocation; namespaced event helper; on-demand capture;
native macOS 27 per-bundle reveal instead of physically moving icons; independent
SwiftUI grid, settings, cancellation and presentation suppression integration.
This is an adaptation of selected mechanisms, not an unmodified Ice component.

Draplet addition (2026-10-23): automatic Pocket overflow can return via a
bounded native Command status-item move after fresh host-frame validation.
Events carry a Draplet-only tag to avoid recursive pin recognition; button-up
is always posted, and cursor restoration is conditional on no intervening
pointer movement. The result is checked again after native visibility restores.
No preferred-position table writes, external runtime binaries or persistent
input-suppression services are used for this path.
