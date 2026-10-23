# Resource behavior and profiling

Draplet draws over the menu bar, observes other applications through Accessibility and, when required, reconstructs the menu-bar background. Resource costs depend on the foreground app, wallpaper, menu state and system memory pressure.

## Resource strategy

- Use one shared 20 Hz tick for system-presentation detection and left-side pointer/menu checks instead of two independent fast timers. Animation timers still run at 60 Hz only during transitions.
- Share typed window observations. Discover visible window IDs at the existing 20 Hz presentation cadence; describe all windows only when IDs change, when background shadow geometry is needed or after a 250 ms fallback. Known Dock and game canvases still receive targeted 20 Hz geometry/alpha checks, including fades with unchanged IDs.
- Observe the [KVO-compliant foreground application](https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication) and share scalar PID/name. Activation/termination events invalidate cached metadata immediately; a 500 ms fallback covers missed notifications. This avoids NSRunningApplication dynamic-property reads on every fast tick.
- Cache AppKit presentation options between notifications, with immediate invalidation and a 250 ms fallback. Known native fullscreen returns before unnecessary window enumeration. Foreground fullscreen AX polling retains its existing maximum 4 Hz cadence.
- Hidden, unused left-menu geometry uses a one-second AX interval. Revealed, hovered, selected or keyboard-popup menus retain the fast 150 ms interval.
- Normalize indicator window coordinates before comparing them with WindowServer's rounded frames. Unchanged indicator layouts bypass image/label/geometry work. This removes repeated stationary repaint requests caused by fractional title metrics.
- Build Settings only when opened; release hosting views, toolbar and window when closed. Navigation/preferences survive reconstruction, and Dock visibility still follows Settings.
- Keep one converted live frame pending for main at most, rejecting stale completion tokens after stream replacement. Release the Core Image context/caches after capture stops, and reuse the NSImage used to draw a background.
- Compute native scanline medians with histograms rather than repeated sorting. The sampled upper-median rule and resulting background signatures are preserved, including odd/even samples and small images. Live remains capped at 30 fps and capture queue depth 3; unchanged fingerprints are skipped. No animation speed or capture resolution was reduced.

## Reproduce measurements

Run on macOS with Settings closed and a settled foreground app/wallpaper:

```sh
python3 scripts/measure-resources.py --pid "$(pgrep -x Draplet)" --seconds 30 --warmup 5
```

The helper reads cumulative process CPU and memory through libproc. It converts Mach time with the machine's timebase; CPU is a percentage of **one core**. Footprint, resident memory and a sampled memory peak are different values. The helper does not capture pixels, restart apps, measure GPU utilization or attribute WindowServer's CPU/GPU work.

For an A/B comparison, use the same Mac, foreground app, wallpaper, Settings visibility and menu state. Keep profiler/build/UI activity outside the measured interval. Warm up each build and repeat; a short desktop sample is not a battery benchmark. Use vmmap for lifetime memory peak and Instruments/authorized GPU profiling for graphics utilization.

## Validation scope

The regression suite covers shared observations and same-ID Dock fades, immediate app changes, cache invalidation, stale capture deliveries, exact background medians, stationary indicator repaint requests, Settings release/recreation and preserved menu/fullscreen behavior. A captured WindowServer-rounded frame triggers the repaint regression before the fix.

Historical measurements are scoped below; current release validation and its limits are in [RELEASE_READINESS.md](RELEASE_READINESS.md). No claim of zero GPU use, absence of long-term leaks, or universal battery improvement is made.

## Local measurements (2026-10-18)

On the same 10-core Apple-silicon / 16 GiB Mac running macOS 27.0.1, sequential desktop samples measured build 12 at about 7.3% of one core and 45 MiB footprint, versus the final build 13 at about 2.45% and 24 MiB before Settings. The intervals were 20 seconds with warm-up, without a sampling profiler; the Mac remained in use, so foreground/window/layout differences and scheduling introduce noise. This is an approximate practical comparison, not a fixed-workload energy benchmark.

During the build-13 pass, Settings use left 52–55 MiB footprint and a lifetime peak around 138 MiB: framework/system caches remain after the window and hosting hierarchy are released. Do not interpret the cold-start improvement as a universal halving of RAM. A Live sample on the current opaque bar published only one changed desktop frame; it does not represent the worst case for animated wallpapers. Exact GPU utilization and WindowServer attribution were unavailable. Detailed acceptance and limits are in [RELEASE_READINESS.md](RELEASE_READINESS.md).
