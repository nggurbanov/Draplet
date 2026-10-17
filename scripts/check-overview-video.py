#!/usr/bin/env python3
"""Pixel regression for a 1470-point menu-bar recording with a black native bar.

Record with: screencapture -v -V 24 -R0,0,1470,80 clip.mov
This fixture checks transition contamination, not general wallpaper matching.
Requires ffmpeg; it does not change macOS appearance or drive the UI.
"""
import argparse
import json
from pathlib import Path
import statistics
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("video")
parser.add_argument("--window-log", type=Path,
                    help="Matching overview-window-probe.swift trace; checks covers while the native bar fades")
args = parser.parse_args()
process = subprocess.Popen([
    "ffmpeg", "-v", "error", "-i", args.video,
    "-vf", "crop=iw:64:0:0,fps=60,scale=1470:32:flags=neighbor",
    "-f", "rawvideo", "-pix_fmt", "rgb24", "-",
], stdout=subprocess.PIPE)
assert process.stdout is not None
size = 1470 * 32 * 3
frames = native_frames = 0
bad = []
runs = []

def background(frame, start, end):
    return tuple(statistics.median(frame[(28 * 1470 + x) * 3 + c]
                                   for x in range(start, end, 5)) for c in range(3))

while True:
    frame = process.stdout.read(size)
    if not frame:
        break
    if len(frame) != size:
        raise SystemExit("Incomplete video frame")
    native = background(frame, 1240, 1425)
    desktop = max(native) <= 4
    if not runs or runs[-1][0] != desktop:
        runs.append([desktop, frames, 0])
    runs[-1][2] += 1
    if desktop:
        native_frames += 1
        left = background(frame, 400, 600)
        right = background(frame, 950, 1100)
        difference = max(abs(a - b) for sample in (left, right) for a, b in zip(sample, native))
        if difference > 8:
            bad.append({"seconds": round(frames / 60, 4), "difference": difference})
    frames += 1
if process.wait() != 0 or native_frames < 30:
    raise SystemExit("Recording failed or does not contain the opaque black bar fixture")
phases = [run[0] for run in runs if run[2] >= 30]
if not any(phases[i:i + 3] == [True, False, True] for i in range(len(phases) - 2)):
    raise SystemExit("Recording must contain desktop, overview and desktop again; no complete transition found")
result = {"frames": frames, "black_native_frames": native_frames,
          "phases": [{"desktop": state, "start": round(start / 60, 4), "frames": count}
                     for state, start, count in runs if count >= 30],
          "mismatched_frames": len(bad), "first_mismatches": bad[:12]}
overlap = []
if args.window_log:
    events = []
    for line in args.window_log.read_text().splitlines():
        seconds, rows = line.split(" ", 1)
        rows = json.loads(rows)
        overview = any(row["owner"] == "Dock" and 18 <= row["layer"] <= 20
                       and row["frame"].get("Width", 0) >= 1462
                       and row["frame"].get("Height", 0) >= 948 for row in rows)
        covers = sum(row["owner"] == "Draplet" and row["layer"] == 25 for row in rows)
        events.append((float(seconds), overview, covers))
    entry = hidden = None
    cycles = []
    for index, (seconds, overview, covers) in enumerate(events):
        if overview:
            if entry is None:
                entry = seconds
            if not covers and hidden is None:
                hidden = seconds
            # Allow the 50 ms monitor one turn plus WindowServer observation
            # latency. Any later return while the overview exists is a failure.
            if covers and index + 1 < len(events):
                end = events[index + 1][0]
                start = max(seconds, entry + 0.1)
                if end > start:
                    overlap.append({"start": round(start, 4), "seconds": round(end - start, 4)})
        elif entry is not None:
            cycles.append({"start": entry, "end": seconds,
                           "suppression_ms": round(1000 * (hidden - entry), 1) if hidden is not None else None})
            entry = hidden = None
    if not cycles or entry is not None:
        raise SystemExit("Window trace must contain a complete overview entry and exit")
    result["overview_cycles"] = cycles
    result["cover_overlap_after_entry_grace"] = overlap
print(json.dumps(result, indent=2))
raise SystemExit(bool(bad or overlap))
