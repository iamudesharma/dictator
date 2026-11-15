# Liquid Glass performance comparison

Historical report: Liquid Glass was removed on November 14, 2026. The current
app uses the flat external Material/Cupertino UI. See [flat-ui.md](flat-ui.md).

Measurements recorded November 13, 2026 (IST); report finalized November 14.

The design is **not performance-neutral**. Idle CPU stayed essentially unchanged,
but opening and scrolling settings used more memory and CPU than the flat UI.
I reduced the glass rendering cost and installed the measured final build.
It still retains about 58 MiB more physical footprint after closing settings.

The final median transcription time was 0.485 seconds versus 0.459 seconds for
the flat UI: an observed 26 ms / 5.7% increase in this small sample. Run ranges
overlap, so this does not establish a consistent recognition slowdown, and it
also does not prove zero impact. All controlled file transcripts matched exactly,
and all eight real microphone/shortcut/insertion tests completed successfully.

## Measured results

| Metric | Reconstructed flat UI | Initial Liquid Glass | Final tuned glass |
| --- | ---: | ---: | ---: |
| Fresh tray idle physical footprint | 38.5 MiB | 39.1 MiB | 39.8 MiB |
| Settings idle CPU | 0.021% | 0.018% | 0.021% |
| Settings idle RSS | 126.8 MiB | 150.6 MiB | 144.3 MiB |
| Settings idle physical footprint | 83.6 MiB | 177.9 MiB | 145.4 MiB |
| Scrolling CPU | 8.64% | 10.70% | 11.00% |
| Scrolling sampled peak physical footprint | 151.9 MiB | 300.4 MiB | 246.3 MiB |
| Tray footprint after settings closes | 62.4 MiB | 156.3 MiB | 120.8 MiB |
| Retained-model transcription of the 20.099 s file | 0.459 s | 0.459 s | 0.485 s |
| CPU work per file transcription | 0.162 CPU-s | 0.201 CPU-s | 0.172 CPU-s |
| File-transcription sampled peak footprint | 172.7 MiB | 255.6 MiB | 220.8 MiB |
| Shortcut → recording, observed | 0.463 s | 0.427 s | 0.522 s |
| Release shortcut → insertion finished / idle | 1.430 s | 1.443 s | 1.306 s |
| Live-dictation sampled peak footprint | 184.2 MiB | 281.9 MiB | 239.3 MiB |

State CPU and non-peak memory entries are medians of two runs' phase averages.
Transcription entries are medians of 16 requests per primary build. Peak entries
are the highest sampled value across both launches. CPU uses Activity Monitor's
one-core convention: 100% is one fully occupied core, not the entire machine.
RSS and physical footprint are different macOS accounting measures and must not
be substituted for each other. Figures include app-owned native/graphics memory;
they do not represent total machine or WindowServer/GPU-driver memory.

The tuning reduced settings idle footprint by 18.3% and the sampled scrolling
peak by 18.0% compared with the initial glass build. It did not bring either
measure back to the flat baseline, and scrolling CPU did not improve.

## What was changed

Only the app-owned glass adapter changed during tuning:

- Resolve and cache the flat-pane themes, including reduced-motion variants.
- Remove the additional saturation filter and blurred inner-shadow pass for
  these rectangular window panes.
- Keep the 16-sigma backdrop blur, tint, edge treatment, compact layout and
  shared capture for the non-overlapping header/sidebar.

An intermediate ungrouped-capture candidate reached a 367.8 MiB scrolling peak,
so it was not selected. Its measurements are retained separately in the evidence.
No speech precision, decoding, audio capture, model-memory policy, model catalog
or existing feature was removed or changed. No forced production GC was added.

## Controls and interpretation

The available archived apps predated other fixes, so the flat baseline was
reconstructed in an isolated checkout from the current source by reversing only
the three glass UI source changes and removing the glass dependency. Every other
application source and native Runner source was checked for identity. Other
resolved dependency versions matched. Native speech-library hashes matched.
This is a controlled reconstruction, not an exact archived previous release.

Both builds used the same project-local storage and installed app path, release
configuration, Flutter 3.50 / Dart 3.14, signing identity, Parakeet Unified English
Q8_0 weights, Metal (`MTL0`), English, and the same 50-word mono 16 kHz PCM fixture.
The host was an Apple M1 Pro, 16 GiB RAM, 10 logical CPUs, macOS 27.0.

The initial comparison ran flat → initial glass → initial glass → flat. Each
fresh process measured tray idle, settings idle, identical generated scrolling,
settings close/disposal, a live dictation, eight retained-model file requests,
and model-resident idle. Tuned candidates were measured afterward in two fresh
processes each; those later runs were not counterbalanced with another flat run.
This and ordinary desktop activity limit attribution of small timing differences.

The live tests sent the Option shortcut through macOS keyboard events, played the
reference WAV through the built-in speakers into the built-in microphone, stopped
by releasing Option, and verified actual text insertion plus saved file contents
in a dedicated TextEdit document. The driver never typed the transcript. The
clipboard was verified restored. Shortcut-start values include modifier debounce,
audio setup and status polling; they are not hardware first-sample latency.
Release-to-idle includes recognition and the native paste/clipboard settling time.

File requests used the installed app's loopback API with output processing off.
These timings include request handling and recognition, rather than only a native
kernel. All 96 timed file requests across the primary builds, intermediate
candidate and speech-only controls returned the exact reference text on `MTL0`.
All eight live dictations inserted and saved text, with 0–1 word differences out
of 50 from acoustic playback. The final two live runs had zero normalized word
errors. No WAV-format or insertion error occurred in these completed tests.

A separate fresh-launch control never mounted settings. With a warmed model,
the flat and ungrouped glass candidate measured 0.471 / 0.465 s median wall time
and 0.157 / 0.158 CPU-s per request. This supports separating the recognition path
from costs associated with using the glass settings window. This control used the
intermediate candidate; it must not be presented as a fresh-launch measurement
of the final tuned build or proof of a particular GPU-allocation mechanism.

Memory was sampled with `proc_pid_rusage` approximately every 20–25 ms. CPU
counters were converted using the Mach timebase and checked against a known CPU
interval. No intrusive vmmap sampling ran during the timed phases. Peaks are
sampled peaks, not guaranteed lifetime maxima. These are small local tests on one
Mac, not a statistical guarantee for every workload, model or OS release. GPU
utilization, power draw and frame-rate performance were not measured.

## Installed state and evidence

The final measured tuned app is installed and running. Its Dart executable hash
matches the measured bundle. Strict deep signature verification passes; all 85
tests pass and Flutter analysis is clean. Original model and preferences were
restored and verified, and the temporary loopback API is disabled.

Evidence is under `.aurascribe/benchmarks/glass-performance/`:

- `comparison.csv`, `summary.json`, `fresh-summary.json` — comparison tables.
- `results.json` — initial counterbalanced runs.
- `optimized-results.json` — rejected ungrouped candidate.
- `tuned-results.json` — final tuned build.
- `fresh-results.json` — settings-never-mounted control.
- `source-audit.json` — source/native identities, fixture and binary hashes.
- `benchmark*.py`, `ui.swift`, `dictate.swift` — reproducible measurement drivers.
- `*-settings.png`, `live-*.json`, `*-app.log` — native UI and live test evidence.
- `tuned-tests.log`, `tuned-analyze.log`, `tuned-build.log` — final validation.
- `current-preference-verification.json` — read-only restoration check.

One incomplete initial attempt stopped at a window-focus guard. Its data is kept
in `attempt1/` and excluded from the comparison; the app did not crash and the
harness restored the installed app and settings before retrying.
