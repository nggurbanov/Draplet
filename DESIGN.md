---
name: Draplet native Settings
description: A quiet daily macOS utility with warm surfaces and restrained terracotta accents.
colors:
  accent-light: "rgb(72% 25% 10%)"
  accent-dark: "rgb(94% 49% 30%)"
  control-tint: "rgb(62% 20% 7.5%)"
  secondary-light: "rgb(39% 38% 36%)"
  secondary-dark: "rgb(69% 68% 66%)"
  background-light: "rgb(97.5% 96.5% 94.5%)"
  background-dark: "rgb(12.5% 12% 11.5%)"
  surface-light: "rgb(95% 94% 92.5%)"
  surface-dark: "rgb(17% 16.5% 16%)"
typography:
  title:
    fontFamily: SF system
    fontSize: 25pt
    fontWeight: 700
  body:
    fontFamily: SF system
    fontSize: 14pt
  section:
    fontFamily: SF system
    fontSize: 13pt
    fontWeight: 600
  secondary:
    fontFamily: SF system
    fontSize: 12pt
  annotation:
    fontFamily: SF system
    fontSize: 11pt
rounded:
  group: 9pt
  preview: 8pt
  navigation: 7pt
  icon-preview: 5pt
spacing:
  label-group: 8pt
  row-vertical: 11pt
  row-detail-vertical: 13pt
  row-horizontal: 16pt
  section: 20pt
  content: 26pt
components:
  settings-group-light:
    backgroundColor: "{colors.surface-light}"
    rounded: "{rounded.group}"
  settings-group-dark:
    backgroundColor: "{colors.surface-dark}"
    rounded: "{rounded.group}"
  menu-bar-preview:
    rounded: "{rounded.preview}"
    height: 38pt
  toolbar-tab:
    rounded: "{rounded.navigation}"
    height: 42pt
---

# Design System: Draplet

## Overview

**Creative North Star: "A quiet daily macOS utility"**

Warm ivory and charcoal surfaces carry compact, familiar controls. The approved variant E artwork owns the brand: an asymmetric terracotta curtain, two ivory rings on a chocolate rail and three exposed chocolate dots. Its texture belongs in the icon and installer artwork; Settings use native AppKit chrome and SwiftUI controls.

The approved PNGs under `../art/draplet-e` establish palette and character. The user explicitly loosened exact layout fidelity and delegated effective native UI/UX to Impeccable. They are style references for Settings, not a composition or state-fidelity contract.

**Key Characteristics:**

- Warm, restrained and compact.
- Native controls and standard macOS window behavior.
- Clear shared choices with independent controls when needed.
- Immediate settings changes with visible permission recovery.

## Colors

Terracotta marks interaction against warm neutrals; the frontmatter preserves the source sRGB channel values without hex rounding.

### Primary

- **Terracotta text accent** uses `accent-light` or the lighter `accent-dark` for selected navigation text, actions and switch tint.
- **Deep terracotta fill** uses the appearance-independent `control-tint` for filled native segmented controls. Their white selected labels need this darker fill even in dark appearance.

### Neutral

- **Warm ivory / charcoal background** uses the paired `background` tokens for the window and content.
- **Inset ivory / charcoal surface** uses the paired `surface` tokens for groups and the preview.
- **Warm secondary label** uses the paired `secondary` tokens for descriptions, section labels, annotations and status. Primary labels retain the native primary label color.
- Group outlines use native primary at 9% opacity; the preview outline uses 12%. Dividers remain native.

**The Two Terracottas Rule.** Text/switch accent and filled-control tint serve different contrast needs. Do not replace the darker segmented-control fill with the brighter dark-mode text accent.

The recorded contrast review measured selected navigation text at 6.91:1 in dark appearance and 7.62:1 in light appearance; secondary text was at least 5.43:1 across the reviewed surfaces.

## Typography

**Display Font:** SF system. **Body Font:** SF system. Native controls retain their platform text behavior.

The hierarchy is compact and legible: `title` for page titles, `body` for rows, `section` for semibold group labels, `secondary` for descriptions and toolbar tab labels, and `annotation` for preview notes. Toolbar symbols are regular 20-point SF Symbols; the toolbar brand label is 16-point semibold. The auto-hide value and preview clock use monospaced digits.

## Layout

One unified native toolbar contains the brand, five tabs in order—General, Appearance, Left, Right, Shortcuts—and Pause Hiding / Resume Hiding. Appearance is the initial page. Tab controls are 42 points high inside 54-point hosts, leaving 6 points of vertical padding; Appearance is 88 points wide and the other tabs are 64 points wide. Padding must fit inside the native toolbar height, rather than enlarge the custom host and get clipped. A rectangular content shape makes each whole tab clickable. Native toolbar item glass backgrounds are explicitly disabled with `isBordered = false` after custom view assignment; the only persistent tab selection surface is the app's low-opacity terracotta treatment.

The window opens with 940 × 710 points of content and saves its frame. Its AppKit minimum is 850 × 700 points; the SwiftUI content also declares an 830 × 620 minimum. The window is resizable. A vertical `ScrollView` lets longer pages and independent settings extend naturally; the footer stays outside scrolling content. Resize and scroll provide room rather than shrinking text or hiding controls. Opening Settings adds Draplet to the Dock; minimizing keeps it there, and closing removes it. Full-width right-side reveal borrows focus without changing that Dock policy.

