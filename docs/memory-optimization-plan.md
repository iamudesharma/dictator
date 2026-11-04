# AuraScribe memory optimization plan

Prepared 2026-11-04; implemented in this checkout. See [measurement results and acceptance limits](memory-results.md). No additional model weights were downloaded.

## Baseline and measurement

The earlier release-process snapshot reported 247.7 MiB physical footprint and
295.1 MiB lifetime peak. It was not a controlled benchmark and does not establish
how much is Dart, the Flutter renderer, a loaded model, or native allocations.
The installed Moonshine weights occupy about 118 MiB on disk; disk size is not RAM.

First record a repeatable baseline on this Mac, with the same release build,
model, audio fixture, window state, and feature settings. Run each case three
times, retaining the median and range. Observe at launch, after settling, while
busy, and after the idle timeout. Record:

- macOS physical footprint and peak for AuraScribe; subprocess RSS separately.
  RSS and footprint are different metrics. Do not add RSS to footprint or sum
  independent process lifetime peaks and call that a simultaneous total.
- A synchronized process-tree RSS trace during GGUF inference, including the
  helper, and macOS allocation/VM evidence for major native/GPU categories.
- Dart heap/external allocations and snapshot differences in a separate profile
  build using DevTools. Confirm final savings in release, not from debug numbers.
- Model load time, press-to-ready delay, and release-to-insert latency, including
  first use after an idle unload. Keep test audio/transcripts project-local.

Cases: fresh hidden tray without a model loaded; settings open/closed; Moonshine
loaded; short and maximum-length dictation; repeated partial and final decodes;
optional grammar use; capture open/export/close; meeting start/stop/cancel.
Test Parakeet only when the user has downloaded it; do not download it for this plan.

## 1. Release native inference resources when idle

Priority: high. Files: `lib/transcription/transcription_service.dart`,
`moonshine_transcription_backend.dart`, `sherpa_nemotron_transcription_backend.dart`,
`lib/grammar/grammar_model_service.dart`, and the orchestrator.

Moonshine owns a persistent worker/recognizer after loading. The optional grammar
service also retains its native model until explicitly unloaded. Add a shared
activity/lease policy for dictation preparation, recording, partial/final decode,
grammar, Smart Commands, meetings, benchmarks and other inference consumers.
An idle timer may unload only after the last active operation finishes. A new
operation cancels unloading or waits for it before reloading; it must never use
a freed recognizer or load a duplicate copy. Switching engines must serialize
with these transitions.

Offer a low-memory idle timeout, initially 60 seconds, and a keep-warm preference.
Keep existing preload-off behavior. Benchmark the timeout before choosing its
shipping default; preserve audio and the current release-during-preparation
semantics. Do not claim instant readiness after unloading.

The GGUF helper already exits after each clip: preserve that behavior rather
than adding a redundant idle-unload mechanism for it. Check graceful worker
shutdown actually finishes native `free()` calls before terminating an isolate;
the current Moonshine worker acknowledges shutdown before its final cleanup.
Native allocators can retain freed pages, so explicit disposal is necessary but
does not guarantee an equal immediate reduction in physical footprint.

Verification: idle expiry, new work at expiry, engine switch during load/unload,
grammar sharing, meeting activity, errors and cancellation. Repeat model cycles
and check retained allocations and latency.

## 2. Reduce audio storage and repeated full-clip copies

Priority: high. File: `lib/app/dictation_orchestrator.dart`.

The current path appends PCM bytes to a growable `List<int>`. Every 800 ms,
clip-based partial recognition copies the accumulated audio into `Uint8List`,
then copies it again into a WAV buffer. Final recognition repeats the process.

Replace the general integer list with typed chunks and an explicit byte bound
derived from the recording limit. Stream PCM to a project-local WAV spool and
update the header when finalizing; avoid a second full WAV-sized memory buffer.
Native partial recognition still needs a stable snapshot: serialize snapshots,
allow at most one outstanding decode, and coalesce pending ticks. Do not truncate
the recognizer's required audio context merely to reduce memory. For true
streaming, remove retained full-clip audio only after proving no fallback uses it.

Keep passing file paths to Moonshine's worker: it already avoids transporting
PCM through isolate messages. If a future interface passes audio bytes, evaluate
`TransferableTypedData`; construction still copies bytes and must be measured.

Verification: maximum duration, rapid release/cancel, partial-final ordering,
last-word preservation, byte limits, file cleanup, and unchanged fixture output.
Measure peak memory and allocation rate, not just resting memory.

## 3. Release hidden settings UI state

Priority: medium. Files: `lib/app/app.dart`, `settings/settings_screen.dart`,
and window visibility integration.

