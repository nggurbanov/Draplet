#!/usr/bin/env python3
"""Native regression: return an unsupported extra without moving its publisher.

The source must be the single CompatibilityFixture, bundled as
org.drapletqa.native under ~/Applications. This script does not synthesize a
hardware gesture; Draplet's existing fixture hook exercises its real cell and
return controller. Native menu delegate callbacks observe actual activation.
"""
import argparse
import importlib.util
import json
import plistlib
import subprocess
import time
import base64
import datetime
import hashlib
import re
from pathlib import Path

spec = importlib.util.spec_from_file_location("native_qa", Path(__file__).with_name("qa-native.py"))
assert spec is not None and spec.loader is not None
qa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)
parser = argparse.ArgumentParser()
parser.add_argument("--fixture", type=Path, required=True)
parser.add_argument("--report", type=Path, required=True)
parser.add_argument("--expect-old-failure", action="store_true")
parser.add_argument("--review-seconds", type=int, default=0)
args = parser.parse_args()
args.report.mkdir(parents=True, exist_ok=True)
observer = args.report / "observer"
subprocess.run(["xcrun", "swiftc", "Tests/Native/CompatibilityObserver.swift", "-o", str(observer)], check=True)
source = args.fixture.resolve()
assert source.parent == Path.home() / "Applications", "The regression needs a publisher outside /Applications"
assert plistlib.loads((source / "Contents/Info.plist").read_bytes())["CFBundleIdentifier"] == "org.drapletqa.native"
normal_pid_file = Path(".build/membership43/normal.pid")
normal_pid = int(normal_pid_file.read_text())
assert subprocess.check_output(["ps", "-p", str(normal_pid), "-o", "comm="], text=True).strip() == "/Applications/Draplet.app/Contents/MacOS/Draplet"
before = plistlib.loads(subprocess.check_output(["defaults", "export", "com.tyrell.Draplet", "-"]))
subprocess.run(["kill", "-TERM", str(normal_pid)], check=True)
time.sleep(0.3)
app = fixture = None
def launch_app():
    return qa.Controls(Path("/Applications/Draplet.app/Contents/MacOS/Draplet"), args.report / ("app.log" if app is None else "relaunch.log"),
                       "--test-controls", "--qa-no-reopen", "--qa-hold-pocket", "-autoCollapse", "NO")
def physical(identifier):
    assert fixture is not None
    return json.loads(subprocess.check_output([str(observer), identifier, str(fixture.process.pid)], text=True))
def wait_physical(identifier, visible):
    # NSStatusItem.isVisible crosses into MenuBarAgent asynchronously. Wait for
    # the independent AX host to publish that change, rather than treating its
    # first stale row as pixels which survived the native visibility change.
    deadline = time.monotonic() + 2
    last = None
    while time.monotonic() < deadline:
        last = physical(identifier)
        if bool(last["proxyFrames"]) == visible: return last
        time.sleep(.06)
    raise AssertionError(("Native status visibility did not settle",visible,last))
