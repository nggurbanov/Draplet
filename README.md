# Draplet

Your menu bar, on demand. A small, free, open-source macOS utility for both sides
of the menu bar. MIT licensed. Personal daily-use build, 0.2.0.

## Use

- Left: keeps the Apple logo and application name visible; hover or click to uncover the
  native application menus with a 180 ms feathered wipe. The title stays in place.
- Right: click the arrow to hide or reveal status icons. Right-click for Settings,
  Pause/Resume, Reveal Both Sides, and Quit.
- Both sides default to Hover. Settings → Reveal offers a shared Hover/Click
  selector or independent choices. Clicking also works in Hover mode. The left
  arrow stays visible and toggles both ways; while open it sits after the last
  menu (or before the Apple glyph if the menus fill the space up to the notch),
  leaving File and the other native menus clickable.
- Settings → Icons offers matching Chevron, Arrow, Triangle, Hidden Bar, Dots,
  or custom artwork, with optional separate choices. Directional presets mirror
  toward/away from the center; custom artwork keeps its orientation. Hidden Bar
  uses its original arrows as homage. Custom PNG/JPEG/TIFF/PDF files (up to 8 MB)
  are copied as a compact transparent template into preferences, so removing the
  source file doesn't break the icon. Custom artwork can be replaced or removed.
- Hold ⌘ and drag the arrow between icons to choose the boundary. Icons to its
  left hide; icons to its right remain visible. macOS remembers the arrangement.
- Optional hover reveal, auto-hide delay, and an always-hidden section are in
  Settings. With that section enabled, put its dotted divider left of the arrow;
  ⌥-click the arrow to reveal every section for arranging it.
- ⌃⌥Space reveals both sides. Alternatives ⌃⌥D, ⌃⌥B, or Disabled are in Settings.
- Launch at login is opt-in. Reopen `/Applications/Draplet.app` for Settings.
- Quit releases the icon-hiding assertion and removes every cover/status item.

Accessibility is required for reading menu geometry. Grant it through Settings;
Draplet detects the grant without a restart. It does not need Screen Recording,
Input Monitoring, an account, a subscription, or network access.

Hidden Bar is detected and right-side management waits until it quits. The
Settings handoff button quits Hidden Bar without changing its login setting.
To use Draplet after reboot, enable its login option and disable Hidden Bar's
own login option yourself so they don't both launch.

## Build locally on macOS

Requires Apple's Command Line Tools, macOS 14+, and bash. No package manager or
downloaded dependencies are needed; the small right-side engines are vendored.

```sh
bash build.sh
bash test.sh
open .build/Draplet.app
```

The output is `.build/Draplet.app`. The build script uses an available Apple
Development signing identity, or ad-hoc signing if none exists. To choose one,
set `DRAPLET_SIGNING_IDENTITY` to its identity hash. Keep the same identity and
bundle identifier across installed builds so permissions stay associated.
The icon source is `scripts/make-icon.swift`; the generated ICNS is checked in.

## Current scope and limits

- The left cover is tuned to the approved black menu bar, English layout, and
  built-in notched display on the developer's Mac (macOS 27.0.1). Broader light,
  translucent, RTL and external-display rendering is future work. It rebuilds on
  display changes/wake and follows menu-bar visibility, but those wider cases
  have not received the same real-world verification.
- Left cover level 25 stays below the user's Vorssaint notch UI at level 26.
- macOS 27 icon hiding uses Hidden Bar's dynamically loaded private menu-bar
  visibility API. A changed/missing API fails open. Hiding is per app bundle,
  including all of an app's status items together. System controls stay visible.
- Earlier macOS versions use the spacer engine; this build is verified on the
  developer's Mac, not a compatibility matrix.
- Revealed icons can still run out of physical space around the notch. Optional
  "Make room for icons" uses Draplet's shorter app menu; a separate overflow
  shelf is not part of 0.1.
- Donations, public distribution, notarization and automatic updates are not
  included yet. No public repository has been created by the build process.

## Validation

`test.sh` checks LTR/RTL section resolution, protecting the most-visible sibling
icon, own/system controls, stale inventory cancellation, late native assertion
invalidation, successful release, and fail-open activation errors. Live checks
also cover actual native hiding/reveal, unchanged left geometry and typography,
60 fps transitions only while animating, keyboard shortcuts and clean exit.

`Reference/` preserves the exact approved prototype and its timed launcher.
See [ThirdPartyNotices.md](ThirdPartyNotices.md) for Hidden Bar attribution.
