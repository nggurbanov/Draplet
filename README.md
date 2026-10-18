# Draplet

<img src="Resources/Brand/Draplet.png" width="96" alt="Draplet app icon">

A free, open-source macOS utility that keeps both sides of your menu bar tidy.
Hide application menus on the left and selected status icons on the right,
then reveal them with a click, a hover, or a keyboard shortcut.

**Early alpha.** Draplet is changing quickly. The current version is 0.4.4.
In-app updates are in development and are not included in this version yet.

## Features

- Hide File, Edit, View and other application menus behind a left-side curtain.
- Hide selected menu-bar icons on the right, with an optional always-hidden section.
- Reveal on hover or click, with shared or independent behavior for each side.
- Curtain and Fade animations, plus a native Hidden Bar mode for the right side.
- Matching or independent indicators, built-in presets and custom image import.
- Cached background matching, or optional Live matching for animated wallpapers.
- A configurable reveal shortcut, auto-hide delay and optional launch at login.
- Native Settings with light and dark appearances. A Dock icon appears while Settings is open.

## Requirements and current limits

- macOS 14 or later. The current development build is tested on macOS 27 with Apple silicon;
  other supported OS versions and Intel Macs still need hardware validation.
- Accessibility access reads menu positions and fullscreen window state.
- Background matching requires Screen & System Audio Recording permission.
  Draplet captures no audio; the menu-bar background is processed locally in memory.
- Left-side hiding is a visual overlay. It does not free space for more status icons.
- macOS owns the menu bar during native fullscreen and Mission Control.
  Draplet withdraws its visual overlays and restores them after the desktop background settles.
- The macOS 27 native icon-hiding backend uses private, dynamically resolved APIs.
  An unavailable backend fails open, leaving icons visible. Future macOS updates may affect it.

## Build and run

Use a Mac with the Xcode command-line tools and a recent macOS SDK:

```sh
git clone https://github.com/nggurbanov/Draplet.git
cd Draplet
bash build.sh
ditto .build/Draplet.app /Applications/Draplet.app
open /Applications/Draplet.app
```

The build uses an available Apple Development signing identity, or ad-hoc signing
if none is available. You can select an identity with `DRAPLET_SIGNING_IDENTITY`.
Public Developer ID signing and notarization are not configured yet.

Enable Draplet in System Settings → Privacy & Security → Accessibility and
Screen & System Audio Recording when prompted. Draplet detects permission changes.

To choose which icons hide, hold ⌘ and drag Draplet's right arrow to the right of
the icons you want hidden. macOS remembers the arrangement. With an always-hidden
section, place its dotted divider to the left of the arrow. ⌥-click reveals all sections.

The default shortcut is ⌃⌥Space. Settings provides alternatives.
Quit Hidden Bar before using Draplet's right-side hiding; both manage the same icons.

## Create a local DMG

```sh
bash scripts/build-dmg.sh
```

This builds a drag-to-Applications image in `dist/`, verifies its checksum, mounts it,
and checks the packaged app signature, executable and Applications shortcut.
The packaging environment is isolated under `.build/`.

Downloaded alpha builds may require an explicit Open Anyway approval in macOS.
Do not disable Gatekeeper or other system protections globally.

## Development and validation

```sh
bash test.sh
```

The current suite has 117 checks covering icon layout, preferences, rendering,
transition cancellation, native-engine lifecycle, fullscreen detection and overlay ordering.
Captured, minimized window-state fixtures cover the Minecraft and Fladder regressions.
Passing these checks is not a substitute for testing gestures and fullscreen on real hardware.

The UI is SwiftUI and AppKit. `Sources/LeftCurtain.swift` owns the left overlay;
`Sources/RightCurtain.swift` integrates icon hiding and right transitions;
`Sources/MenuBarBackdrop.swift` handles Cached/Live backgrounds.
`Sources/SystemPresentation.swift` and `Sources/ForegroundFullscreen.swift` coordinate
fullscreen and Mission Control suppression. Settings is in `Sources/Settings.swift`.

Cached mode stops capturing once a complete background is ready and refreshes on
relevant desktop changes. Live mode follows animated backgrounds. Fullscreen detection
uses window metadata and bounded Accessibility queries, without continuous screen capture.

Please report issues with the Draplet version, macOS version, display arrangement,
background mode and a short reproduction. Remove personal information from screenshots
and logs before sharing them. There is no automatic telemetry or crash-log upload.

## License and acknowledgments

Draplet is [MIT licensed](LICENSE).
Right-side hiding includes code from [Hidden Bar](https://github.com/dwarvesf/hidden)
by Dwarves Foundation, also under MIT. The "Hidden Bar" indicator preset retains its
original artwork as an homage. See [ThirdPartyNotices.md](ThirdPartyNotices.md)
and [Vendor/HiddenBar/LICENSE](Vendor/HiddenBar/LICENSE).
