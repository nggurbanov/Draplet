# Schematic README demo

Mode: Experience. Code-led, explicitly approved 18-second schematic menu-bar loop.
Inherit Draplet's warm neutral / terracotta identity and native macOS visual
language. This is an illustrative vector animation, never a screen recording or
an app-verification artifact. Do not copy personal desktop data, app inventory,
notifications, wallpaper or screen captures into the scene.

Composition: 1440 × 600 at 30 fps; frame-driven movement, no remote assets or
wall-clock animation. Generic Notes window and authored icons supply fictional
content. Preserve the native horizontal disclosure and leftmost expanded-only
Pocket control. The incoming drag target is a distinct temporary surface.

Sequence: left disclosure reveal/collapse; right accordion reveal; Command-drag
one terracotta star into Pocket; open Pocket; Command-drag the same star back to
the bar; collapse; return to the initial frame. Show Command held through release,
leave readable pauses at both drops, and keep the same star identifiable.
No marketing headline, extra feature claims or unrelated UI redesign.

Source and reproducible preview instructions live in media/demo. Keep dependency
and generated output directories on the development host. Review the animation before adding
final media to the public README. App code, release assets and updater stay fixed.

## Reproducibility and review boundary

`media/demo/package-lock.json` locks dependencies; Remotion and its CLI are pinned
to 4.0.538. Studio uses port 3427. See `media/demo/README.md` for installation,
SSH forwarding, preview and export instructions. `export.sh` renders a lossless
PNG intermediate before encoding the 1440 × 600 / 30 fps MP4 and optimized
1080 × 450 / 20 fps infinite-loop GIF. Publication remains separate from source
preparation.

Review disposition: narrow SHIP after resolving the target name, duplicated
glyph, star flash and collapsed-arrow gap. The target names the fictional status
item “Star”. Local review references in the Mac checkout are
`.build/draplet-demo-storyboard-final.png` and
`.build/draplet-demo-review-final.tsx`. They are private review artifacts, not
inputs to the animation or publication assets. Static captures do not prove
subjective playback smoothness. Review the full encoded loop and last-to-first
transition before adding final media to the public README. Native app behavior
and physical Command-drag acceptance require their own evidence.

This is a media extension of the incumbent identity. Scene colors, shadows,
stage and timing are local illustration choices, not additions to the native
app's design system. Preserve `PRODUCT.md`, `DESIGN.md`, the design sidecar,
app code, release artwork, release assets and updater.
