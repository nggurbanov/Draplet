#!/usr/bin/env python3
"""Bounded native rendering/capture lifecycle QA for an uninstalled candidate.

Requires an unlocked Mac, existing Accessibility/Screen Recording access and no
running Draplet. Launch overrides live in NSArgumentDomain; controls never edit
preferences. Only children started here may be stopped. Reports include raw
native logs, statuses and preference snapshots; idle drawing is an observation
because another application or wallpaper can legitimately change the scene.
"""
import argparse
import datetime
import hashlib
import importlib.util
import json
import plistlib
import re
import subprocess
import sys
import time
from pathlib import Path


class Preconditions(RuntimeError):
    pass


def draplet_processes():
    output = subprocess.check_output(["ps", "-axo", "pid=,comm="], text=True, timeout=4)
    found = []
    for line in output.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and Path(parts[1]).name == "Draplet":
            found.append({"pid": int(parts[0]), "executable": parts[1]})
    return found


def preferences(domain):
    result = subprocess.run(["defaults", "export", domain, "-"], capture_output=True, timeout=5)
    if result.returncode:
        error = result.stderr.decode(errors="replace")
        if "does not exist" in error or "not found" in error:
            return {}
        raise RuntimeError("Cannot snapshot preferences: " + error.strip())
    return plistlib.loads(result.stdout)