cache_key = "org.drapletqa.native|slot:0/1"
cache_file = Path.home() / "Library/Caches/com.tyrell.Draplet/Pocket-v1" / (hashlib.sha256(cache_key.encode()).hexdigest() + ".plist")
old_cache = cache_file.read_bytes() if cache_file.exists() else None
try:
    fixture = qa.Controls(source / "Contents/MacOS/StatusFixture", args.report / "source.log")
    fixture.send("window"); fixture.wait(lambda state: state["window"])
    # Isolate return from image acquisition. Seed only our disposable fixture's
    # cache with the image exported by its actual NSStatusBarButton publisher.
    # This does not stand in for Pocket's separate screenshot/glyph tests.
    ink = fixture.request("image")
    assert "png" in ink, ink
    cache_file.parent.mkdir(parents=True, exist_ok=True)
    cache_file.write_bytes(plistlib.dumps({"key": cache_key, "png": base64.b64decode(ink["png"]), "width": ink["width"],
                                          "height": ink["height"], "template": True, "pid": fixture.process.pid,
                                          "scale": ink["scale"], "captured": datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), "failures": 0}))
    app = launch_app()
    app.wait(lambda state: state["backgroundReady"] and not state["systemPresentationSuspended"], timeout=25)
    app.send("expand")
    app.wait(lambda state: state["pocket"]["buttonVisible"] and not state["rightAnimation"]["transitioning"], timeout=15)
    app.send("pocket")
    opened = app.wait(lambda state: state["pocket"]["visible"] and not state["pocket"]["busy"], timeout=25)
    assert "Draplet Compatibility Fixture" in opened["pocket"]["names"], opened
    arrow_before = physical("Draplet.Toggle")
    (args.report / "arrow-before.json").write_text(json.dumps(arrow_before))
    app.send("qa-pocket-return-overflow-fixture")
    returned = app.wait(lambda state: state["pocket"].get("lastReturn") in ("returned", "failed", "cancelled")
                        and not state["pocket"]["busy"], timeout=18)
    (args.report / "return.json").write_text(json.dumps(returned, indent=2))
    if args.expect_old_failure:
        assert returned["pocket"]["lastReturn"] == "failed", returned
        print("Reproduced: native-only return fails for the publisher in ~/Applications", flush=True)
    else:
        assert returned["pocket"]["lastReturn"] == "returned", returned
        state = app.wait(lambda state: len(state["pocket"].get("compatibility", [])) == 1, timeout=8)
        identifier = state["pocket"]["compatibility"][0]["identifier"]
        observed = physical(identifier)
        assert len(observed["proxyFrames"]) == 1 and not observed["originalRendered"], observed
        (args.report / "physical.json").write_text(json.dumps(observed, indent=2))
        arrow = physical("Draplet.Toggle")
        (args.report / "arrow-after.json").write_text(json.dumps(arrow))
        assert len(arrow["proxyFrames"]) == 1, arrow
        slot = [float(value) for value in re.findall(r"-?\d+(?:\.\d+)?", observed["proxyFrames"][0])]
        boundary = [float(value) for value in re.findall(r"-?\d+(?:\.\d+)?", arrow["proxyFrames"][0])]
        assert slot[0] + slot[2] / 2 < boundary[0] + boundary[2] / 2, "Returned mirror landed on the always-visible side after native restoration"
        prior_boundary = [float(value) for value in re.findall(r"-?\d+(?:\.\d+)?", arrow_before["proxyFrames"][0])]
        assert abs(boundary[0] - prior_boundary[0]) < 1, ("Return moved the user's disclosure",prior_boundary,boundary)
        app.send("qa-compatibility-click-fixture")
        fixture.wait(lambda state: state["openMenus"] == 1, timeout=6)
        fixture.send("cancel-menu"); fixture.wait(lambda state: state["openMenus"] == 0)
        print("Passed: compatible status control opens the original publisher menu", flush=True)
        if args.review_seconds:
            print("Visual review ready", flush=True)
            time.sleep(min(max(0,args.review_seconds),30))
        for _ in range(3):
            app.send("collapse")
            app.wait(lambda state: state["right"] == "Hidden" and not state["rightAnimation"]["transitioning"])
            assert not wait_physical(identifier,False)["proxyFrames"], "A hidden-section mirror remained visible"
            app.send("expand")
            app.wait(lambda state: state["right"] == "Expanded" and not state["rightAnimation"]["transitioning"])
            app.wait(lambda state: "Draplet Compatibility Fixture" not in state["pocket"]["overflow"], timeout=10)
            assert len(wait_physical(identifier,True)["proxyFrames"]) == 1, "Expanded mirror is absent from the physical bar"
        print("Passed: three accordion cycles preserve the native slot and Pocket membership", flush=True)
        app.close(); app = launch_app()
        app.wait(lambda state: state["backgroundReady"] and not state["systemPresentationSuspended"], timeout=25)
        app.send("expand")
        app.wait(lambda state: state["right"] == "Expanded" and not state["rightAnimation"]["transitioning"]
                 and len(state["pocket"].get("compatibility", [])) == 1, timeout=15)
        assert len(physical(identifier)["proxyFrames"]) == 1, "Relaunch lost the compatibility slot"
        print("Passed: restart restores the captured glyph and the native status item", flush=True)
        fixture.send("image-two")
        old_ink = plistlib.loads(cache_file.read_bytes())
        app.send("qa-compatibility-refresh-fixture")
        app.wait(lambda state: state["pocket"].get("captureRequests", 0) > 0, timeout=8)
        app.wait(lambda state: not state["pocket"]["busy"], timeout=18)
        new_ink = plistlib.loads(cache_file.read_bytes())
        assert new_ink["captured"] > old_ink["captured"] and new_ink["png"] != old_ink["png"], "Explicit refresh did not acquire the changed publisher icon"
        (args.report / "refreshed.png").write_bytes(new_ink["png"])
        print("Passed: explicit refresh captures a changed publisher glyph without streaming", flush=True)
        app.send("pin:org.drapletqa.native")
        app.wait(lambda state: not state["pocket"].get("compatibility"))
        assert not physical(identifier)["proxyFrames"], "Re-pinning left a duplicate status item"
        print("Passed: re-pinning removes the compatibility slot", flush=True)
        app.send("expand")
        app.wait(lambda state: state["pocket"]["buttonVisible"] and not state["rightAnimation"]["transitioning"], timeout=15)
        app.send("pocket")
        app.wait(lambda state: state["pocket"]["visible"] and not state["pocket"]["busy"], timeout=20)
        app.send("qa-pocket-return-fixture")
        app.wait(lambda state: state["pocket"].get("lastReturn") == "returned" and not state["pocket"]["busy"], timeout=20)
        assert len(physical(identifier)["proxyFrames"]) == 1, "Pinned return failed to restore the physical compatibility slot"
        print("Passed: a pinned unsupported extra returns in one operation", flush=True)
finally:
    if app: app.close()
    if fixture: fixture.close()
    if old_cache is None: cache_file.unlink(missing_ok=True)
    else: cache_file.write_bytes(old_cache)
    after = plistlib.loads(subprocess.check_output(["defaults", "export", "com.tyrell.Draplet", "-"]))
    saved_compatibility = dict(after.get("compatibilityMenuItems", {}))
    for key in list(saved_compatibility):
        if key.startswith("org.drapletqa.native|"): del saved_compatibility[key]
    saved_compatibility.update({key: value for key, value in before.get("compatibilityMenuItems", {}).items() if key.startswith("org.drapletqa.native|")})
    if saved_compatibility or "compatibilityMenuItems" in before:
        arguments = ["defaults", "write", "com.tyrell.Draplet", "compatibilityMenuItems", "-dict"]
        for key, value in saved_compatibility.items(): arguments.extend([key, "-int", str(value)])
        subprocess.run(arguments, check=True)
    elif "compatibilityMenuItems" not in before:
        subprocess.run(["defaults", "delete", "com.tyrell.Draplet", "compatibilityMenuItems"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    pins_preserved = before.get("pinnedPocketBundles") == after.get("pinnedPocketBundles")
    with (args.report / "normal.log").open("w") as log:
        normal = subprocess.Popen(["/Applications/Draplet.app/Contents/MacOS/Draplet"], stdin=subprocess.DEVNULL,
                                  stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    normal_pid_file.write_text(str(normal.pid))
    print("Normal app restored", normal.pid, flush=True)
    assert pins_preserved, "QA changed a real pin"
