# Rune review and native Draplet improvements

Reviewed 2026-10-28 against Rune revision
[`d098d470e6f52c7d1c5025dd056cee2711ca0efb`](https://github.com/anomalyco/rune/tree/d098d470e6f52c7d1c5025dd056cee2711ca0efb).
This review uses implemented source, not performance targets or planned APIs.
Draplet remains a SwiftUI/AppKit application; no Rune or Rust dependency was added.

## Source comparison

| Rune mechanism | Draplet decision |
| --- | --- |
| [`runtime/timer_wake.rs`](https://github.com/anomalyco/rune/blob/d098d470e6f52c7d1c5025dd056cee2711ca0efb/crates/rune/src/runtime/timer_wake.rs) separates polling from drawing; [`window/presented.rs`](https://github.com/anomalyco/rune/blob/d098d470e6f52c7d1c5025dd056cee2711ca0efb/crates/rune/src/window/presented.rs) skips unchanged render work. | Skip equal cover setters, empty/open mask compositing and repeated presentation-policy work. Preserve independent invalidation for new Live pixels. |
| [`system_material/macos.rs`](https://github.com/anomalyco/rune/blob/d098d470e6f52c7d1c5025dd056cee2711ca0efb/crates/rune/src/system_material/macos.rs) changes native geometry only when needed. | Avoid setting an unchanged right-cover frame. Keep native panels and the existing NSPopover material. |
| [`frame_encoded.rs`](https://github.com/anomalyco/rune/blob/d098d470e6f52c7d1c5025dd056cee2711ca0efb/crates/rune/src/frame_encoded.rs) distinguishes drawn, unchanged and skipped work. | Add separate actual-draw, display-request, animation-timer, presentation-change and pending-capture evidence to the existing QA status. A display request is not a presented frame. |
| Explicit stop acknowledgement and retained callback ownership in [`recorder/macos.rs`](https://github.com/anomalyco/rune/blob/d098d470e6f52c7d1c5025dd056cee2711ca0efb/crates/rune/src/recorder/macos.rs) and [`display_link.rs`](https://github.com/anomalyco/rune/blob/d098d470e6f52c7d1c5025dd056cee2711ca0efb/crates/rune/src/display_link.rs). | Apply the ownership principle to Draplet's own ScreenCaptureKit pipeline. Rune's recorder uses AVAudioRecorder; it is not a reusable SCK implementation. Serialize each stream's start/stop and wait for all retiring streams on normal quit. |
| [`rune-motion/src/animated.rs`](https://github.com/anomalyco/rune/blob/d098d470e6f52c7d1c5025dd056cee2711ca0efb/crates/rune-motion/src/animated.rs) and [`layer.rs`](https://github.com/anomalyco/rune/blob/d098d470e6f52c7d1c5025dd056cee2711ca0efb/crates/rune-motion/src/layer.rs) sample analytic position/velocity when retargeting. | Keep Draplet's approved curves, quick/relaxed durations and rapid-reversal behavior. A velocity-carrying curve would need separate acceptance for overshoot, masking and native icon reflow. |
| Display-linked scheduling with idle shutdown and Low Power Mode handling. | Keep the existing transition-only 60 Hz timers. Replacing them requires ProMotion/Low Power/multiple-display evidence; current source review does not establish a pacing defect. |

## Concrete behavior changes

- `MenuMaskDrawing` invokes no background closure for a fully revealed or empty mask. Intermediate Curtain/Fade alpha and direction retain their bitmap checks.
- Equal left/right view properties schedule no new display request. A real title change still drops its measurement cache; a fresh background still refreshes views.
- Repeated right-side suppression values synchronize the cover without reapplying pin policy and status work. Readiness changes still use `configure`; actual suppression changes retain cancellation and restoration.
- Both shortcuts and native controllers retain their existing animation styles. Both cover animation loops now notice Reduce Motion becoming enabled during a transition, settle and stop the active timer. System display preferences are never changed by the regression suite.
- `CaptureLifecycle` owns every stream from before its start request through its stop acknowledgement. An early Cached frame or user stop cannot issue `stopCapture` concurrently with that stream's still-pending start. Older retiring streams remain tracked after a replacement starts.
- AppKit normal termination waits for the registry to drain, allowing Sparkle's existing termination path to continue. A three-second timeout is logged rather than blocking quit indefinitely. Stop errors are reported and counted as completed callbacks; neither errors nor timeout establish successful daemon-side cleanup.
- Capture acknowledgements and the quit deadline run in modal mode as well as common modes. [AppKit documents](https://developer.apple.com/documentation/appkit/nsapplication/terminatereply/terminatelater) that `terminateLater` runs `NSModalPanelRunLoopMode`; dispatching replies back to an occupied main queue can hang a Quit originating in a main-queue callback. The first native Live-Quit run exposed this failure, a process sample confirmed the nested loop, and a regression now reproduces that scheduling boundary.
- Failed image conversion no longer commits the fingerprint that would suppress an identical retry.

## Validation

On 2026-10-28, macOS 27.0.1 / Apple silicon:

- `bash test.sh`: **405 checks passed**, including start/stop ordering and the modal-loop scheduling regression. The initial source baseline passed 380 checks.
- Signed optimized `bash build.sh`: passed without compiler warnings. The candidate validated against the installed application's designated signing requirement; no certificate or trust settings changed. This checks signature compatibility, not independent permission-preservation acceptance.
- `python3 scripts/qa-render-lifecycle.py --app .build/Draplet.app --report .build/render-lifecycle-qa-final`: **11 native checks passed**. Cached retired its stream; 20 unchanged presentation deliveries performed no suppression transitions; 20 left and 20 right toggles converged with no animation timer.
- Live entered Quit with one pending stream and logged zero pending callbacks before exit, about **80 ms** after the request in the final run. Three startup Quit intervals (10/100/300 ms after launch setup) exited normally; the latter two had a registered stream at cleanup. Pending count does not distinguish an unfinished start from an already running stream; that exact ordering is covered by held-callback tests.
- The final 1.52-second unchanged-scene idle observation contained zero new snapshots, display requests, draws or presentation-policy transitions. A separate changing-scene run produced new snapshots and corresponding redraws. These short observations are not a universal zero-idle-drawing or energy claim.
- Native QA preference snapshots were identical before/after. It left no controlled Draplet process running and did not replace `/Applications/Draplet.app` or publish an update.

Actual commands for the candidate:

```sh
bash test.sh
DRAPLET_SIGNING_IDENTITY='Draplet Alpha Distribution' DRAPLET_SIGNING_PROFILE=alpha bash build.sh
python3 scripts/qa-render-lifecycle.py --app .build/Draplet.app --report .build/render-lifecycle-qa-final
```

The native suite requires an unlocked desktop, Draplet's existing Accessibility/Screen Recording access and no other Draplet instance. It uses process-only preference overrides, refuses to stop an existing user process, and records raw status/logs. Idle counters are observations rather than assertions because the foreground scene can change. The known main-queue Quit hang was reproduced before the modal-mode fix; its first failed run and process sample are separate local evidence.

All native counters and reports are process-local; generated artifacts stay under `.build`. The candidate was exercised as a shell-launched child, not as an independent TCC fixture. A staged Sparkle install with active capture, physical Command-drag, other macOS versions, Intel, multiple displays and long-running animated wallpapers were not revalidated in this pass. The review does not establish battery savings, exact GPU cost, long-term leak freedom or elimination of every possible ScreenCaptureKit daemon failure.

## Release follow-up — 2026-10-28

[0.5.3 Alpha / build 48](https://github.com/nggurbanov/Draplet/releases/tag/v0.5.3)
ships these changes from source commit `38164235ba167eda6b11ec60db03c110e7fd9465`.
Release acceptance subsequently closed the updater gaps above: an exact public
47 → packaged 48 Sparkle update retained both privacy grants and preferences
across independent LaunchServices launches, and the updated app's Live capture
and both curtains worked. A separate candidate-code fixture installed a staged
update on normal quit with Live capture active, drained its callbacks and stayed
closed; a later launch resumed capture and retained a settings sentinel. The
latter fixture was a shell child and does not establish independent TCC grants.
All five public downloads matched local hashes before feed activation. See
[release readiness](RELEASE_READINESS.md) for the distinct evidence scopes and
remaining hardware/long-term limits.
