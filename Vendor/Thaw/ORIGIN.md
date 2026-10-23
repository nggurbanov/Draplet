# Thaw-derived native host geometry

Upstream: https://github.com/thaw-app/Thaw
Revision: `c0afbdbf045eca8b1d276e7493272ee07c3996be` (`feat/thaw-3`, retrieved 2026-10-18).
Copyright (Thaw) © 2026 Toni Förster. GNU GPL version 3.

Adapted mechanisms:
- `ThawAX/Sources/ThawAXCore/MenuBarAgentWindow.swift`: read MenuBarAgent's
  window children, descend only through host-owned wrappers, stop at the real
  owner, and use host geometry rather than the publisher's stale parked frame.
- `ThawAX/Sources/ThawAXCore/AXPrimitives.swift` and
  `Thaw/Items/Interaction/MenuBarItemAXProvider.swift`: identify native overflow
  via AXOverflowButton / the host's direct AXButton role.
- `MenuBarModel/Sources/MenuBarModel/Bridging.swift`: dynamically resolve
  SLWindowListCreateImageFromArray before the deprecated CG capture path.

Draplet modifications: a small bounded AX walk with exact AX-element identity
matching, on-demand staging and geometry checks, no background image stream,
no global preferred-position writes or Thaw helper services. Adapted code lives
in Sources/PocketInventory.swift and Vendor/Ice/PocketWindowAccess.m.