The Flutter home builds SettingsScreen even when the native window is hidden.
Track explicit window visibility, including title-bar close, tray reopen, and
Smart Commands transitions. Unmount the settings subtree while hidden, retaining
only intentional navigation/draft data in small state objects. Do not lose
unsaved edits or stop background meetings/downloads owned by shared controllers.

While visible, load data for the selected page rather than loading profiles,
commands, custom models, benchmarks, devices and storage metadata together in
every `_loadSystemState` call. Coalesce overlapping refreshes. Limit rebuilds from
audio-level notifications to the widgets that need them. Disable widget-aware
tickers while hidden; separately stop timers/subscriptions where appropriate.
TickerMode saves animation work; it does not dispose widgets or arbitrary timers.

Unmounting UI does not unload the Flutter engine or Dart runtime. Measure its
actual benefit before expanding this change.

Verification: 20 settings open/close/navigation cycles with heap diffs; draft and
selection restoration; no duplicate listeners or frame scheduling while hidden;
background capture and dictation continue normally.

## 4. Bound image and native resource lifetimes

Priority: medium; potentially most useful after capture/annotation.

Measure decoded image/cache sizes, native audio buffers, recognizers/sessions,
ports, subscriptions and timers across success/error/cancel. Dispose resources
at the owning feature's end. Annotation export already disposes its `ui.Image`;
sherpa's Dart `readWave` wrapper already copies samples and frees the native WAV.
Do not label those existing paths as confirmed leaks.

Decode previews at their displayed size while preserving original export
quality. If image measurements justify it, trial a 16–32 MiB image-cache budget.
The cache limit is not a fixed reservation, so lowering it saves nothing when
the cache is already smaller. Remove image listeners/owners when closing the
feature; `clearLiveImages()` does not free images still held elsewhere.

History is already capped at 100 entries and ActivityLog at 200: preserve those
bounds rather than treating them as unlimited leaks. Inspect retained annotation
data and meeting results and use bounded/paged loading where measurements warrant.

## 5. Native inference allocations and dependencies

Priority: measurement-dependent.

If native model buffers dominate after the lifecycle/audio fixes, inspect ONNX
session allocators and documented binding controls for arena/thread settings.
Change one supported option at a time and compare memory, output and latency.
If allocator retention prevents idle recovery, evaluate a short-lived native
helper for ONNX as a separate spike; killing an isolate alone is not evidence
that native allocations were freed.

Audit eagerly initialized plugins and loaded native libraries with VM evidence.
Unused dependencies and smaller app bundles do not automatically translate to
lower RAM. Make optional services lazy where the profile establishes a benefit.
Keep Gemma dylib/runtime build phases intact. Model replacements are a separate
quality benchmark, not an assumed Flutter memory fix.

## Acceptance and sequencing

Implement in separate reviewable changes: measurement, idle lifecycle, audio
buffers, hidden UI, then evidence-driven cache/native tuning. Re-measure after
each and keep changes that produce useful repeatable savings.

Initial engineering target: investigate a 20% reduction in comparable unloaded
tray footprint, subject to the controlled baseline. This is a target, not a
prediction. Also require a lower maximum-duration dictation peak, no continuing
growth after warm-up over 20 dictation/settings cycles, unchanged fixture text,
and reported cold-start latency tradeoffs. Agree a latency budget from the
baseline before enabling unloading by default. Preserve hold/release, focus-safe
insertion, recovery, clipboard restoration and project-local storage.

Use `flutter analyze`, relevant lifecycle/buffer regression tests, a release
build, DevTools retention checks and native manual acceptance. Do not force GC
in production or clear caches periodically to disguise retained owners. Do not
promise a total footprint below 100 MiB from Flutter widget changes.

If Flutter engine/native baseline still dominates after these steps, separately
evaluate a native background host with Flutter settings launched on demand.
Current orchestration/hotkeys run in Dart, so destroying the engine is an
architecture change requiring service ownership and IPC work; it is not part of
the initial optimization pass.

## Official guidance consulted

- Flutter DevTools memory view: https://docs.flutter.dev/tools/devtools/memory
- Flutter performance profiling: https://docs.flutter.dev/perf/ui-performance
- Flutter rendering/buffer best practices: https://docs.flutter.dev/perf/best-practices
- TickerMode scope: https://api.flutter.dev/flutter/widgets/TickerMode-class.html
- Dart transferable buffers: https://api.dart.dev/dart-isolate/TransferableTypedData-class.html
- Image cache budget: https://api.flutter.dev/flutter/painting/ImageCache/maximumSizeBytes.html
- Image cache clearing limitations: https://api.flutter.dev/flutter/painting/ImageCache/clearLiveImages.html
