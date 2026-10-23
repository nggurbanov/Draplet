#!/usr/bin/env python3
"""Bounded native integration QA on an unlocked Mac.

Run against the installed candidate with a compiled Tests/Native/StatusFixture
app. Exercises real controllers, AX actions, WindowServer and native hiding;
does not substitute for hardware acceptance of Command-drag gestures. Automatic
return invokes the production tagged native move on disposable QA icons only.
"""
import argparse
import json
import plistlib
import queue
import signal
import subprocess
import threading
import time
from pathlib import Path


class Controls:
    def __init__(self, executable, log, *arguments):
        self.log = open(log, "w")
        self.process = subprocess.Popen([str(executable), *arguments], stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        assert self.process.stdin is not None and self.process.stdout is not None
        self.input = self.process.stdin
        self.output = self.process.stdout
        self.replies = queue.Queue()
        self.reader = threading.Thread(target=self.read, daemon=True)
        self.reader.start()

    def read(self):
        for line in self.output:
            self.log.write(line)
            self.log.flush()
            if line.startswith("{"):
                try:
                    self.replies.put(json.loads(line))
                except ValueError:
                    pass

    def send(self, value):
        if self.process.poll() is not None:
            raise RuntimeError(f"Native process exited: {self.process.returncode}")
        self.input.write(value + "\n")
        self.input.flush()

    def request(self, command):
        while not self.replies.empty():
            self.replies.get_nowait()
        self.send(command)
        try:
            return self.replies.get(timeout=4)
        except queue.Empty as exc:
            raise RuntimeError("Main-thread native status did not answer within four seconds") from exc

    def status(self):
        return self.request("status")

    def wait(self, predicate, timeout=8):
        deadline = time.monotonic() + timeout
        last = None
        while time.monotonic() < deadline:
            last = self.status()
            if predicate(last):
                return last
            time.sleep(.12)
        raise AssertionError(json.dumps(last, ensure_ascii=False))

    def close(self):
        if self.process.poll() is None:
            try:
                self.send("quit")
                self.process.wait(timeout=5)
            except (OSError, RuntimeError, subprocess.TimeoutExpired):
                self.process.terminate()
                self.process.wait(timeout=5)
        self.reader.join(timeout=1)
        self.log.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=Path("/Applications/Draplet.app"))
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--report", type=Path, default=Path(".build/native-qa"))
    parser.add_argument("--screenshot-helper", type=Path)
    args = parser.parse_args()
    args.report.mkdir(parents=True, exist_ok=True)
    before = subprocess.check_output(["defaults", "export", "com.tyrell.Draplet", "-"])
    (args.report / "preferences-before.plist").write_bytes(before)
    expected_pins = set(plistlib.loads(before).get("pinnedPocketBundles", [])) - {"org.drapletqa.native"}
    fixture = app = None
    results = []

    def passed(name, **evidence):
        results.append({"check": name, "passed": True, **evidence})
        print("PASS", name, json.dumps(evidence), flush=True)

    def settled(expanded):
        assert app is not None
        return app.wait(lambda s: s["rightAnimation"]["expanded"] == expanded
                        and not s["rightAnimation"].get("transitioning", True)
                        and s["right"] == ("Expanded" if expanded else "Hidden"))

    def snapshot(name):
        if args.screenshot_helper:
            subprocess.run(["python3",str(args.screenshot_helper),"--path",str(args.report / (name + ".png")),
                            "--region","740,0,650,300"], check=True, stdout=subprocess.DEVNULL)

    def fixture_images(opened):
        pocket = opened["pocket"]
        assert sum(name.startswith("Draplet QA") for name in pocket["names"]) == 8, opened
        assert pocket["images"] >= 8, opened
        glyphs = [value for name,value in pocket["glyphs"].items() if name.startswith("Draplet QA")]
        assert len(set(glyphs)) == 8, "Native fixture glyphs must be distinct; overflow arrows are not valid icon captures"
        sizes = [value for name,value in pocket["glyphSizes"].items() if name.startswith("Draplet QA")]
        # Production crops horizontally but preserves native bar-height padding.
        # A stale QA slot previously photographed two neighbours as one wide icon.
        assert len(sizes) == 8 and all(8 <= size[0] <= 24 and 16 <= size[1] <= 40 for size in sizes) \
            and max(size[0] for size in sizes)-min(size[0] for size in sizes) <= 1.5, \
            "Fixture circle widths must match; neighbouring menu-bar icons are not valid captures: " + repr(sizes)

    try:
        fixture = Controls(args.fixture / "Contents/MacOS/StatusFixture", args.report / "fixture.log")
        # Own the desktop scene instead of depending on the user's frontmost
        # application, which may legitimately be fullscreen during unattended QA.
        fixture.send("window")
        fixture.wait(lambda s:not s["fullscreen"] and not s["changing"])
        app = Controls(args.app / "Contents/MacOS/Draplet", args.report / "runtime.log",
                       "--test-controls", "--qa-no-reopen", "--qa-capture-dir", str((args.report / "captures-first").resolve()),
                       "-autoCollapse", "YES", "-collapseDelay", "5")
        app.wait(lambda s: s["backgroundReady"] and not s["systemPresentationSuspended"], timeout=25)
        app.send("collapse")
        settled(False)
        time.sleep(1.2)
        assert not app.status()["pocket"]["buttonVisible"], "Saved pins must not leave a Pocket chevron on the collapsed bar"
        app.send("pocket")
        assert not app.status()["pocket"]["visible"], "Pocket is reached through the expanded strip"
        snapshot("collapsed-pins")
        passed("collapsed strip hides Pocket even with saved pins and late scans")
        app.send("expand")
        expanded = settled(True)
        expanded = app.wait(lambda s: s["pocket"]["buttonVisible"] and s["pocket"]["overflow"]
                            and s["pocket"]["scan"].get("host", -1) > 0
                            and s["pocket"]["scan"].get("nativeOverflow", -1) >= 0)
        passed("real native overflow is reachable", items=len(expanded["pocket"]["overflow"]),
               button=expanded["pocket"]["buttonX"], native=expanded["pocket"]["scan"].get("nativeOverflow"))
        native = expanded["pocket"]["scan"].get("nativeOverflow", -1)
        assert native >= 0 and 0 <= native - expanded["pocket"]["buttonX"] <= 7, expanded
        assert expanded["pocket"]["buttonMaxX"] <= expanded["pocket"]["scan"]["firstVisibleX"] + 1, expanded
        snapshot("expanded-overflow")
        observed = []
        for index in range(4):
            if index:
                app.send("collapse")
                settled(False)
                app.send("expand")
                app.wait(lambda s: s["pocket"]["buttonVisible"] and not s["pocket"]["transitioning"])
            # Observe immediately after the curtain, without an extra settling
            # sleep that would conceal the original first-frame placement race.
            candidate = app.status()["pocket"]
            physical = fixture.request("overflow")
            # MenuBarAgent can expose two AX window entries for the same
            # physical control. Compare unique native rectangles, retaining
            # the raw observation in any failure; distinct positions still fail.
            buttons = {(value["x"], value["maxX"], value["width"]): value for value in physical["overflow"]}
            assert physical["trusted"] and len(buttons) == 1, physical
            actual = next(iter(buttons.values()))
            assert abs(actual["x"] - candidate["scan"]["nativeOverflow"]) < 1, (candidate, actual)
            assert candidate["buttonX"] <= actual["x"] and candidate["buttonMaxX"] >= actual["maxX"] - 1, (candidate, actual)
            observed.append({"button": [candidate["buttonX"], candidate["buttonMaxX"]], "physical": actual})
        passed("first revealed frame covers independently observed native overflow", cycles=observed)
        for index in range(40):
            app.send("collapse" if index % 2 == 0 else "expand")
            time.sleep(.045)
        settled(True)
        app.send("collapse")
        settled(False)
        passed("40 rapid reversals converge; explicit collapse works")
        for _ in range(40):
            app.send("right-click")
            time.sleep(.045)
        settled(False)
        app.send("right-click")
        settled(True)
        app.send("right-click")
        settled(False)
        passed("40 actual arrow actions converge; single clicks open and close")
        app.send("expand")
        settled(True)
        fixture.send("block-arrow")
        obstruction = fixture.wait(lambda s:s.get("blocker"))
        assert obstruction.get("postEventsAllowed"), "The owned fixture cannot post its test mouse events"
        app.wait(lambda s:s["pocket"].get("clickRouting", {}).get("frame", "none") != "none")
        intercepted = obstruction["blockerClicks"]
        for expanded in [False, True] * 10:
            fixture.send("click-arrow")
            settled(expanded)
            assert fixture.status()["blockerClicks"] == intercepted, "The foreign hit window stole an ordinary arrow click"
        fixture.send("clear-blocker")
        fixture.wait(lambda s:not s["blocker"])
        app.send("collapse")
        settled(False)
        passed("20 WindowServer arrow clicks bypass the foreign transparent hit window",foreign_clicks=0)
        app.send("expand")
        settled(True)
        if not app.status()["pocket"].get("holdReasons"):
            settled(False)
            passed("auto-hide closes after departure")
        else:
            raise AssertionError("Auto-hide held by " + str(app.status()["pocket"].get("holdReasons")))
        app.send("pin:org.drapletqa.native")
        app.wait(lambda s: "org.drapletqa.native" in s["pocket"]["pins"])
        assert not app.status()["pocket"]["buttonVisible"], "New pins do not expose a collapsed Pocket button"
        app.send("expand")
        settled(True)
        pins_shown = app.wait(lambda s:s["pocket"]["buttonVisible"] and not s["pocket"]["scanInFlight"])
        assert pins_shown["pocket"]["buttonMaxX"] <= pins_shown["pocket"]["scan"]["firstVisibleX"] + 1, pins_shown
        snapshot("expanded-pins")
        passed("pinned expanded strip puts Pocket before every native icon",button=pins_shown["pocket"]["buttonX"],
               first_icon=pins_shown["pocket"]["scan"]["firstVisibleX"],native_overflow=pins_shown["pocket"]["scan"]["nativeOverflow"])
        started = time.monotonic()
        app.send("pocket")
        opened = app.wait(lambda s: s["pocket"]["visible"] and not s["pocket"]["busy"], timeout=20)
        fixture_images(opened)
        passed("eight real pinned status images", images=opened["pocket"]["images"], size=[opened["pocket"]["width"],opened["pocket"]["height"]],cold_seconds=round(time.monotonic()-started,2))
        app.send("appearance-dark"); snapshot("pocket-dark")
        app.send("appearance-light"); snapshot("pocket-light")
        app.send("appearance-system")
        # Exercise the actual SwiftUI-backed source control and full return
        # callback across a run-loop turn, not just the separate drop policy.
        app.send("qa-pocket-return-fixture")
        returned = app.wait(lambda s:"org.drapletqa.native" not in s["pocket"]["pins"])
        assert set(returned["pocket"]["pins"]) == expected_pins, "Return changed a real pin"
        passed("actual Pocket cell Command-return removes only the fixture pin")
        app.send("expand")
        settled(True)
        app.wait(lambda s:s["pocket"]["buttonVisible"])
        app.send("pocket")
        automatic = app.wait(lambda s:s["pocket"]["visible"] and not s["pocket"]["busy"])
        if any(name.startswith("Draplet QA") for name in automatic["pocket"]["names"]):
            arrow_before = fixture.request("arrow-geometry")["frame"]
            app.send("qa-pocket-return-overflow-fixture")
            placed = app.wait(lambda s:s["pocket"].get("lastReturn") in ("returned", "failed", "cancelled")
                              and not s["pocket"]["busy"], timeout=12)
            assert placed["pocket"]["lastReturn"] == "returned", placed
            assert not placed["pocket"]["shield"] and not placed["systemPresentationSuspended"], placed
            assert set(placed["pocket"]["pins"]) == expected_pins
            arrow_after = fixture.request("arrow-geometry")["frame"]
            assert len(arrow_before) == len(arrow_after) == 4 and abs(arrow_after[0]-arrow_before[0]) < 1, \
                ("Native return moved the user's disclosure instead of the disposable source", arrow_before, arrow_after)
            passed("automatic overflow returns through native placement without Mission Control",arrow_before=arrow_before,arrow_after=arrow_after)
        app.send("pin:org.drapletqa.native")
        app.wait(lambda s:"org.drapletqa.native" in s["pocket"]["pins"])
        app.send("expand")
        settled(True)
        app.wait(lambda s:s["pocket"]["buttonVisible"])
        app.send("pocket")
        app.wait(lambda s:s["pocket"]["visible"] and not s["pocket"]["busy"])
        app.send("pocket-left:Draplet QA 1")
        app.wait(lambda s: "native-menu" in s["pocket"].get("holdReasons", []))
        passed("Pocket AX action opens the real fixture menu")
        fixture.send("cancel-menu")
        for _ in range(6):
            # The new control is intentionally unavailable on a collapsed bar.
            # Native actions and the departure timer may have closed the strip.
            app.send("expand")
            settled(True)
            app.wait(lambda s:s["pocket"]["buttonVisible"])
            app.send("pocket")
            app.wait(lambda s: s["pocket"]["visible"] and not s["pocket"]["busy"])
            app.send("pocket-toggle")
            app.wait(lambda s: not s["pocket"]["visible"] and not s["pocket"]["busy"])
        passed("six cached Pocket open-close cycles leave no work")
        app.close()
        app = Controls(args.app / "Contents/MacOS/Draplet", args.report / "restart.log",
                       "--test-controls", "--qa-no-reopen", "--qa-capture-dir", str((args.report / "captures-restart").resolve()),
                       "-autoCollapse", "YES", "-collapseDelay", "5")
        app.wait(lambda s: s["backgroundReady"] and not s["systemPresentationSuspended"], timeout=25)
        app.send("collapse")
        settled(False)
        assert not app.status()["pocket"]["buttonVisible"], "Restart with saved pins must retain the single collapsed arrow"
        app.send("expand")
        settled(True)
        app.wait(lambda s:s["pocket"]["buttonVisible"])
        started = time.monotonic()
        app.send("pocket")
        reopened = app.wait(lambda s: s["pocket"]["visible"] and not s["pocket"]["busy"], timeout=20)
        snapshot("pocket-restart")
        fixture_images(reopened)
        passed("fresh process retains distinct pinned glyphs",open_seconds=round(time.monotonic()-started,2),
               capture_requests=reopened["pocket"].get("captureRequests",0),disk_hits=reopened["pocket"].get("cacheDiskHits",0))
        app.send("pocket-toggle")
        app.wait(lambda s:not s["pocket"]["visible"] and not s["pocket"]["busy"])
        fixture.send("fullscreen")
        fixture.wait(lambda s:s["fullscreen"] and not s["changing"], timeout=12)
        full = app.wait(lambda s: s["nativeFullscreen"] and s["systemPresentationSuspended"], timeout=12)
        assert not full["leftVisible"] and not full["pocket"]["buttonVisible"], full
        assert not full["rightAnimation"].get("coverPresented", True), full
        passed("native fullscreen suppresses every Draplet cover/control")
        fixture.send("fullscreen")
        fixture.wait(lambda s:not s["fullscreen"] and not s["changing"], timeout=12)
        app.wait(lambda s: not s["nativeFullscreen"] and not s["systemPresentationSuspended"], timeout=12)
        app.send("collapse")
        settled(False)
        passed("desktop restoration collapses cleanly")
        app.send("unpin:org.drapletqa.native")
        unpinned = app.wait(lambda s:"org.drapletqa.native" not in s["pocket"]["pins"])
        assert set(unpinned["pocket"]["pins"]) == expected_pins, "Real pins changed during fixture cleanup"
        passed("test pin removed without touching real pins")
    finally:
        if app:
            try:
                app.send("unpin:org.drapletqa.native")
            except (OSError, RuntimeError):
                pass
            app.close()
        if fixture:
            fixture.close()
        current = plistlib.loads(subprocess.check_output(["defaults", "export", "com.tyrell.Draplet", "-"]))
        baseline = plistlib.loads(before)
        pins = [value for value in current.get("pinnedPocketBundles", []) if value != "org.drapletqa.native"]
        if pins or "pinnedPocketBundles" in baseline:
            subprocess.run(["defaults", "write", "com.tyrell.Draplet", "pinnedPocketBundles", "-array", *pins], check=True)
        else:
            subprocess.run(["defaults", "delete", "com.tyrell.Draplet", "pinnedPocketBundles"], capture_output=True)
        (args.report / "results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    for item in [signal.SIGTERM, signal.SIGINT]:
        signal.signal(item, lambda signum, frame: (_ for _ in ()).throw(SystemExit(128 + signum)))
    main()
