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

# Sparkle

Draplet includes [Sparkle 2.10.0](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0)
for in-app updates. Sparkle is copyright the Sparkle Project contributors,
licensed under MIT, with additional third-party notices. The complete distributed
license is included as `Sparkle-LICENSE` in the app’s Resources. Sparkle's framework,
installer and downloader helpers are distributed together with Draplet.
