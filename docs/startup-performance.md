# Dictation startup performance — November 13, 2026

The selected installed Parakeet Unified English artifact is 731,357,568 bytes.
The previous startup path verified its entire SHA-256 on the UI isolate before
opening the microphone. Direct measurement took 6,722 ms, matching the reported
5–8-second first-dictation delay.

Changes:

- GGUF WAV recording now starts before model preparation. Preparation runs in the
  background with the existing shared model lease; final transcription joins it.
  Hold release and cancellation remain available while preparation is pending.
- On macOS, checksums use the system `/usr/bin/openssl` SHA-256 implementation in
  a subprocess without a shell. The portable Dart verifier runs in an isolate as
  fallback. Verification remains mandatory before an installed model is used.
- Verified files are reused within this process while size, modification/change
  timestamps, permissions and expected SHA remain unchanged. There is no persistent
  trust shortcut across launches. Modified same-size files are verified again.
- The output profile file is read once instead of twice per dictation activation.
- Debug logs now include hotkey-to-recording-ready elapsed milliseconds.

Measurements on this machine (filesystem cache and concurrent load affect timing):

| Check | Measured time |
| --- | ---: |
| Previous Dart checksum, isolated run | 6,722 ms |
| Native SHA-256, standalone command | 428 ms |
| New cold validation, full-suite benchmark under load | 1,097 ms |
| New unchanged-file reuse, full-suite benchmark under load | 17.4 ms |
| Unchanged-file reuse, earlier isolated benchmark | 2.04 ms |

The cold preparation is now outside the microphone startup path. These are model
validation measurements, not live hardware microphone-start or inference timings.
Very short first clips may still wait for preparation after capture ends. Model
inference, one-time permissions, optional browser media automation and hardware
startup retain their own costs; this change does not claim all backends start in
milliseconds or change the low-memory policy to keep large models resident.

Validation: 64 standard tests plus the offline installed-model benchmark passed.
The regression suite exercises capture before a blocked model load, hold release,
audio-start cancellation, insertion errors, download recovery and same-size weight
modification. The benchmark disables network access and uses installed weights.

Reproduce: `flutter test --no-pub test tool/benchmark_model_preparation_test.dart`.
Logs are `.aurascribe/performance-tests.log`, `performance-analyze.log`, and
`performance-release-build.log`.
