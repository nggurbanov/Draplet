# Alpha release readiness — 0.5.0 (build 13)

Checked on the development Mac on 2026-10-18. The public binary release remains a draft; the production update feed intentionally advertises no update yet.

## Fixed during the stability pass

- Invalid stored shortcut indices no longer crash startup; invalid values disable the shortcut.
- A completely empty Accessibility menu inventory leaves status icons visible instead of hiding every third-party application.
- Capture/setup requirements follow the enabled features and Accessibility permission. Native right-side Hidden Bar mode alone does not require background capture.
- Transient background failures retry twice (0.5 s, then 1.5 s), with stale callbacks cancelled on stop/reconfiguration. An incomplete initial capture times out rather than leaving Setup spinning indefinitely. Settings shows the actual failure detail.
- Scheduled updates remain prominent when background downloads are disabled: a persistent Settings action and a deferrable reminder lead to Sparkle's download/install flow.
- Permission polling runs asynchronously, at most once per second, with one request in flight. Display geometry and Dock identity are cached until invalidated; unchanged left indicator metadata is not repeatedly assigned.
- Release and updater-test signing use the same identity throughout the Sparkle helper graph. Repeated updater fixtures use separate bundle identifiers and refuse to overwrite running copies.

## Verified

- 168 lifecycle, preference, rendering, animation, permission-monitor, retry-policy and updater-selector checks passed; native build and deep strict code-signature verification passed.
- Regression tests first reproduced the invalid shortcut, empty inventory and permission-policy failures before their fixes.
- In the preceding build-12 updater audit, real isolated signed-archive build 100 → 101 installation worked, including normal-quit installation without relaunch, explicit immediate relaunch and preserved preferences. Corrupt archive and unavailable-feed failure paths were exercised.
- In that updater audit, with automatic downloads disabled, a scheduled update showed the custom reminder, persisted a one-hour deferral, remained actionable in Settings and completed the actual Sparkle download/install/relaunch path. This fixture used an entirely ad-hoc-signed helper graph.
- An injected interruption through the real capture failure handler recovered in the same process. Live mode streamed; Cached mode returned to ready with streaming stopped.
- Final build 13 suppressed its title, hit target and covers in a disposable native fullscreen window and restored them on return. Window metadata also recorded cover removal during Mission Control. Earlier native tests covered the same entry/exit paths before the metadata cache change.
- Build-13 native Settings captures cover Appearance in light/dark. Closing/recreating Settings preserved Right navigation and correctly removed/restored the Dock icon. Earlier General/Shortcuts/Left and updater ready/error captures remain historical evidence.
- The DMG checksum, mounted application signature/executable and real Applications shortcut passed packaging verification. The updater candidate feed is separately Ed25519 signed.

## Limits before broader beta claims

- This is Apple-silicon hardware on macOS 27. Intel, macOS 14.2–26, multiple physical displays, sleep/wake and repeated slow gesture reversal still need a hardware matrix. Legacy systems use the divider layout described in README.
- Fullscreen acceptance here uses a disposable AppKit host; it does not replace another user acceptance run in Fladder/Minecraft after this revision.
- The original spontaneous background interruption's cause was not proven; automatic recovery was verified by fault injection.
- Resource profiling and repeatable measurement instructions are in [PERFORMANCE.md](PERFORMANCE.md). GPU utilization, WindowServer attribution, battery life and long-term memory stability were not quantified. A Live sample on the current opaque menu-bar background is not an animated-wallpaper worst-case benchmark.
- The empty-inventory fix does not prove every partially missing AX inventory safe. macOS system-owned icon and per-application grouping limits remain.
- Public alpha artifacts are ad-hoc signed, not Developer ID signed or notarized; initial Gatekeeper approval may still be required.

## Build-13 resource pass

The repaint regression first failed against WindowServer-rounded indicator coordinates and passed after normalization/unchanged-layout suppression. Shared window discovery, foreground KVO/scalar caching, one shared 20 Hz pointer/presentation tick and a bounded frame-delivery gate retain the fast system-presentation path. Native scanline reconstruction fell from about 2.66 to 0.34 ms/frame in a synthetic 2940×66 benchmark, with equal signatures.

Sequential same-Mac process samples before the final timer consolidation measured build 12 at 7.287% of one core / 44.99 MiB footprint, and build 13 at 1.999% / 22.99 MiB before opening Settings (20 seconds each, 5-second warm-up). The current Live/opaque-background sample was 2.347% / 24.49 MiB; it published only one changed desktop frame. Native fullscreen measured 0.476% over five seconds. These are short diagnostics on a Mac in use, with possible foreground/window/layout differences, not a controlled energy benchmark.

After real Settings use, the new process retained 52–55 MiB and reached about 138 MiB lifetime peak: AppKit/SwiftUI caches remain after hosting views/windows are released. The cold-start improvement must not be presented as a universal halving of RAM or proof that leaks cannot occur.

Final shared-clock build-13 follow-up: a 20-second Cached sample (three-second warm-up) measured 2.449% of one core, 24.19 MiB footprint and 2.95 package-idle wakeups/s. The earlier build-12 reference measured 7.287%, 44.99 MiB and 6.15 wakeups/s. Wakeups vary with scheduling/system activity; this does not establish battery savings. Final native entry/exit and Mission Control entry/exit removed all covers, restored them after fresh background and preserved left auto-hide. Capture-failure injection recovered with the shared clock, and pause stopped capture/overlays.

A final shared-clock Live/opaque-background sample measured 2.757% CPU and 26.13 MiB over 10.005 seconds; changed animated-wallpaper throughput and GPU utilization remain unmeasured.
