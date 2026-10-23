# Draplet schematic demo

The README's 18-second animation is authored in Remotion. All visible UI,
wallpaper, status glyphs and cursor are vectors in `src/Composition.tsx`.
Contents and status publishers are fictional. There are no screen captures,
personal data, remote images, downloaded fonts or analytics. This is an
illustration, not footage or verification of the native app.

## Preview

From the repository root, use a Node version satisfying `package.json`:

```sh
cd media/demo
npm ci
npm run dev
```

Remotion and its CLI are locked to 4.0.538. Studio opens at
http://localhost:3427/DrapletDemo without launching a browser automatically.
For a remote development host, forward port 3427 through SSH.

The composition is 1440 × 600, 30 fps and 540 frames. Scrub or play the Studio
timeline; the accent color is editable in composition props. Animation is
frame-driven, with no CSS animations, wall-clock timers or network assets.
System-font metrics can vary between preview and export hosts.

## Storyboard

- 0–3.5s: left arrow reveals and collapses application menus.
- 3.5–5s: right accordion reveals status icons and the leftmost Pocket arrow.
- 5–8s: Command-drag the terracotta star into the temporary Pocket target.
- 8–10.9s: open Pocket and pick up the pinned star with Command held.
- 10.9–13.6s: return the star to the menu bar, then dismiss Pocket.
- 13.6–18s: collapse the right strip and restore the initial frame.

Command remains held through release. The normal Pocket control appears only
with an expanded right strip; the incoming drag target is a separate temporary
surface. The same star represents the fictional status item throughout.

## Export

Install `ffmpeg` with libx264 support and a browser usable by Remotion, then run
from this directory:

```sh
npm run lint
bash export.sh
```

The script renders a temporary lossless PNG sequence before encoding:

- `out/draplet-demo.mp4`: 1440 × 600, 30 fps, H.264/yuv420p, CRF 18, faststart.
- `out/draplet-demo.gif`: 1080 × 450, 20 fps, palette-optimized, infinite loop.

Both are 18 seconds. Intermediate frames are removed on exit and existing output
files are overwritten. Dependencies, caches and exports are ignored by Git.
The GIF is encoded directly from lossless frames, not the compressed MP4.

Before publishing an edited animation, check normal-speed playback, both drops,
Command release and the last-to-first transition. The published version's decoded
GIF endpoints match exactly. Static frames and policy checks do not establish
native hardware drag acceptance. The root README identifies the scene as schematic.

## Published assets and design

The approved exports live in `docs/assets/` at the repository root. The Studio
source and authored artwork are GPL v3 as part of Draplet.

This scene extends the product's warm neutral / terracotta identity. Its stage,
fictional wallpaper and timing are media-specific choices, not native app tokens.
The root PRODUCT.md, DESIGN.md and `.impeccable/design.json` remain authoritative
for the application. This source does not alter its hiding engines or updater.
