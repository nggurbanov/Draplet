# Hidden Bar

The files in `Vendor/HiddenBar` are from https://github.com/dwarvesf/hidden,
commit `47937b9d8aede0325ca87a7880af13433e7c5cf8`, licensed under MIT.
Copyright (c) 2019 Dwarves Foundation; individual source headers also credit 2026.
The complete license is in `Vendor/HiddenBar/LICENSE` and included in the app.
The original `ic_expand.png` and `ic_collapse.png` artwork in `Resources/HiddenBar`
is from the same project and license; its preset is named "Hidden Bar" as homage.

Local modification: add bounded Accessibility messaging timeouts to the extras
menu bar and individual status items, as well as their owning application.

The menu-bar hiding framework used on macOS 27 is private and dynamically
resolved. If it is unavailable, Draplet leaves the icons visible. Restrictions
are released when Draplet quits or its process exits. No assessment session,
keyboard lock, or other system restriction is activated.

# Vorssaint availability format

`Sources/MenuBarAvailability.swift` references the Control Center availability
format described by Vorssaint's `App/MenuBarAllowanceSupport.swift`,
Copyright (C) 2026 Vorssaint, under GPL-3.0-or-later. This prevents capture of
status items explicitly disabled by macOS. The complete GPL accompanies Draplet.

# Sparkle

Draplet includes [Sparkle 2.10.0](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0)
for in-app updates. Sparkle is copyright the Sparkle Project contributors,
licensed under MIT, with additional third-party notices. The complete distributed
license is included as `Sparkle-LICENSE` in the app’s Resources. Sparkle's framework,
installer and downloader helpers are distributed together with Draplet.

# Ice

Draplet Pocket adapts selected mechanisms from [Ice](https://github.com/jordanbaird/Ice),
revision `11edd39115f3f43a83ae114b5348df6a0e1741cf`, by Jordan Baird and contributors,
under GNU GPL version 3. See `Vendor/Ice/ORIGIN.md` for the exact source paths and
local modifications dated 2026-10-18. The complete license is in `Vendor/Ice/LICENSE`
and included as `Ice-LICENSE` in app Resources. Draplet as a whole is distributed
under GPL v3; existing MIT components retain their notices. The original Draplet
MIT notice is retained in `LICENSES/Draplet-original-MIT.txt` and the app Resources.

## Thaw

Native host geometry and overflow identification adapt selected mechanisms from
[Thaw](https://github.com/thaw-app/Thaw), Copyright (Thaw) © 2026 Toni Förster,
under GPL v3. Exact revision, source paths and modifications are retained in
`Vendor/Thaw/ORIGIN.md`; its license is included as `Thaw-LICENSE` in app Resources.
