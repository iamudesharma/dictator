# Memory improvements and verification

2026-11-04, this Apple silicon Mac with 8 GiB RAM. The optimization work did not
download, change or delete model weights. Final inspection found Moonshine Tiny
INT8 and a Parakeet v3 Q8_0 model installed; the saved selection is the GGUF
backend with its Parakeet v3 default, and preload is off. That selection is
preserved. The Moonshine probes below test that available backend separately.

## Implemented

- One shared activity fence protects preparation, recording, inference, grammar,
  Smart Commands, meetings and benchmarks. Idle cleanup waits for current work;
  arrivals wait for an in-flight unload before inspecting or using a model.
  Model switches and inference are serialized. Native getters no longer create
  backend objects merely to display idle state.
- General → Memory defaults to low-memory mode. Moonshine runs in a standalone
  Dart AOT worker that exits after every partial/final decode, so its ONNX
  allocations leave the app process entirely. Keep-warm mode retains the isolate
  implementation for lower repeat latency. Existing GGUF per-clip processes are
  preserved. Other resident models use a configurable idle timeout (60 seconds
  by default); OS memory pressure requests cleanup after active work finishes.
- Moonshine's isolate acknowledges shutdown after freeing native resources.
  Nemotron warm-up frees its stream on exceptions. Selected Gemma STT is reloaded
  and reused for text tasks after idle cleanup instead of silently choosing a
  second text model. Inference/session settings and model quantization are unchanged.
- PCM goes to a bounded project-local disk spool instead of a growing integer
  list. Immutable partial WAV snapshots copy at most 64 KiB at a time, keep the
  full required audio prefix, and serialize with final decoding. Enhanced-accuracy
  mode no longer performs unused periodic partial decoding. Limits, errors and
  cancellation clean up files; crash leftovers in the dedicated spool expire
  conservatively after 24 hours.
- The settings MaterialApp is created on demand and released while hidden.
  Page data loads only where needed, refreshes coalesce, and microphone-level
  events no longer rebuild hidden settings. Main page drafts survive and modal
  editors deliberately keep their UI alive until accepted/cancelled. Native close
  gives widget disposal a frame before hiding the window. A small closed input
  client replaces Flutter's last editor reference without showing a keyboard.
- Capture previews decode at the existing export panel's resolution and evict
  their own cache entry on disposal. Original capture files remain unchanged.
  Diarization passes the native WAV allocation directly to the native processor,
  removing a full-duration Dart float copy and a second native input copy.
- Benchmark input size is checked before reading; input copying streams through
  the filesystem. Recent benchmark results read at most a 512 KiB tail, rather
  than the entire append-only file. Existing history/log bounds are preserved.

## Release launch measurements

`tool/benchmark_launch_memory.py` launches an app three times, settles for eight
seconds per run, and queries macOS `vmmap -summary`. No microphone or transcription
is involved. The before bundle was preserved before rebuilding. These runs were
sequential on a machine in use, not an alternating controlled lab experiment.

| Scenario | Median physical footprint | Range | Scope |
| --- | ---: | ---: | --- |
| Before, settings open | 104.7 MiB | 78.0–124.4 MiB | Original release, fresh launch |
| Optimized, settings open | 77.8 MiB | 72.2–83.8 MiB | Intermediate optimized build before final UI teardown refinement |
| Final build, hidden tray | **38.0 MiB** | **37.0–38.1 MiB** | Fresh launch, no loaded model |

The settings-open median was about 26% lower in these observations, but ranges
are noisy and this is not proof of a fixed percentage saving. The earlier 247.7
MiB session snapshot and 295.1 MiB lifetime peak were taken after other activity;
they are not the same baseline as a fresh hidden launch. Settings were not
locked against user changes during this work, so the historical settings-open
comparison is indicative rather than a matched model-selection benchmark. The final hidden-tray runs use the final runtime sources. The packaged app grew from
143.5 MB to 149.5 MB because it includes the worker; disk size is separate from RAM.

## Inference and lifetime checks

The installed Moonshine model transcribed the same public upstream WAV through
20 isolate load/decode/idle-unload cycles and 20 process-worker cycles. Every
cycle returned identical fixture text. No model weights were downloaded for
these probes; only the public test audio was fetched into project storage.

| Diagnostic | Median load/preparation | Median transcription operation |
| --- | ---: | ---: |
| In-process isolate | 420.5 ms model load | 137.5 ms decode with loaded model |
| Per-clip worker | 10.5 ms path preparation | 707.5 ms including worker start, model load and decode |

