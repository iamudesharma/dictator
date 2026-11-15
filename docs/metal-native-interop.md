# Retained Metal speech sessions and Flutter 3.50

Latest: [native profiling and the Accelerate benchmark](native-profile-results.md).

For the subsequent CPU/memory optimization pass and corrected kernel-counter
measurements, see [the resource benchmark](resource-performance.md).

AuraScribe now uses Flutter 3.50.0 / Dart 3.14.0 and `material_ui` 1.11.0.
The speech integration uses FFIgen 23.0.0 bindings generated from the pinned
transcribe.cpp C API, with no platform channel or subprocess for GGUF decoding.
Flutter describes this integration approach in its
[native interop documentation](https://docs.flutter.dev/interop) and
[3.50 release](https://flutter.dev/blog/whats-new-in-flutter-3-50).

## Runtime and ownership

- `NativeSpeechSession` owns a worker isolate. That isolate alone owns the native
  model and session pointers, and serializes their use. Model/session handles
  never cross isolates. Heavy synchronous FFI calls stay off the Flutter UI isolate.
- The runtime requests Metal, reports the actual backend (`MTL0` in the live test),
  and supports CPU recovery when the native library returns a backend failure.
- One loaded model/session is reused between clips. Parakeet warms with half a
  second of silence during preparation, while normal dictation can already capture.
- WAV input is decoded in bounded 25-second slices without intermediate WAV files.
  Language hints, vocabulary, Whisper context prompts and native timestamps remain
  supported. Borrowed native strings are copied before the next session mutation.
- Close frees the session before the model. Existing shared activity leases protect
  loading, recording and inference; the default 60-second idle unload and OS-pressure
  cleanup remain. Moonshine's separate low-memory worker policy is unchanged.
- Generated C structs use the native initialization functions. Runtime ABI is checked
  against 0.4.1. Native sources remain pinned to commit
  `7045d1c0fe7cee37747b2792977421d435e75fca`.

Other app integrations keep their existing implementations; the direct FFI migration
here covers GGUF speech inference. C bindings fit the library's existing public API;
there is no need for a second Objective-C wrapper around Metal.

## Build and regeneration

The selected SDK lives under ignored `.aurascribe/tools/flutter-3.50.0`; other local
SDK installations remain available. `.flutter-version` and the pubspec enforce this
project's version. A fresh checkout can install the official release tag locally:

```sh
git clone --depth 1 --branch 3.50.0 https://github.com/flutter/flutter.git .aurascribe/tools/flutter-3.50.0
bash tool/flutterw pub get
bash tool/flutterw precache --macos
(cd macos && pod install)
bash tool/build_transcribe_ffi.sh
bash tool/generate_speech_bindings.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash tool/build_local_release.sh --no-pub
```

`tool/native_bindings` isolates the latest generator dependencies from the older
Gemma package's `hooks` constraint. Its lockfile makes generation reproducible.
`ffigen.yaml` is the source configuration; generated bindings are checked in.
Both existing native setup phases and the Moonshine AOT worker remain present.
The runtime setup also bundles/signs libtranscribe and its matching ggml/Metal dylibs
under `Contents/Frameworks/aurascribe-native`, with relative loader dependencies.

## Live benchmark, November 13, 2026

Installed AuraScribe and Hex 3.4.0 transcribed the same generated 20.099-second,
mono 16 kHz PCM16 speech WAV. Both model copies were byte-verified:
731,357,568 bytes, SHA-256
`4b50b6dd862bf6e346929aaf4f5eaacec003bfa3f56462d6c874b41ef2f38795`.
Output processing and text insertion were bypassed. Every output matched the reference.

Both settings windows were closed for the final pass. Ten alternating requests per
app were made; the first was excluded symmetrically, leaving nine warm observations.
RSS and CPU-time deltas were sampled about every 50 ms, without vmmap during decoding.

| Warm measurement | Updated AuraScribe | Hex 3.4.0 |
| --- | ---: | ---: |
| Median file transcription | 0.353 s | 0.453 s |
| Range | 0.336–0.370 s | 0.431–0.483 s |
| Mean CPU time per clip | 0.131 CPU-seconds | 0.116 CPU-seconds |
| Mean CPU utilization, approximate | 37.2% | 25.3% |
| Peak sampled process-tree RSS in warm series | 155.9 MiB | 105.3 MiB |

The previous CPU AuraScribe pass took 2.177 seconds warm (two observations), used
about 181% CPU and reached 1,291 MiB sampled process-tree RSS. The new warm median
is about 6.2 times faster. The previous pass used Flutter 3.47, different window
state/history, and a per-clip CPU process, so it is not isolation of one change.

The final setup pass's first AuraScribe request took 1.236 seconds and reached
266.8 MiB RSS; Hex's first request in that pass took 0.992 seconds. An earlier
new-binary/on-demand run before warm-up integration took 6.49 seconds. These are
not cold-boot guarantees: disk/shader caches, startup preloading and process histories
vary. Preparation overlaps live capture; after idle unload, another load is needed.

Times include AuraScribe's HTTP API versus Hex's CLI/API transport, so a 0.1-second
end-to-end difference does not prove the native kernels themselves are faster.
100% CPU denotes one core; GPU utilization/energy is not included. Process RSS does
not fully account for shared/Metal-managed unified-memory buffers. No claim of
267 MiB total model/GPU memory or a total-GPU-memory advantage is made.

Raw data and reference audio are project-local under
`.aurascribe/benchmarks/metal-comparison/`, with aggregate results in `summary.json`.
Temporary API/onboarding/window overrides were restored; no model downloads,
provider calls, driver installation, or external publication were performed.

## Validation

- Flutter 3.50 analysis: no issues.
- 64 standard regressions plus one real native Metal lifecycle test: all 65 pass.
- The real-model test checks repeated identical recognition, invalid input recovery,
  native segment timestamps, idempotent close, and unloading/reopening a Metal session.
- Release build succeeded (161.6 MB); strict deep signature verification passed for
  built and installed apps, using the existing stable local signing certificate.
- Parakeet Unified English was live-tested. Other catalog model quality/hardware paths
  and CPU fallback on unavailable Metal hardware were not all exercised.
- Existing dependency SwiftPM/deprecation and ONNX minimum-macOS warnings remain.

Logs: `.aurascribe/tools/metal-analyze.log`, `metal-all-tests.log`,
`metal-native-tests.log`, `metal-release-build.log`, and `metal-signing.log`.
