# Alpha release readiness — 0.5.0 (build 12)

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

- 139 lifecycle, preference, rendering, animation, permission-monitor, retry-policy and updater-selector checks passed; native build and deep strict code-signature verification passed.
- Regression tests first reproduced the invalid shortcut, empty inventory and permission-policy failures before their fixes.
- Real isolated signed-archive build 100 → 101 installation worked, including normal-quit installation without relaunch, explicit immediate relaunch and preserved preferences. Corrupt archive and unavailable-feed failure paths were exercised.
- With automatic downloads disabled, a scheduled update showed the custom reminder, persisted a one-hour deferral, remained actionable in Settings and completed the actual Sparkle download/install/relaunch path. This fixture used an entirely ad-hoc-signed helper graph.
- An injected interruption through the real capture failure handler recovered in the same process. Live mode streamed; Cached mode returned to ready with streaming stopped.
- Final build 12 suppressed its title, hit target and covers in a disposable native fullscreen window and restored them on return. Window metadata also recorded cover removal during Mission Control. Earlier native tests covered the same entry/exit paths before the metadata cache change.
- Current native Settings captures cover Appearance in light/dark, General and Shortcuts; existing Left/Right and updater ready/error captures cover preserved layouts. Dock visibility follows Settings visibility.
- The DMG checksum, mounted application signature/executable and real Applications shortcut passed packaging verification. The updater candidate feed is separately Ed25519 signed.

## Limits before broader beta claims

- This is Apple-silicon hardware on macOS 27. Intel, macOS 14.2–26, multiple physical displays, sleep/wake and repeated slow gesture reversal still need a hardware matrix. Legacy systems use the divider layout described in README.
- Fullscreen acceptance here uses a disposable AppKit host; it does not replace another user acceptance run in Fladder/Minecraft after this revision.
- The original spontaneous background interruption's cause was not proven; automatic recovery was verified by fault injection.
- Cached mode avoids continuous pixel streaming while settled, but window/foreground metadata polling continues. A warm observed sample was roughly 7% of one CPU core and 119 MiB RSS; no battery-life or idle-CPU improvement claim is made.
- The empty-inventory fix does not prove every partially missing AX inventory safe. macOS system-owned icon and per-application grouping limits remain.
- Public alpha artifacts are ad-hoc signed, not Developer ID signed or notarized; initial Gatekeeper approval may still be required.