These are Flutter test-process measurements under varying memory pressure, not
release end-to-end dictation latency. The process path adds repeat processing
latency in exchange for returning native allocations when each worker exits.
The bundled release worker also passed the same sample: one observed cold-ish
run took 1,239 ms wall time (876 ms model load, 174 ms decode) and reported a
234 MiB worker peak RSS. This transient child memory is **not included** in app-only
RSS or the fresh hidden-tray figures. Do not sum separate lifetime peaks and call
that a simultaneously observed total.

The isolate test showed native allocator retention despite recognizer disposal;
this motivated the process implementation. Test-runner RSS is affected by GC,
compression and instrumentation, so its absolute values are not production app
footprint measurements.

The already-installed Parakeet v3 Q8_0 also passed the same public fixture
through the existing CPU worker and exited normally. One sampled run took
2,903 ms wall time and reached approximately
1036 MiB sampled worker RSS (100 ms sampling).
This includes memory-mapped model pages and is not the app's idle physical
footprint. It demonstrates why a small tray figure does not mean transcription
never needs substantial transient memory. No Parakeet weights were fetched by
the probe.

## Automated verification

- `flutter analyze --no-pub` is clean; all 42 standard tests pass. Tests cover activity leases/pressure, arrival during
  unload, load-state races, serialized model switching, bounded PCM snapshots,
  byte continuity/sample alignment, benchmark read limits, settings navigation,
  hold/release, focus-safe insertion error recovery and storage boundaries.
- Twenty settings close/reopen cycles preserve unsaved vocabulary, remove service
  listeners and unmount the UI. The normal test run also checks hidden modal retention
  until the editor completes.
- Both opt-in settings allocation tests pass, with zero settings states and
  text-editing controllers after the lifecycle test scope. VM profiling uses the same `getAllocationProfile` RPC exposed
  by DevTools, plus optional class-only retaining paths. It stores aggregate sizes
  and class/field names, never object values, full heap dumps or credentials.
  Counts collected inside the async test body can include test-scope references;
  the collectible-state assertion runs after that scope. Modal behavior is
  checked separately from the 20-cycle allocation experiment. No forced GC exists in production code.
- The 149.5 MB macOS release build and strict deep code-signature verification pass for the app
  and bundled native/AOT helpers. This remains a local ad hoc developer build.

Reports are ignored under `.aurascribe/benchmarks/memory/`. Reproduce with:

```sh
python3 tool/measure_memory.py --pid PID --seconds 30 --label tray-idle
python3 tool/benchmark_launch_memory.py --app /path/AuraScribe.app --label hidden-tray
flutter test --enable-vmservice --dart-define=MEMORY_HEAP_PROFILE=true test/settings_lifecycle_test.dart
# Installed Moonshine weights and an existing public/sample WAV are required:
flutter test --dart-define=SHERPA_LIBRARY_DIR=/path/AuraScribe.app/Contents/Frameworks \
  --dart-define=MEMORY_FIXTURE=/project/.aurascribe/benchmarks/memory/fixture.wav \
  --dart-define=MEMORY_PROCESS_WORKER=true tool/verify_memory_lifecycle.dart
```

## Limits and decisions

Live microphone → cross-app insertion and long meeting/capture hardware paths
have not been repeated for this final memory build. The original native focus
panel and insertion strategy were preserved. Real device/permission acceptance
remains necessary, particularly after the ad hoc signature changes on rebuild.
Full retained-heap profiling of live meetings and captures is still manual;
fixture/GC tests are not proof that every native feature is leak-free.

No global image-cache budget was arbitrarily reduced: a cap is not a reservation
and no evidence established a useful global saving. No undocumented ONNX arena
flags, dependency-cache modifications, forced production GC, model replacement,
or native-host rewrite was introduced. The existing binding's two CPU threads
were preserved. A separate native background host was explicitly outside the
plan's initial pass; the Flutter engine remains alive for Dart-owned services.
The existing ONNX runtime still emits its macOS 15.5 deployment warning when
linking the macOS 13 target, so older-OS compatibility remains an existing gate.

Official guidance: [Flutter memory tools](https://docs.flutter.dev/tools/devtools/memory),
[rendering allocation guidance](https://docs.flutter.dev/perf/best-practices),
[VM allocation profiles](https://api.flutter.dev/flutter/vm_service/VmService/getAllocationProfile.html),
[image-cache ownership limits](https://api.flutter.dev/flutter/painting/ImageCache/clearLiveImages.html).
