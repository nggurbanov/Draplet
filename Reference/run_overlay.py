"""Run the temporary native hover-to-reveal overlay, with a bounded lifetime."""
import argparse
import pathlib
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--duration", type=int, default=180)
parser.add_argument("--mode", choices=("fixed", "geometry"), default="fixed")
args = parser.parse_args()
duration = min(600, max(15, args.duration))
root = pathlib.Path(__file__).resolve().parent
output = pathlib.Path(tempfile.mkdtemp(prefix="menu-overlay-"))
binary = output / "MenuOverlay"
subprocess.run([
    "swiftc", "-swift-version", "5", "-module-cache-path",
    str(pathlib.Path(tempfile.gettempdir()) / "codex-swift-module-cache"),
    str(root / ("MenuOverlayFixed.swift" if args.mode == "fixed" else "MenuOverlay.swift")), "-o", str(binary),
], check=True, timeout=60)
print(f"Overlay evidence: {output}", flush=True)
print("Commands: status, pause, resume, reveal, collapse, quit", flush=True)
process = subprocess.Popen([str(binary), str(duration), str(output)])
try:
    process.wait(timeout=duration + 10)
except subprocess.TimeoutExpired:
    print("Safety deadline reached; stopping the temporary overlay.", flush=True)
finally:
    if process.poll() is None:
        process.terminate()
        process.wait(timeout=5)
