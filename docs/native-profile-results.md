# Native profiling and Accelerate optimization

November 13, 2026 — Apple M1 Pro, 10 CPU cores, 16 GiB RAM.
The signed updated release is installed at `/Applications/AuraScribe.app`.
Flutter 3.50.0 / Dart 3.14.0 and direct generated C FFI remain unchanged.

The update reduces measured full-app CPU time by **24.4%** and
median file-transcription latency by **8.9%**.
Memory footprint is effectively unchanged; there is no demonstrated memory saving.
Aura still has higher RSS and CPU time than Hex, while physical footprint was
lower than Hex in this fresh-process comparison. Exact resource parity is not claimed.

## What the profiles found

**CPU:** An eight-second `sample` capture during repeated transcription placed
most speech work in `decode_rnnt_greedy`, predictor/joint GGML graphs and
`ggml_vec_dot_f32`. The old sample's function-stack summary counted 2,201 entries
through `ggml_vec_dot_f32`. These are sampled stack occurrences, not CPU percentages.
The second decoder worker also showed real `cthread_yield`/barrier activity.
Flutter raster/I/O workers mostly waited; some main-thread activity came from
tray image/menu updates and AppKit rendering.

Hex [uses one CPU decoder thread for GPU sessions](https://github.com/anomalyco/hex/blob/v3.4.0/src/transcription/gguf_session.rs),
where Aura uses two. A one-thread probe reduced CPU but increased native warm
latency from about 0.300 to 0.334 seconds. Raising thread QoS did not solve this.
Reducing polling also did not produce a useful saving. Those policies were rejected
and **two decoder threads remain**.

**Memory:** The previous huge RSS difference was not a stable private-memory gap.
With both apps restarted, the baseline warm peaks were 249.6 MiB Aura versus
218.4 MiB Hex RSS; physical footprint was 173.0 versus
190.4 MiB. RSS depends strongly on clean mapped-page residency and
OS reclamation/compression. Region snapshots found the same approximately 697.5 MiB
model-file VM object in both processes, with zero private-resident pages attributed
to those file mappings. VM-object resident counts are **not additive process RSS**.
They must not be added to the table below or interpreted as another 697.5 MiB of
private allocation per app. Aura also has Flutter-engine, compiled Dart-code,
plugin/framework and anonymous runtime mappings. This identifies categories, not
an exact attribution of every byte in the RSS difference.

Hex's older session wrapper rotates sessions to drop scratch. An experiment doing
that in Aura did not lower measured logical Metal allocations: both policies held
731,758,592 bytes after loading the model and 732,020,736 after the clip. The pinned
runtime's `SessionCore::release_scratch`/`ScratchReleaseGuard` already frees offline
scheduler/context buffers after each call. The logged approximately 87 MB Metal
scheduler buffer was a transient allocation, not proof of a retained leak. The
session-rotation change was reverted. Existing model/session reuse, idle unload
and OS-pressure leases remain; neither forced GC nor model reloading was added.
The Metal allocation probe is not total GPU or system-wide unified-memory usage.

## Change kept

The shared native runtime now uses Apple Accelerate `cblas_sgemv` for supported
contiguous **float32 matrix-vector** products. Existing GGML workers compute
disjoint output-row ranges. Tensor types, shapes, bounds, reference mode and strides
are checked first. Noncontiguous, batched/multi-vector, quantized and unsupported
operations retain their existing path. A runtime availability guard keeps the original
kernel on macOS 13.0–13.2; the modern Accelerate entry point is used from 13.3.
The dylib still targets macOS 13.0 and weak-links that symbol. Older macOS hardware
was not live-tested. Model precision, vocabulary, language hints,
output handling, timestamp generation and thread counts are unchanged.

The project-owned patch is `tool/native_patches/accelerate_gemv.patch` (SHA-256
`d3bc23e32b550a5bf2aea0fbb25da991804b3960b69e900a90906d264522a58f`). The build script prepares a content-addressed source
copy at pinned commit `7045d1c0fe7cee37747b2792977421d435e75fca`, applies the patch
there, and retains ABI 0.4.1. The `.reference/transcribe.cpp` checkout is clean.
The macro enables this path only in this project's shared native build; the
optional CLI's source remains unmodified. Both existing setup phases, Gemma
companion libraries and the Moonshine worker remain.

In the standalone 21-run probe (first excluded), native median fell from 0.300 to
0.278 seconds. Median decoder timings changed from approximately 50.1 to 38.4 ms
for prediction and 22.5 to 12.5 ms for the joint network. `/usr/bin/time` measured
3.94 versus 2.97 CPU-seconds for the complete probe processes, including setup,
so that is supporting evidence rather than a per-clip CPU measurement. The final
app's separate post-benchmark stack capture (`aura-final.sample.txt`) shows `cblas_sgemv`/Accelerate BLAS
executing in the hot decoder path.

## Same benchmark, installed apps

Same 20.0990625-second mono 16 kHz PCM16 fixture; same Parakeet Unified English Q8_0.
Both model copies were rehashed:
`4b50b6dd862bf6e346929aaf4f5eaacec003bfa3f56462d6c874b41ef2f38795`.
Audio SHA-256: `342ffafd061c00014983c4782a78d4ffa43743064d49adf3668245ec608ec6a3`.
All outputs exactly match the 50-word reference; all Aura requests report `MTL0`.

Each series starts fresh Aura and Hex processes, hides both settings windows, and
alternates ten calls per app. First calls are excluded symmetrically, leaving nine
warm observations. CPU uses kernel counters with Mach timebase conversion. Peaks
use approximately 50 ms sampling. No profiler/vmmap/build ran during these timed
series. Output processing, insertion and mic capture are outside this workload.

| Warm measurement | Before | Updated AuraScribe | Hex, final series |
| --- | ---: | ---: | ---: |
| Median transcription | 0.346 s | 0.315 s | 0.431 s |
| Range | 0.319–0.367 s | 0.303–0.352 s | 0.424–0.485 s |
| Mean CPU time per clip | 0.229 CPU-s | 0.173 CPU-s | 0.157 CPU-s |
| Mean CPU utilization (100% = one core) | 66.6% | 54.1% | 36.0% |
| Peak sampled process-tree RSS | 249.6 MiB | 250.3 MiB | 210.7 MiB |
| Peak sampled app physical footprint | 173.0 MiB | 178.0 MiB | 190.4 MiB |

CPU and latency improved together. RSS increased in this pass, while footprint
changed by 4.9 MiB. This does not demonstrate reduced app memory use.
Hex's own RSS also varied between the two fresh-process series without changes
to its code. Clean/shared mappings and compressed/private accounting differ;
neither metric fully describes GPU/unified-memory consumption. Sequential runs
cannot eliminate thermal, cache, clock and scheduler variation. Timing includes
Aura's HTTP and Hex's CLI/API transport and does not isolate native kernels.

The first updated Aura request took 1.194 seconds, peaking at
270.7 MiB RSS / 166.0 MiB footprint. This is not a cold-boot guarantee.
Live mic startup and cross-app insertion were not retested. Other catalog models
were not all live-tested, so general accuracy/hardware parity is not claimed.

## Validation and reproduction

- 336 native matrix comparisons pass against the original `use_ref` path, covering
  odd sizes, 1/2/4 threads, multiple vectors, padded row strides and F16 fallbacks.
  Float32 results use an explicit numerical tolerance; general bitwise identity
  with a different BLAS accumulation order is not claimed.
- 68 standard/real-model tests pass, including Metal recognition, native timings,
  vocabulary/output plumbing, invalid-input recovery and model close/reopen.
- Flutter analysis is clean. Release build and strict deep signature verification
  pass. The stable local signing identity remains. Existing dependency warnings remain.
- Temporary API/onboarding and Hex labs/window settings were restored; the updated
  app is running with the original preferences.

```sh
bash tool/build_transcribe_ffi.sh
bash tool/verify_accelerate_gemv.sh
bash tool/flutterw test --no-pub test tool/verify_metal_session_test.dart tool/verify_native_pcm_test.dart
bash tool/flutterw analyze --no-pub
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash tool/build_local_release.sh --no-pub
```

Opt-in probes: `tool/profile_native_speech.dart`, `tool/native_metal_memory_probe.m`
and `tool/profile_memory_regions.m`. They use existing project-local fixtures,
collect code stacks/accounting rather than memory contents, and do not install
anything. Raw measurements, summaries, profiler captures, reference-source excerpts,
probe comparisons and the exact local harness are under
`.aurascribe/benchmarks/profile-comparison/`. Final series: `after-results.json`;
baseline: `before-results.json`; aggregate: `summary.json`. Build/check logs use
`.aurascribe/tools/profile-*.log`.
