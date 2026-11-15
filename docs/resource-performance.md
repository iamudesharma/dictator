# Resource optimization and repeat benchmark

Latest: [native profiling and the Accelerate benchmark](native-profile-results.md).

November 13, 2026. The updated signed release is installed and running at
`/Applications/AuraScribe.app`. Flutter 3.50.0 / Dart 3.14.0 are unchanged.

The repeated benchmark preserves fast transcription, but **does not establish
whole-application CPU or memory savings or resource parity with Hex**.

## Changes retained

- GGUF file transcription reads bounded slices from the original WAV. It no longer
  scans/copies each slice to a temporary WAV and then rereads it for inference.
  Other STT backends retain their existing fallback path.
- A small project-owned C helper reads/converts PCM16 directly into caller-owned
  native float storage. Its temporary PCM allocation is freed before inference;
  those audio bytes no longer allocate on the Dart heap. Reads remain bounded at
  25 seconds. Generated FFIgen bindings call it on the existing speech isolate.
- Silence detection uses exact integer squared-sample accumulation and the original
  energy threshold. Normal dictation still bypasses the file API's silence gate.
  Requested timestamps remain relative to each slice and receive original-file offsets.
  Empty recognizer output remains distinct from a skipped silent slice.
- Tray updates resolve the final icon once and skip identical image uploads.
  Native updates are serialized to preserve the final icon across rapid transitions;
  menus and tooltips still update on each request.
- Model/session reuse, Metal selection, CPU fallback, vocabulary, language mapping,
  timestamps, output processing, idle/pressure cleanup and other engines remain.
  Decoder parameters, quantization and model quality were not changed.

## Same model/audio, installed applications

Both copies of Parakeet Unified English Q8_0 were reverified against SHA-256
`4b50b6dd862bf6e346929aaf4f5eaacec003bfa3f56462d6c874b41ef2f38795`. The same 20.0990625-second, mono 16 kHz PCM16 fixture has
SHA-256 `342ffafd061c00014983c4782a78d4ffa43743064d49adf3668245ec608ec6a3`. Every transcript exactly matches its 50-word reference.
Aura reports `MTL0` throughout. Hex is the installed 3.4.0 release.

Ten alternating requests per app, first excluded symmetrically, give nine warm runs
per series. Both settings windows were closed; processing/insertion was bypassed.
The previous release and final release each used a fresh Aura process. Hex retained
its process and loaded model across these sequential series.

| Warm metric | Before these optimizations | Updated AuraScribe | Hex, final series |
| --- | ---: | ---: | ---: |
| Median transcription | 0.334 s | 0.342 s | 0.435 s |
| Range | 0.324–0.370 s | 0.328–0.367 s | 0.424–0.470 s |
| Mean CPU time per clip | 0.225 CPU-s | 0.230 CPU-s | 0.166 CPU-s |
| Mean CPU utilization | 65.8% | 66.7% | 37.9% |
| Peak sampled process-tree RSS | 266.5 MiB | 283.2 MiB | 105.1 MiB |
| Peak sampled app physical footprint | 173.6 MiB | 174.5 MiB | 165.4 MiB |

Updated Aura's median is 21.5% shorter than Hex's, but CPU time is
39.1% higher and peak RSS remains substantially higher. Physical footprint is
closer, still higher in this series. The before/final Aura differences are small for
latency/CPU/footprint and do not support an improvement claim. Peak RSS increased
in this pass. Exact parity would require further profiling; these changes alone do
not deliver it.

The final setup request took 1.172 s and peaked at
274.4 MiB sampled RSS / 169.2 MiB footprint.
Hex's setup request in that series took 0.497 s. These are setup
observations with existing OS/shader caches, not guaranteed cold-start times.
Live microphone startup and cross-app insertion were not remeasured here.

## Measurement details

CPU uses `proc_pid_rusage` user/system counters immediately before/after each
request, converting Mach ticks with `mach_timebase_info`. A controlled 0.200026-second
CPU burn measured 0.200024 seconds. This avoids the coarse sampling/rounding of the
older `ps` CPU estimates; older CPU percentages must not be directly compared with
these corrected measurements. 100% means one core; GPU activity and CLI/API-client
CPU are excluded. No model subprocesses were observed for either app.

RSS and app physical footprint were sampled about every 50 ms using `ps` and
`proc_pid_rusage`, without blocking `vmmap` during decoding. Footprint includes
compressed/private accounting that RSS alone misses; shared/Metal buffers complicate
both. Neither figure represents complete GPU/unified-memory consumption. Sampling
can miss very short peaks. OS compression, clock/thermal state, startup history,
disk/shader caches and differing API/CLI transports remain uncontrolled factors.

## Isolated preprocessing check

`tool/benchmark_pcm_conversion.dart` reproduces the old silence-scan/temp-WAV/read/
Dart-conversion path versus the new native path, without inference or Flutter/tray work.
Both use one compiled Dart AOT executable, the same fixture and 200 iterations:

| Process measurement | Old path | Native path |
| --- | ---: | ---: |
| User + system CPU, `/usr/bin/time` | 0.34 s | 0.06 s |
| Peak RSS | 24.3 MiB | 18.7 MiB |
| Peak physical footprint | 15.2 MiB | 9.5 MiB |

Output checksums match. This demonstrates cheaper preprocessing (about 1.4 ms CPU
saved per clip in this isolated run), **not** those savings for the complete app.
Inference/runtime work dominates the full benchmark, where no CPU saving is resolved.

## Validation and artifacts

- Analysis: no issues. 68 tests pass, including native PCM equivalence at both sides
  of the silence threshold, slice bounds, real Metal recognition, timestamp offsets,
  output processing, missing-input recovery, close/reopen and tray transition ordering.
- Signed release build and strict deep signature verification pass. The existing
  stable local signing identity is retained. Existing dependency warnings remain.
- The temporary Aura API/onboarding overrides and Hex labs/window settings were
  restored; the updated app is running with its original preferences.
- Other model families and hardware-dependent features were not all live-tested.

Raw series, aggregate `summary.json`, harness and PCM logs are under
`.aurascribe/benchmarks/resource-comparison/`. Final series: `final-tray-results.json`;
baseline: `precise-before.json`. Earlier exploratory series are retained there and
are not substituted for the final measurements. Build/test logs use the
`.aurascribe/tools/resource-*.log` prefix.