def json_value(value):
    if isinstance(value, bytes):
        return {"bytes": len(value), "sha256": hashlib.sha256(value).hexdigest()}
    if isinstance(value, (datetime.datetime, datetime.date)):
        return value.isoformat()
    if isinstance(value, dict):
        return {key: json_value(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_value(item) for item in value]
    return value


def preference_diff(before, after):
    return [{"key": key, "beforePresent": key in before, "afterPresent": key in after,
             "before": json_value(before.get(key)), "after": json_value(after.get(key))}
            for key in sorted(before.keys() | after.keys())
            if (key in before) != (key in after) or before.get(key) != after.get(key)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True, help="Candidate .app; never installed or replaced")
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--idle-seconds", type=float, default=1.5)
    parser.add_argument("--startup-quit-delays", default="0.01,0.1,0.3",
                        help="Comma-separated application --quit-after intervals in seconds")
    args = parser.parse_args()
    if not .2 <= args.idle_seconds <= 10:
        parser.error("--idle-seconds must be between .2 and 10")
    try:
        quit_delays = [float(value) for value in args.startup_quit_delays.split(",")]
    except ValueError:
        parser.error("--startup-quit-delays must contain numbers")
    if not quit_delays or len(quit_delays) > 8 or any(not 0 < delay <= 1 for delay in quit_delays):
        parser.error("Provide one to eight startup quit intervals greater than zero and at most one second")

    args.report = args.report.resolve()
    args.report.mkdir(parents=True, exist_ok=True)
    report = {"startedUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "app": str(args.app.resolve()), "checks": [], "runs": [],
              "scope": "Native child-process capture/render QA; no install or independent TCC acceptance"}
    children = []
    before = None
    domain = None
    exit_code = 1

    def record(name, **evidence):
        report["checks"].append({"check": name, "passed": True, **evidence})
        print("PASS", name, flush=True)

    def save_status(name, state):
        (args.report / (name + ".json")).write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")

    def ensure_environment(state):
        for key in ("authorized", "backgroundPermission", "native", "backgroundCapturesPending",
                    "leftDraws", "leftDisplayRequests", "leftAnimationTimerActive", "rightAnimation"):
            if key not in state:
                raise Preconditions("Candidate lacks required native QA field: " + key)
        for key in ("draws", "displayRequests", "timerActive", "presentationChanges"):
            if key not in state["rightAnimation"]:
                raise Preconditions("Candidate lacks rightAnimation." + key)
        if not state["authorized"] or not state["backgroundPermission"]:
            raise Preconditions("Existing Accessibility and Screen Recording access are required; no permission changes made")
        if not state["native"]:
            raise Preconditions("The native right-side visibility backend is unavailable on this Mac")
        if state.get("systemPresentationSuspended") or state.get("presentationSuppressed"):
            raise Preconditions("Desktop presentation is suppressed; leave fullscreen/Mission Control before rerunning")
        if state.get("backgroundError"):
            raise RuntimeError("Native background capture failed: " + state["backgroundError"])
        if state.get("right") in ("Paused", "Waiting for Hidden Bar to quit", "Accessibility permission needed"):
            raise Preconditions("Current right-side configuration cannot be exercised: " + state["right"])

    def wait_status(control, predicate, timeout=12):
        deadline = time.monotonic() + timeout
        last = None
        while time.monotonic() < deadline:
            last = control.status()
            ensure_environment(last)
            if predicate(last):
                return last
            time.sleep(.12)
        raise AssertionError("Native state did not settle: " + json.dumps(last, sort_keys=True))

    def settled_right(control, expanded=True):
        return wait_status(control, lambda state: state["rightAnimation"]["expanded"] == expanded
                           and not state["rightAnimation"]["transitioning"]
                           and not state["rightAnimation"]["timerActive"]
                           and state["right"] == ("Expanded" if expanded else "Hidden"))

    def stop_and_check(control, run, send_quit=True):
        started = time.monotonic()
        if send_quit:
            control.send("quit")
        try:
            control.process.wait(timeout=6)
        except subprocess.TimeoutExpired as error:
            raise AssertionError("Owned candidate did not finish normal Quit within six seconds: " + str(run["log"])) from error
        control.reader.join(timeout=1)
        control.log.flush()
        log = Path(run["log"]).read_text(errors="replace")
        run.update(returncode=control.process.returncode, quitWaitSeconds=round(time.monotonic() - started, 4),
                   elapsedSeconds=round(time.monotonic() - run.pop("startedMonotonic"), 4),
                   cleanupPending=[int(count) for count in re.findall(r"native UI cleanup complete; (\d+) capture", log)])
        assert control.process.returncode == 0, "Candidate exited abnormally: " + str(run)
        assert "capture shutdown timed out" not in log, "Native shutdown watchdog fired: " + str(run)
        assert "Draplet background capture stop:" not in log, "ScreenCaptureKit reported a stop error: " + str(run)
        assert re.search(r"capture shutdown complete; 0 capture stream\(s\) pending", log), \
            "No native shutdown-complete/pending-zero evidence: " + str(run)
        run["shutdownCompletePendingZero"] = True
        control.close()

    try:
        if sys.platform != "darwin":
            raise Preconditions("Native lifecycle QA requires macOS")
        running = draplet_processes()
        if running:
            raise Preconditions("A Draplet process already exists; it was left untouched: " + json.dumps(running))
        info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
        domain = info.get("CFBundleIdentifier")
        if domain != "com.tyrell.Draplet" or info.get("CFBundleExecutable") != "Draplet":
            raise Preconditions("Expected a Draplet candidate bundle, received: " + repr(domain))
        executable = (args.app / "Contents/MacOS/Draplet").resolve()
        if not executable.is_file():
            raise Preconditions("Candidate executable is missing: " + str(executable))
        spec = importlib.util.spec_from_file_location("draplet_native_qa", Path(__file__).with_name("qa-native.py"))
        assert spec is not None and spec.loader is not None
        qa = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(qa)
        before = preferences(domain)
        (args.report / "preferences-before.plist").write_bytes(plistlib.dumps(before))

        def launch(mode, name, quit_after=None):
            running = draplet_processes()
            if running:
                raise Preconditions("Refusing another launch while Draplet exists: " + json.dumps(running))
            arguments = ["--test-controls", "--qa-no-reopen", "-hasLaunched", "YES", "-autoCollapse", "NO",
                         "-rightRevealMode", "menuBar", "-backgroundMode", mode,
                         "-SUEnableAutomaticChecks", "NO", "-SUAutomaticallyUpdate", "NO"]
            if quit_after is not None:
                arguments += ["--quit-after", str(quit_after)]
            run = {"name": name, "mode": mode, "arguments": arguments,
                   "log": str(args.report / (name + ".log")), "startedMonotonic": time.monotonic()}
            control = qa.Controls(executable, run["log"], *arguments)
            run["pid"] = control.process.pid
            children.append(control)
            report["runs"].append(run)
            return control, run

        cached, cached_run = launch("cached", "cached")
        state = wait_status(cached, lambda current: current["backgroundReady"]
                            and current["backgroundSnapshots"] >= 1
                            and current["backgroundCapturesPending"] == 0 and not current["streaming"], timeout=25)
        if not state["leftEnabled"]:
            raise Preconditions("Current preferences disable the left controller; no preferences were changed")
        assert state["backgroundMode"] == "cached" and state["rightRevealMode"] == "menuBar", state
        save_status("cached-settled", state)
        record("Cached frame retires its stream", snapshots=state["backgroundSnapshots"], pending=0)

        cached.send("expand")
        settled_right(cached)
        start = cached.status()
        for _ in range(20):
            cached.send("qa-presentation-refresh")
        end = cached.status()  # FIFO status fences the preceding main-thread controls.
        ensure_environment(end)
        assert end["rightAnimation"]["presentationChanges"] == start["rightAnimation"]["presentationChanges"], (start, end)
        record("20 unchanged presentation refreshes skip policy work",
               before=start["rightAnimation"]["presentationChanges"], after=end["rightAnimation"]["presentationChanges"])

        idle_start = cached.status()
        idle_started = time.monotonic()
        time.sleep(args.idle_seconds)
        idle_end = cached.status()
        ensure_environment(idle_end)
        save_status("idle-before", idle_start)
        save_status("idle-after", idle_end)
        deltas = {key: idle_end[key] - idle_start[key]
                  for key in ("leftDraws", "leftDisplayRequests", "backgroundSnapshots", "backgroundFrames")}
        deltas.update({"right." + key: idle_end["rightAnimation"][key] - idle_start["rightAnimation"][key]
                       for key in ("draws", "displayRequests", "presentationChanges")})
        report["idleObservation"] = {"elapsedSeconds": round(time.monotonic() - idle_started, 4), "deltas": deltas,
                                     "note": "Drawing deltas are reported, not asserted: external scene changes remain possible"}
        assert not idle_end["leftAnimationTimerActive"] and not idle_end["rightAnimation"]["timerActive"], idle_end
        record("Settled controllers have no animation timers")

        left_initial = cached.status()["leftRevealed"]
        for _ in range(20):
            cached.send("left-toggle")
            time.sleep(.035)
        left_final = wait_status(cached, lambda current: current["leftRevealed"] == left_initial
                                 and not current["leftAnimationTimerActive"]
                                 and abs(current["progress"] - (1 if left_initial else 0)) < .0001)
        save_status("left-rapid-final", left_final)
        record("20 rapid left toggles converge without a timer", revealed=left_initial)

        cached.send("expand")
        settled_right(cached)
        for _ in range(20):
            cached.send("right-click")
            time.sleep(.035)
        right_final = settled_right(cached)
        save_status("right-rapid-final", right_final)
        record("20 rapid right toggles converge without a timer", expanded=True)
        stop_and_check(cached, cached_run)
        record("Cached Quit finishes capture shutdown with pending zero")

        live, live_run = launch("live", "live")
        live_state = wait_status(live, lambda current: current["backgroundReady"] and current["streaming"]
                                 and current["backgroundCapturesPending"] == 1, timeout=25)
        assert live_state["backgroundMode"] == "live", live_state
        save_status("live-active", live_state)
        record("Live owns one active capture stream", pending=1, frames=live_state["backgroundFrames"])
        stop_and_check(live, live_run)
        record("Live Quit drains capture before native shutdown")

        for index, delay in enumerate(quit_delays):
            immediate, run = launch("live", "live-startup-quit-" + str(index + 1), quit_after=delay)
            stop_and_check(immediate, run, send_quit=False)
            record("Live startup Quit completes at requested interval", requestedSeconds=delay,
                   elapsedSeconds=run["elapsedSeconds"], cleanupPending=run["cleanupPending"])
        report["outcome"] = "passed"
        exit_code = 0
    except Preconditions as error:
        report.update(outcome="blocked", error=str(error))
        print("BLOCKED", error, file=sys.stderr, flush=True)
        exit_code = 2
    except Exception as error:
        report.update(outcome="failed", error=repr(error))
        print("FAIL", repr(error), file=sys.stderr, flush=True)
    finally:
        for control in reversed(children):
            if not control.log.closed:
                try:
                    was_running = control.process.poll() is None
                    control.close()
                    if was_running:
                        report.setdefault("cleanup", []).append({"pid": control.process.pid, "returncode": control.process.returncode})
                except Exception as error:
                    # Never target a process found by name: this Popen is ours.
                    if control.process.poll() is None:
                        control.process.kill()
                        control.process.wait(timeout=3)
                    report.setdefault("cleanupErrors", []).append(repr(error))
                    report["outcome"] = "failed"
                    exit_code = 1
        if before is not None and domain is not None:
            try:
                after = preferences(domain)
                (args.report / "preferences-after-before-restore.plist").write_bytes(plistlib.dumps(after))
                report["preferencesBeforeCleanupDiff"] = preference_diff(before, after)
                created_launch_keys = [key for key in ("hasLaunched", "SUHasLaunchedBefore")
                                       if key not in before and after.get(key) is True]
                if created_launch_keys:
                    if draplet_processes():
                        report["launchKeyCleanup"] = "Skipped: a new Draplet process exists; preserve its state"
                    else:
                        for key in created_launch_keys:
                            subprocess.run(["defaults", "delete", domain, key], capture_output=True, check=True, timeout=5)
                        report["launchKeyCleanup"] = {"removedPreviouslyAbsentKeys": created_launch_keys}
                final_preferences = preferences(domain)
                (args.report / "preferences-after.plist").write_bytes(plistlib.dumps(final_preferences))
                report["preferencesFinalDiff"] = preference_diff(before, final_preferences)
                if report["preferencesFinalDiff"]:
                    report["preferencesNote"] = "Differences reported and preserved; no wholesale preference restoration"
            except Exception as error:
                report["preferencesError"] = repr(error)
                report["outcome"] = "failed"
                exit_code = 1
        for run in report["runs"]:
            if "startedMonotonic" in run:
                run["elapsedSeconds"] = round(time.monotonic() - run.pop("startedMonotonic"), 4)
        report["finishedUTC"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        (args.report / "summary.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        print("Report:", args.report / "summary.json", flush=True)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
