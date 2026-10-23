# Draplet

<!-- impeccable:product-schema 1 -->

## Platform
Native macOS desktop utility (SwiftUI and AppKit; macOS-specific, not a web or iOS app).

## Users and purpose
A daily-use, free and open-source menu-bar utility. Hide application menu headings on the left and selected status icons on the right, then reveal either side or both on demand.

## Capabilities and constraints
Preserve independent/shared icons, custom image import, hover/click reveal, Curtain/Fade and right-only native Hidden Bar animations, both animation paces, automatic right-side hiding, always-hidden section, extra room option, global shortcut and login registration. Preserve Accessibility and screen-capture permission guidance, cached/live background matching and graceful failure. The native hiding/reveal engines and recent rapid-toggle flash fixes are working behavior, not a redesign target.

## Pocket
The original horizontal arrow retains accordion reveal in the native menu bar.
Pocket's separate down/up chevron appears only while that right strip is expanded
and is always leftmost, before every visible right status icon. It replaces
native overflow's leading slot; a fitting pins-only layout uses verified empty
space before the first physical status slot. With Curtain selected, Pocket and
the icons reveal together under the existing mirrored curtain at the selected
pace, without an isolated early chevron or all-at-once icon replacement.
Collapsing immediately hides the control, and late scans cannot restore it.
Saved pins are reached by expanding the original horizontal arrow. With neither
overflow nor eligible running pinned items, no Pocket control is shown.

Automatic overflow includes exact nonfitting items from a readable host; an
unavailable host creates no automatic membership. Pins persist by bundle
identifier and remain separate from overflow. The macOS 27 native backend groups
all status icons from one pinned app. Individually hosted items such as Spotlight
require a verified distinct owner; shared system controls and input agents remain
excluded. Settings and item context menus provide Keep in Pocket / Return to
Menu Bar. Command-drag into Pocket pins a real status item's app; its genuine-drag
target can open independently of strip expansion. Command-drag back to the menu
bar removes the pin and restores the original section subject to available space.
Ordinary clicks invoke the actual native action. Physical Command-drag acceptance
remains separate from implemented gesture guards and automated policy checks.

The user's macOS emoji-picker reference governs this surface: a much smaller
downward-opening native popover with a top pointer, translucent material and a
dense glyph grid. Keep native logical image size, native monochrome tint and
original colors for colored imagery. Application artwork is not a substitute.
No launcher header, permanent captions or footer. The drag target names the actual
status item, such as Spotlight. Reuse the last-good real glyph while a refresh
waits or fails; keep its native action clickable. Never replace it with app
artwork. Items explicitly disallowed by macOS Control Center are excluded from
capture while their pins stay saved.

Keep a local persistent cache bounded to 128 records. A 120-second soft age makes
images eligible for idle refresh; failures back off for 30, 120, 600 and then 3600
seconds. Display changes preserve pixels, and normal quit drains pending writes.
Safe collapsed prewarming uses a matched prefix shield ending before the original
arrow and system controls. New imagery can still require first foreground capture
when native hidden capacity is insufficient. A matching verified layout bypasses
the repeated 300 ms warm settling delay; native activation is still awaited and
the cold preparation path remains.

The expanded strip, Pocket button and popover share pointer retention. Auto-hide
waits the configured delay, five seconds by default, after leaving all three and
resets on re-entry. Native menus, capture, actions and drags hold reveal. Preserve
fullscreen suppression, cancellation and bounded local glyph capture. Ice reuse and
GNU GPL v3 remain approved. See .impeccable/pocket-brief.md and
docs/RELEASE_READINESS.md for current evidence and its limits.

## Brand commitments
Draplet variant E: asymmetric terracotta curtain on the left, two ivory rings on a chocolate rail and three exposed chocolate dots. Production artwork lives under Resources/Brand and Resources/Installer. Settings concepts establish warm ivory/charcoal surfaces, restrained terracotta accents, native controls and compact navigation. User explicitly clarified that their exact layout is not binding; choose the best actual UI/UX patterns using Impeccable.

## Delivery
Implement native Settings and production icon; prepare and verify a local drag-to-Applications DMG. Public source publication to nggurbanov/Draplet is authorized. Paid signing and notarization are not authorized. In-app updates are approved with a single feed, automatic checks and persistent install reminders; no channels. Keep the current app signing identity and bundle identifier for existing permissions.

## Product principles
- A quiet everyday utility; Settings should make each task obvious.
- Shared choices have one source of truth; independent choices remain easy to find.
- Explain permissions where they matter and show recovery actions.
- Brand texture belongs in artwork; controls use familiar macOS conventions.

## Open decisions
No final preferred pace was selected. Retain the user's current choice and both available timings.
