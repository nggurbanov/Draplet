#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
command -v ffmpeg >/dev/null
mkdir -p out
frames=$(mktemp -d "$PWD/out/frames-XXXXXX")
trap 'rm -rf "$frames"' EXIT
npx remotion render DrapletDemo "$frames" --sequence --image-format=png --concurrency=2
ffmpeg -v error -y -framerate 30 -pattern_type glob -i "$frames/*.png" \
  -c:v libx264 -crf 18 -pix_fmt yuv420p -movflags +faststart out/draplet-demo.mp4
ffmpeg -v error -y -framerate 30 -pattern_type glob -i "$frames/*.png" \
  -filter_complex '[0:v]fps=20,scale=1080:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle' \
  -loop 0 out/draplet-demo.gif
