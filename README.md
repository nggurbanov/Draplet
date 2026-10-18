# Draplet

Your menu bar, on demand. A small, free, open-source macOS utility for both sides
of the menu bar. MIT licensed. Personal daily-use build, 0.4.4.

## Use

- Left: keeps the Apple logo and application name visible; hover or click to uncover the
  native application menus. The title stays in place.
- Right: click the arrow to hide or reveal status icons. Right-click for Settings,
  Pause Hiding / Resume Hiding, Reveal Both Sides, and Quit. Pausing keeps both
  sides visible until hiding is resumed.
- Both sides default to Hover. Settings → General offers a shared Hover/Click
  selector or independent choices. Clicking also works in Hover mode. The left
  arrow stays visible and toggles both ways; while open it sits after the last
  menu (or before the Apple glyph if the menus fill the space up to the notch),
  leaving File and the other native menus clickable.
- Settings → Appearance offers matching Chevron, Arrow, Triangle, Hidden Bar, Dots,
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
- Draplet appears in the Dock while Settings is open, including when minimized.
  Closing Settings returns it to menu-bar-only operation.
- Draplet removes its overlay windows during Mission Control, native fullscreen,
  and foreground fullscreen games that cover the native bar. macOS owns fullscreen
  menus; native right-side icon hiding continues. Desktop curtains return after
  the native bar settles and a fresh background arrives.
- Quit releases the icon-hiding assertion and removes every cover/status item.

