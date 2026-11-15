# Microphone WAV capture follow-up

November 13, 2026.

The reported `Use mono, 16 kHz, 16-bit PCM WAV` error came from strict WAV
validation. The exact failing recording was unavailable. Four recordings from
the previously installed release all passed validation and had the expected
Apple extensible PCM subtype, so the screenshot's specific format was not
reproduced. The existing extensible-PCM parser remains supported.

Batch microphone capture now uses the same native AVAudioEngine/AVAudioConverter
PCM stream already used by the streaming speech backends. It requests mono
16 kHz signed 16-bit samples and writes the app's canonical PCM WAV header,
instead of relying on AVCaptureAudioFileOutput's file container. This covers
GGUF without enabling repeated live inference or changing its retained Metal
model/session or overlapping model preparation.

AudioService writes into the bounded, project-local PcmSpool and finalizes its
header in place after the recorder drains queued chunks. It drops an incomplete
final sample. There is no full-recording Dart buffer or additional file copy.
Failed startup, cancellation and disposal clean up unfinished files. Finished
files retain the orchestrator's existing history/deletion lifecycle.

Validation:

- Flutter analysis: no issues.
- All 79 tests pass, including new canonical capture, final stop-time samples,
  cancellation/restart, startup-failure cleanup, bounded in-place finalization,
  real retained Metal transcription and native PCM checks.
- Signed release built and installed at `/Applications/AuraScribe.app`.
- Four live microphone recordings (requested 0.3, 1, 3 and 6 seconds) completed
  through the installed app's dictation API without errors. Each completed
  header was format 1, mono, 16000 Hz, 32000 bytes/sec, block alignment 2,
  16 bits/sample. Only header metadata and result status were retained.
- Live checks used copy-only mode with history disabled; the clipboard and all
  temporary preferences were restored afterward. The API was disabled again.
- These checks establish capture/container compatibility, not live speech
  recognition accuracy or a new performance benchmark. The real Metal fixture
  tests separately verify exact expected speech output.

Local evidence: `.aurascribe/benchmarks/wav-followup/` contains `tests.log`,
`build.log`, `recording-results.json` (before change),
`pcm-recording-results.json` (after change), and format-check scripts. No model
weights or microphone payloads are added to version control.

Full shortcut, real microphone, speech and TextEdit insertion validation is
recorded separately in [dictation-end-to-end.md](dictation-end-to-end.md).