Content uses the `content` inset and `section` gap. Rows place labels and wrapping detail at the left, controls at the right, using `row-horizontal` padding and the relevant vertical token. Rows have a 42-point minimum height. The footer uses 24-point horizontal and 11-point vertical padding.

- **General:** login, shared reveal behavior, permissions, About and Quit.
- **Appearance:** preview, same/independent icons and animations, custom import/removal, both paces and cached/live background matching.
- **Left:** enable switch, linked or independent reveal action and native-menu guidance.
- **Right:** enable/status/arrangement, reveal action, auto-hide delay, always-hidden section and extra room.
- **Shortcuts:** global reveal binding and contextual menu-bar gestures.

## Elevation & Depth

Settings use flat tonal grouping, subtle borders and native separators. Groups and previews add no custom shadow. Standard macOS chrome, focus, hover and disabled rendering remain native; textured depth stays in the approved artwork.

## Shapes

Soft group, preview, navigation and icon-preview corners use their frontmatter tokens. Group outlines are one point. Controls keep native shapes instead of receiving a custom component skin. Standard traffic lights and the unified transparent titlebar remain visible.

## Components

### Navigation

The selected tab uses appearance-aware accent text and a 12%-opacity accent surface, with selected accessibility semantics. Unselected tabs use native primary text. Native toolbar chrome must not add a second persistent background around these custom tab views.

### Groups and rows

A semibold section label sits above each rounded tonal group. Rows use native switches, pickers, sliders and buttons. Supporting descriptions wrap vertically. There is no Save action; changes apply immediately.

### Shared and independent choices

“Use the same icon on both sides” exposes one shared icon row or separate left/right rows. The same pattern governs animations. Shared reveal action lives in General; linked side rows show their current action and a Change button back to General. Independent reveal actions are editable on Left and Right. Custom icon rows show the selected images, Import Custom and a removal action when an image exists.

### Segments, sliders and actions

Filled segments use `control-tint`; switches and action text use the adaptive accent. Animation options preserve Curtain/Fade and the right-only native Hidden Bar choice. Quick preserves 180 ms reveal / 160 ms hide; Relaxed preserves 550 ms reveal / 250 ms hide. Keep the user's current pace. The auto-hide slider spans 1–30 seconds in one-second steps, with a visible numeric value.

### Menu-bar preview

The explicitly labeled preview uses sample Finder menus and a 9:41 clock. Its arrows change only the preview layout. “Preview Both Sides” invokes the real utility; “Reveal Both Sides” stays available in the footer. Appearance, Left and Right include the preview.

### Permissions and status

Permission rows show actual state and recovery actions. Background preparation and failure states appear where relevant, with progress or retry. Pause Hiding / Resume Hiding stays in the toolbar, with a tooltip explaining that both sides remain visible until resumed. A visible paused notice repeats that effect and offers Resume Hiding. Native icon pop-up menus include artwork in every choice and the selected item, including imported custom artwork.

### Delivery artwork and review

The icon and drag-to-Applications installer retain approved variant E. Final native captures are `.impeccable/review/appearance-dark-final.png`, `.impeccable/review/appearance-light-final.png` and `.impeccable/review/installer.png`.

**Reviewer disposition: SHIP.** The final captures show the implemented light/dark palette, clear selection and the intended installer arrangement. The implementation review records 69 passing checks plus native source/screenshot and manual settings validation for linked/independent choices, custom icon import/removal, the slider and Pause/Resume. The HTML/CSS detector was not run because this is native SwiftUI/AppKit. This disposition covers the reviewed local Settings/icon/installer work; it does not claim a public release, paid signing or notarization.

**0.4.1 refinement verification:** 75 checks pass, including the real Settings window's open, minimize, close and reopen Dock lifecycle. Native UI checks confirmed the top inset in both appearances, navigation through a tab's blank corner, icon artwork and selection, and the explanatory paused notice. A Mission Control capture plus WindowServer inventory confirmed that all three overlay windows leave the screen during the overview and return afterward. Full-width reveal still brings Draplet's short menu forward with Settings closed, without adding a Dock icon. The local DMG's mounted app signature, executable and Applications shortcut were verified again.

**0.4.2 transition refinement:** Slow-gesture screenshots exposed intermediate frames that the fully open 0.4.1 overview check missed. All three overlay windows are now explicitly removed for the Dock overview's lifetime; AppKit's transient fading alone is insufficient. Background capture pauses, rejects stale callbacks and retains the last good image. Presentation resumes only after a fresh native treatment and desktop frame arrive, then the left menus close with the selected animation if previously collapsed. There are 88 passing checks, including real window-ordering checks. Recorded Cached and Live cycles show zero black-bar background mismatches and zero cover overlap after the 100 ms entry allowance; the pre-fix recording fails both diagnostics. Slow trackpad pauses and reversals remain a separate hardware verification, pending user feedback.

## Do's and Don'ts

### Do:

- **Do** use the final appearance-specific text and secondary colors from the frontmatter.
- **Do** use the darker control tint for filled segmented controls in both appearances.
- **Do** retain native keyboard focus, accessibility semantics and control states.
- **Do** let the window resize and longer pages scroll while keeping the footer available.
- **Do** distinguish illustrative preview interactions from real menu-bar actions.

### Don't:

- **Don't** treat the approved Settings concepts as an exact layout contract.
- **Don't** add duplicate toolbar backgrounds around the custom navigation views.
- **Don't** place artwork textures or decorative dashboard chrome in Settings forms.
- **Don't** change the native hiding engines, menu-bar window behavior or timing constants as part of visual polish.
