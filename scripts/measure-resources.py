#!/usr/bin/env python3
"""Read a macOS process's CPU time and memory without a sampling profiler.

CPU is a percentage of one core. Footprint, RSS and sampled peak are distinct.
This does not measure GPU utilization or attribute WindowServer's resource cost.
"""
import argparse
import ctypes
import json
import math
import platform
import time


class Usage(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_ubyte * 16)] + [
        (name, ctypes.c_uint64)
        for name in ("user", "system", "idle_wakeups", "interrupt_wakeups", "pageins",
                     "wired", "rss", "footprint", "start", "exit")
    ]


class Timebase(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--seconds", type=float, default=30)
    parser.add_argument("--warmup", type=float, default=5)
    args = parser.parse_args()
    if platform.system() != "Darwin" or args.pid <= 0 or args.seconds < 1 or args.warmup < 0 or not math.isfinite(args.seconds) or not math.isfinite(args.warmup):
        parser.error("Requires macOS, a positive PID, seconds >= 1 and warmup >= 0")
    libproc = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    libproc.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
    libproc.proc_pid_rusage.restype = ctypes.c_int
    tb = Timebase()
    ctypes.CDLL("/usr/lib/libSystem.B.dylib").mach_timebase_info(ctypes.byref(tb))
    # ri_user_time / ri_system_time use Mach absolute-time units. Convert using
    # this machine's timebase; assuming nanoseconds gives wrong Apple-silicon CPU.
    seconds_per_tick = tb.numer / tb.denom / 1e9

    def read():
        value = Usage()
        if libproc.proc_pid_rusage(args.pid, 0, ctypes.byref(value)) != 0:
            raise SystemExit(f"Cannot read PID {args.pid}: errno {ctypes.get_errno()}")
        return value

    read()
    time.sleep(args.warmup)
    before = read()
    begin = time.monotonic()
    samples = [before]
    while time.monotonic() - begin < args.seconds:
        time.sleep(min(1, max(0, args.seconds - (time.monotonic() - begin))))
        samples.append(read())
    elapsed = time.monotonic() - begin
    after = samples[-1]
    if before.start != after.start:
        raise SystemExit("PID was reused during measurement")
    cpu_seconds = (after.user + after.system - before.user - before.system) * seconds_per_tick
    print(json.dumps({
        "pid": args.pid, "seconds": round(elapsed, 3),
        "cpu_percent_one_core": round(cpu_seconds / elapsed * 100, 3),
        "cpu_seconds": round(cpu_seconds, 4),
        "footprint_MiB": round(after.footprint / 1048576, 2),
        "sampled_peak_footprint_MiB": round(max(v.footprint for v in samples) / 1048576, 2),
        "rss_MiB": round(after.rss / 1048576, 2),
        "package_idle_wakeups_per_second": round((after.idle_wakeups - before.idle_wakeups) / elapsed, 2),
        "gpu_utilization": None,
        "notes": "Process only; excludes WindowServer attribution. Sampled memory peak is not lifetime peak."
    }, indent=2))


if __name__ == "__main__":
    main()