Accessibility is required for reading menu geometry and fullscreen window state. Grant it through Settings;
Draplet detects the grant without a restart. Background matching additionally
requires Screen & System Audio Recording access (macOS's name for the permission).
Draplet captures no audio and processes only a narrow menu-bar strip, locally in
memory. It excludes its own covers and other menu-bar overlays. Without capture
access, the left cover waits and right-side hiding uses its native mode. No Input
Monitoring permission, account, subscription or network access is needed.

## Animations and background

Settings → Appearance → Animations defaults to mirrored Curtain reveals, opening inward toward
the notch. Fade is available for both sides. Unlink the sides to choose separately;
Hidden Bar is available only on the right and preserves its native movement/timing.
A shared timing control offers Quick (180 ms reveal / 160 ms hide, the original
left pace) and Relaxed (550 ms / 250 ms, based on measured native right-side motion). Preview
Both Sides demonstrates the selection. The right side prepares native icon layout
behind its cover before revealing, and settles the hidden layout behind the cover
after closing. Reversing a transition cancels stale callbacks; failures release the
cover and reveal the icons. Reduce Motion disables the custom transition.

Settings → Appearance → Menu-bar background offers:

- **Cached** (default): freeze one complete frame from the same rendering stream
  as Live, then stop capturing. This retains native shading that macOS's still
  screenshot API omits. A cheap two-second check compares wallpaper URL/options
  and file metadata. App activation and window changes near the bar also refresh
  it, since those windows contribute shadows. Space/display/wake and appearance
  events refresh it too; the previous image stays visible until its replacement
  is ready. No stream runs while the scene is unchanged. Mission Control frames
  are excluded from the cache.
- **Live**: stream the same strip at up to 30 fps for animated wallpapers. Unchanged
  frames are skipped. This uses more energy; choose it for motion providers that
  keep the same wallpaper URL. Capture pauses during Mission Control. Refresh
  Background is also available manually.

During Mission Control and native fullscreen, macOS owns the bar:
Draplet's title, arrow and right cover stay out of the transition. A game can
cover Menubar with its own status-level window even while AppKit reports that
the menu is visible; foreground ownership, geometry and window level detect
that case. Native fullscreen is read from the foreground window using existing
Accessibility access: foreground polling runs at most four times per second on a
serial queue. Running apps are prewarmed once, and cached fullscreen state is used
before drawing a newly active app's title. The cache is cleared when an app quits.
This requires no screen capture; late responses from the previous app are discarded.
On return, Draplet first waits for a complete desktop frame, then
samples the native bar until its opacity stays unchanged for 100 ms. Native
colors may keep changing for Live wallpapers. The resulting short capture burst
ends once the native bar settles; Cached mode keeps no continuous stream. If the
left menus were collapsed, they close with the selected animation after the
native bar returns.

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
The approved E artwork is retained in `Resources/Brand/IconSource.png`. Its clean
production-alpha export is `Resources/Brand/Draplet.png`; `scripts/make-icon.swift`
resamples that export into a standard iconset. The generated ICNS is checked in.
`prepare-icon.py` is optional asset tooling (Pillow/numpy/scipy); it preserves the
original interior RGB and derives the actual tile contour for its alpha mask.

## Native Settings and local installer

The resizable native Settings window has General, Appearance, Left, Right and
Shortcuts tabs. Shared visual choices live in Appearance; General links reveal
behavior, and Left/Right expose independent actions when unlinked. Changes apply
immediately. Pause Hiding / Resume Hiding and Reveal Both Sides stay available
across tabs. A paused notice explains why both sides remain visible. Icon menus
show each preset's artwork, including imported custom icons. Toolbar tabs have
inset selection backgrounds and full rectangular click targets.
Appearance follows macOS automatically, with warm light/dark surfaces and contrast
checked against real native renders. The small preview is explicitly illustrative;
Preview Both Sides exercises the real menu bar.

```sh
bash scripts/build-dmg.sh
```

The packaging script creates `.build/packaging-venv` and installs pinned dmgbuild
1.6.7 there if needed. It writes `dist/Draplet-0.4.4.dmg`, verifies the image, mounts
it temporarily and verifies the packaged app signature, executable and Applications
shortcut. The approved background is `Resources/Installer/background.tiff`, at 2x
resolution. Finder opens an 800×500 icon view with actual draggable file targets.
The installer is local and signed with the app's existing identity; public release,
notarization and automatic updates are outside this build.

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

`test.sh` runs 117 checks covering LTR/RTL section resolution, protecting the most-visible sibling
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

Mission Control regression checks include actual window suppression and protection
against visibility polling or native transition callbacks bringing a cover back.
The 0.4.2 recorded Cached and Live entry/exit cycles had zero background mismatches
and no cover overlap after a 100 ms entry allowance. The original recording fails both
checks. The pixel fixture is specific to a 1470-point display with a black native
bar; the matching WindowServer trace checks overlay absence while that bar fades.
The user also confirmed clean slow trackpad pauses and reversals in 0.4.2.

Fullscreen regression checks replay the real Minecraft window geometry and the
measured native opacity fade (about 1.2 seconds on the development Mac). Repeating
an unchanged presentation state must not raise a cover above the game. A live
metadata trace verified that the covers remain absent during the game and return
on the desktop. After the diagnostic recording was stopped, the user confirmed
normal brightness and a clean bar after switching back from Minecraft.

Native fullscreen regression checks also replay the captured Fladder state:
AXFullScreen is true while accessory-process menu visibility is true and native
presentation options are zero. The regression fails without the AX input. Tests
cover bounded asynchronous queries, app/Space changes, stale callbacks, startup
prewarming, cached activation and removal of the actual left title and toggle
before the shared activation observer. The user confirmed clean Fladder fullscreen
and desktop return in 0.4.4, then confirmed that build 10 removed the entry title flash.

Read-only window metadata can be collected without recording video:

```sh
swift scripts/overview-window-probe.swift 24 > /tmp/draplet-windows.log
```

`check-overview-video.py` can additionally analyze an existing recording of its
black-bar fixture. The region-recording CLI is omitted here because its interactive
selection can dim the rest of the screen and alter the test environment.

`Reference/` preserves the exact approved prototype and its timed launcher.
See [ThirdPartyNotices.md](ThirdPartyNotices.md) for Hidden Bar attribution.
