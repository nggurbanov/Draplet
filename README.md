# Draplet

Your menu bar, on demand. A small, free, open-source macOS utility for both sides
of the menu bar. MIT licensed. Personal daily-use build, 0.3.0.

## Use

- Left: keeps the Apple logo and application name visible; hover or click to uncover the
  native application menus. The title stays in place.
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
Draplet detects the grant without a restart. Background matching additionally
requires Screen & System Audio Recording access (macOS's name for the permission).
Draplet captures no audio and processes only a narrow menu-bar strip, locally in
memory. It excludes its own covers and other menu-bar overlays. Without capture
access, the left cover waits and right-side hiding uses its native mode. No Input
Monitoring permission, account, subscription or network access is needed.

## Animations and background

Settings → Animations defaults to mirrored Curtain reveals, opening inward toward
the notch. Fade is available for both sides. Unlink the sides to choose separately;
Hidden Bar is available only on the right and preserves its native movement/timing.
A shared timing control offers A (180 ms reveal / 160 ms hide, the original left
pace) and B (550 ms / 250 ms, based on measured native right-side motion). Preview
Both Sides demonstrates the selection. The right side prepares native icon layout
behind its cover before revealing, and settles the hidden layout behind the cover
after closing. Reversing a transition cancels stale callbacks; failures release the
cover and reveal the icons. Reduce Motion disables the custom transition.

Settings → Menu-bar background offers:

- **Cached** (default): freeze one complete frame from the same rendering stream
  as Live, then stop capturing. This retains native shading that macOS's still
  screenshot API omits. A cheap two-second check compares wallpaper URL/options
  and file metadata. App activation and window changes near the bar also refresh
  it, since those windows contribute shadows. Space/display/wake and appearance
  events refresh it too; the previous image stays visible until its replacement
  is ready. No stream runs while the scene is unchanged.
- **Live**: stream the same strip at up to 30 fps for animated wallpapers. Unchanged
  frames are skipped. This uses more energy; choose it for motion providers that
  keep the same wallpaper URL. Refresh Background is also available manually.

The native menu-bar window supplies opacity, vertical shading and foreground
contrast without copying its menu glyphs. This also handles Reduce Transparency.
There is no documented public wallpaper-change notification. The wallpaper-store
file's modification time is an optional extra signal; public URL/options and system
events remain the main mechanisms. Providers that change pixels without changing
metadata need Live mode. Cached images are held in memory, not saved to disk.

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

- The current layout targets the primary built-in notched display and English
  menu geometry on the developer's Mac (macOS 27.0.1). Blue wallpaper and native
  opaque/translucent treatment have been checked live. Light/dark contrast and
  vertical shading also have bitmap tests. Other OS versions, external displays,
  RTL typography and every macOS menu-bar appearance option are not yet verified.
- Background reconstruction preserves the clean underlying strip and the native
  bar's scanline treatment. It is not a guarantee of pixel-perfect reproduction
  of every future Liquid Glass effect or arbitrary horizontal material pattern.
  Covers stop at the native bar body, leaving the border below it untouched.
- Left cover level 25 stays below the user's Vorssaint notch UI at level 26.
- macOS 27 icon hiding uses Hidden Bar's dynamically loaded private menu-bar
  visibility API. A changed/missing API fails open. Hiding is per app bundle,
  including all of an app's status items together. System controls stay visible.
- Earlier macOS versions use the spacer engine; this build is verified on the
  developer's Mac, not a compatibility matrix.
- Revealed icons can still run out of physical space around the notch. Optional
  "Make room for icons" uses Draplet's shorter app menu; a separate overflow
  shelf is not included.
- Donations, public distribution, notarization and automatic updates are not
  included yet. No public repository has been created by the build process.

## Validation

`test.sh` checks LTR/RTL section resolution, protecting the most-visible sibling
icon, own/system controls, stale inventory cancellation, late native assertion
invalidation, successful release, and fail-open activation errors. It also checks
persisted styles/timing/background mode, wallpaper-file replacement invalidation,
mirrored Curtain/Fade bitmap output, native-treatment extraction and contrast, and
right-transition reversal/timeout handling, retained closed covers, and disabling
implicit window fades. A rapid 24-click frame recording reproduced late native
icon flashes before the fix and found none with retained covers and window
animations disabled. Live checks cover actual native
hiding/reveal, A/B durations, cached one-shot versus streaming behavior, blue and
opaque backgrounds, keyboard shortcuts and clean exit. Animation timers run at
60 fps only during transitions; Live background capture is separately optional.

`Reference/` preserves the exact approved prototype and its timed launcher.
See [ThirdPartyNotices.md](ThirdPartyNotices.md) for Hidden Bar attribution.
