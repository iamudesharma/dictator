# Flat UI counterbalanced memory comparison

November 14, 2026. The active flat release remains the production baseline. No app source, UI package or inference implementation changed for this measurement.

## Finding

The earlier 62.4 versus 77.5 MiB post-close difference did not repeat as a consistent build difference. Across four fresh launches per build, median physical footprint at 2–8 seconds after close was **62.7 MiB historical / 63.6 MiB active**. At 24–30 seconds it was **62.9 / 63.1 MiB**. This supports keeping the flat Material/Cupertino implementation; it does not establish a need for another framework.

Both builds varied: the historical build had an 83.9 MiB early post-close run and the active build had a 71.1 MiB run. All completed runs are included. Four launches per build are too few to claim statistical equivalence or the absence of a leak.

## Results

Values are medians of the per-launch phase means, with launch-to-launch minimum–maximum in parentheses. Footprint is the macOS process physical-footprint counter, not RSS. CPU is percent of one logical core.

| Phase | Historical footprint, MiB | Active footprint, MiB | Historical CPU | Active CPU |
|---|---:|---:|---:|---:|
| Fresh tray idle | 39.2 (38.2–39.3) | 39.2 (38.1–41.8) | 0.047 (0.034–0.084)% | 0.060 (0.053–0.066)% |
| Settings idle | 83.7 (81.6–87.8) | 86.2 (82.2–90.6) | 0.021 (0.019–0.035)% | 0.024 (0.019–1.715)% |
| Settings scrolling | 124.4 (122.1–125.7) | 134.8 (122.6–138.0) | 8.053 (7.917–8.423)% | 8.997 (8.029–9.586)% |
| 2–8 s after close | 62.7 (62.6–83.9) | 63.6 (62.6–71.1) | 0.012 (0.011–0.016)% | 0.013 (0.006–0.016)% |
| 14–20 s after close | 62.8 (62.6–83.9) | 63.1 (62.8–67.1) | 0.002 (0.002–0.003)% | 0.003 (0.002–1.587)% |
| 24–30 s after close | 62.9 (62.7–84.2) | 63.1 (62.9–67.2) | 0.003 (0.002–0.004)% | 0.004 (0.003–0.007)% |


| Launch order | Build | 2–8 s, MiB | 14–20 s, MiB | 24–30 s, MiB |
|---|---|---:|---:|---:|
| 01 | historical | 62.61 | 62.64 | 62.72 |
| 02 | active | 64.33 | 63.24 | 63.33 |
| 03 | active | 62.81 | 62.86 | 62.95 |
| 04 | historical | 62.67 | 62.74 | 62.83 |
| 05 | active | 71.08 | 67.09 | 67.17 |
| 06 | historical | 62.79 | 62.83 | 62.91 |
| 07 | historical | 83.86 | 83.95 | 84.24 |
| 08 | active | 62.63 | 62.80 | 62.89 |

Matched adjacent-pair active-minus-historical differences at 2–8 seconds were +1.72, +0.14, +8.29 and −21.23 MiB. At 24–30 seconds they were +0.61, +0.13, +4.27 and −21.35 MiB. The sign is not consistent across pairs. Scrolling CPU was somewhat higher for active in this small sample (median 9.0% versus 8.1%); this is not evidence of identical performance in every phase.

## What the memory summaries show

Native `vmmap -summary` snapshots were taken only after the timed phases. They agree with the process counter: the high historical run ends at 84.2 MiB, and the other historical runs end near 63 MiB. In that high historical run, `owned unmapped` reports 21.1 MiB in its swapped column, versus zero in the preceding historical run. That is consistent with most of its extra footprint being accounted outside current resident pages. The summary does not identify the allocator or originating call stack.

The `owned unmapped (graphics)` row is identical across all eight snapshots: 8,592 KiB virtual, 112 KiB resident and 8,480 KiB swapped. The higher active run also has more untagged memory than its lower active run. These are accounting observations, not proof of a widget-level cause. There is no demonstrated extra retained graphics allocation attributable to the active UI in these summaries. Total resident mappings in `vmmap` include shared mappings and must not be interpreted as process RSS or physical footprint.

## Method and limits

- Eight separate release launches in order H, A, A, H, A, H, H, A: four adjacent pairs with balanced ordering. No app rebuild, model download, transcription or forced garbage collection occurred during measurement.
- Both bundles ran at the same `/Applications/AuraScribe.app` location, with strict deep signature verification on every install. The exact active bundle was saved before measurement.
- The historical artifact is the archived reconstructed pre-glass baseline used in the original glass comparison, not an independently archived historical shipped release. Its Dart binary hash matches the previous source audit.
- Identical test preferences: English, dark appearance, optional sidebar pages off except API, no preload or grammar, project-local storage, idle model unloading enabled. Status remained idle with no activity and no loaded Metal backend before/after every phase.
- Fresh tray idle sampled for 8 seconds after a 2-second settle. Settings opened at 960 × 720, settled for 3 seconds, then sampled for 8 seconds. Each run captured its own window and used the same 40-event down/up scroll sequence.
- Native close was followed by verification that the window actually hid. Every hide completed before the first 2-second sample boundary. Three 6-second post-close windows began at +2, +14 and +24 seconds after the close helper returned. Raw samples record actual timestamps.
- App process CPU/RSS/physical footprint came from the existing `proc_pid_rusage` helper with Mach-timebase CPU conversion. Samples within a launch are correlated; the independent repeat count is four launches per build, not the number of samples.
- The host was not rebooted or isolated from all other desktop workloads. `vm_stat` snapshots are retained. Cached resources, memory compression, reclamation and allocation timing can vary.
- The earlier 62.4 MiB was a two-run median; 77.5 MiB was a single-pass observation. Earlier protocols did not explicitly pin every optional sidebar preference. Their exact difference cannot be causally reconstructed from this rerun.
- This measures one settings open/scroll/close cycle per fresh launch, not long-term leak behavior, dictation peak memory, mic latency or transcription speed. Those workloads were not rerun for this UI-retention question.
- One initial harness attempt stopped because it checked window visibility before asynchronous close finished. It restored the active app/preferences; its partial data is preserved under `attempt1/` and excluded from the eight complete runs.

## Artifacts and restoration

Project-local evidence: `.aurascribe/benchmarks/flat-counterbalanced/` contains `run.py`, `summarize.py`, `results.json`, `results.csv`, `summary.json`, build identities, raw samples, per-run screenshots, logs, preference checks, host snapshots and native memory summaries. The benchmark-only preferences file contains the backed-up original preferences and stays in this ignored local folder.

Active Dart binary SHA-256: `2c9c0839c37d3b27b5838e4a067bcca352a4b9266e3fa7ee662446e7cbabc531`. Historical: `cc01bd87fab1bbb9d49a4f6117ac4473cd85fb85001b1b16f421c7639f0ab1b1`. Source comparison with the archived baseline differs only in `lib/app/app.dart`, `lib/shared/app_theme.dart` and `lib/diagnostics/story_browser.dart`; this is not a causal isolation of those changes.

The saved active release and original preferences were restored, preference restoration verified, and the active release relaunched. The installed Dart binary hash matches the saved active bundle and strict deep signature verification passes. No production code changes were needed; application tests/builds were not repeated for this measurement-only task.
