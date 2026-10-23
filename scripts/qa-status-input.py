#!/usr/bin/env python3
"""Foreign hit-window regression using two disposable native publishers.

The target's menu delegate, rather than an AX return code, proves ownership.
The blocker posts balanced physical WindowServer input only over its own window.
Run with the daily Draplet stopped; the caller restores that process afterward.
"""
import argparse
import importlib.util
import json
import plistlib
import time
from pathlib import Path
import subprocess

spec = importlib.util.spec_from_file_location("native_qa", Path(__file__).with_name("qa-native.py"))
assert spec is not None and spec.loader is not None
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--expect-interception", action="store_true", help="Prove the old bug before applying its fix")
    parser.add_argument("--screenshots", action="store_true", help="Capture the owned arrow at rest and while pressed")
    args = parser.parse_args()
    args.report.mkdir(parents=True, exist_ok=True)
    before = plistlib.loads(subprocess.check_output(["defaults", "export", "com.tyrell.Draplet", "-"]))
    assert "org.drapletqa.native" not in before.get("pinnedPocketBundles", [])
    fixture = target = app = None
    results = []
    try:
        fixture = native.Controls(Path("/Applications/Draplet QA Status.app/Contents/MacOS/StatusFixture"), args.report / "blocker.log")
        fixture.send("window")
        fixture.wait(lambda s: not s["fullscreen"] and not s["changing"])
        target = native.Controls(Path("/Applications/Draplet Click Target QA.app/Contents/MacOS/ClickTarget"), args.report / "target.log")
        target.wait(lambda s: s["openMenus"] == 0)
        app = native.Controls(Path("/Applications/Draplet.app/Contents/MacOS/Draplet"), args.report / "app.log",
                              "--test-controls", "--qa-no-reopen", "-autoCollapse", "NO")
        app.wait(lambda s: s["backgroundReady"] and not s["systemPresentationSuspended"], timeout=25)
        app.send("pin:org.drapletqa.native")
        app.wait(lambda s: "org.drapletqa.native" in s["pocket"]["pins"])
        app.send("expand")
        app.wait(lambda s: s["right"] == "Expanded" and not s["pocket"]["transitioning"], timeout=15)
        fixture.send("block-target")
        fixture.wait(lambda s: s["blocker"] and s["postEventsAllowed"])
        time.sleep(.8)
        for index in range(1 if args.expect_interception else 12):
            # Re-anchor from the independent publisher, never repeatedly click
            # a fixture rectangle after the native bar has repacked beneath it.
            fixture.send("block-target")
            fixture.wait(lambda s: s["blocker"])
            start = fixture.status()["blockerClicks"]
            menus = target.status()["menuOpens"]
            button = "right" if index >= 10 else "left"
            fixture.send("right-click-target" if button == "right" else "click-arrow")
            if args.expect_interception:
                observed = fixture.wait(lambda s: s["blockerClicks"] > start)
                assert target.status()["openMenus"] == 0
                results.append({"oldBug": True, "wrongOwnerClicks": observed["blockerClicks"] - start, "targetMenus": 0})
            else:
                try:
                    opened = target.wait(lambda s: s["menuOpens"] == menus + 1)
                except AssertionError:
                    (args.report / "failure.json").write_text(json.dumps({"app":app.status(),"fixture":fixture.status(),"target":target.status()},indent=2))
                    raise
                assert fixture.status()["blockerClicks"] == start, "The foreign publisher received the native target's click"
                target.send("cancel-menu")
                closing = target.wait(lambda s: s["openMenus"] == 0)
                target.wait(lambda s: s["menuWindows"] == 0)
                results.append({"cycle": index + 1, "button": button, "wrongOwnerClicks": 0,
                                "targetMenuOpens": opened["menuOpens"] - menus, "menuVisibleAtObservation": opened["openMenus"],
                                "closingMenuWindows":closing["menuWindows"]})
            print(json.dumps(results[-1]), flush=True)
        if args.screenshots and not args.expect_interception:
            fixture.send("clear-blocker")
            fixture.wait(lambda s: not s["blocker"])
            rect = fixture.request("arrow-geometry")["frame"]
            assert len(rect) == 4, "Independent native observer could not locate Draplet's arrow"
            region = ",".join(str(round(value)) for value in rect)
            subprocess.run(["screencapture", "-x", "-R" + region, str(args.report / "arrow-idle.png")], check=True)
            fixture.send("press-arrow")
            time.sleep(.25)
            subprocess.run(["screencapture", "-x", "-R" + region, str(args.report / "arrow-pressed.png")], check=True)
            held = app.status()
            current_rect = fixture.request("arrow-geometry")["frame"]
            subprocess.run(["screencapture", "-x", "-R900,0,550,40", str(args.report / "bar-pressed.png")], check=True)
            (args.report / "arrow-press.json").write_text(json.dumps({"beforeFrame": rect,"heldFrame": current_rect,
                "right": held["right"], "arrowBacking": held["arrowFrame"],"router": held["pocket"]["clickRouting"],
                "suspended": held["systemPresentationSuspended"],"cover":held["rightAnimation"]}, indent=2))
            time.sleep(1.3)  # The fixture unconditionally balances the held down.
    finally:
        if fixture:
            fixture.send("clear-blocker")
        if target:
            target.send("cancel-menu")
        if app:
            app.send("unpin:org.drapletqa.native")
            app.wait(lambda s: "org.drapletqa.native" not in s["pocket"]["pins"])
            app.close()
        if target:
            target.close()
        if fixture:
            fixture.close()
        (args.report / "results.json").write_text(json.dumps(results, indent=2))
        after = plistlib.loads(subprocess.check_output(["defaults", "export", "com.tyrell.Draplet", "-"]))
        assert before.get("pinnedPocketBundles") == after.get("pinnedPocketBundles"), "Real pins changed"


if __name__ == "__main__":
    main()
