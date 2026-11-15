# Microphone WAV compatibility regression

November 13, 2026. Fixed in the locally built and installed AuraScribe release.

The direct speech path called `PcmWave.open`, which accepted only WAV format tag
1. The installed app's `record_macos` / `AVCaptureAudioFileOutput` microphone path
produces tag 65534 (`WAVE_FORMAT_EXTENSIBLE`), with a 40-byte fmt chunk, PCM subtype,
one channel, 16,000 Hz, 16-bit samples, 2-byte block alignment and 32,000 bytes/sec.
These are ordinary PCM16 samples; the header describes them differently.
The strict tag check rejected them before native inference. Previous performance
validation used a classic WAV fixture and missed this real recording format.

`PcmWave.open` now recognizes the extensible PCM subtype, validates the full GUID,
extension length, valid-bit depth and PCM layout, and retains classic WAV support.
Float/custom subtypes, unsupported layouts and malformed extensions remain errors.
No resampling, audio-data rewriting, model change or inference-path downgrade was
needed. The existing bounded native PCM reader consumes the correct data offset.

Validation:

- Captured format metadata from the running app's actual microphone recording;
  no microphone audio was stored in the regression artifacts.
- 71 Flutter/native tests pass. New tests cover the exact microphone fmt chunk,
  padded/odd WAV chunks, slice contents, pause compaction, classic WAVs and invalid
  subtype/extension/depth/layout rejection.
- The real Metal test decodes the known speech fixture with the microphone header
  and checks identical text plus native segment timestamps.
- Installed release: actual mic start → two-second capture → stop → transcription
  returned idle with no error. This quiet capture returned no speech text. Copy-only
  mode was temporarily enabled for this check; no text was inserted into an editor.
- Installed release's file API transcribed all 50 reference words exactly from the
  Apple-format fixture on `MTL0`, with timestamps.
- Analysis is clean; release build and strict deep signature verification pass.
  Temporary API/onboarding/copy/history test preferences were restored, and the
  fixed app is running with its original preferences.

Regression tests: `test/pcm_wave_test.dart`, `test/support/wav_fixtures.dart` and
`tool/verify_metal_session_test.dart`. Local metadata/validation results live in
`.aurascribe/benchmarks/wav-regression/`; logs use `.aurascribe/tools/wav-*.log`.
