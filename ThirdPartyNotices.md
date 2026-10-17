# Hidden Bar

The files in `Vendor/HiddenBar` are from https://github.com/dwarvesf/hidden,
commit `47937b9d8aede0325ca87a7880af13433e7c5cf8`, licensed under MIT.
Copyright (c) 2019 Dwarves Foundation; individual source headers also credit 2026.
The complete license is in `Vendor/HiddenBar/LICENSE` and included in the app.

Local modification: add bounded Accessibility messaging timeouts to the extras
menu bar and individual status items, as well as their owning application.

The menu-bar hiding framework used on macOS 27 is private and dynamically
resolved. If it is unavailable, Draplet leaves the icons visible. Restrictions
are released when Draplet quits or its process exits. No assessment session,
keyboard lock, or other system restriction is activated.
