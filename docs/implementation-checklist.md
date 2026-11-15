# Missing Hex capabilities — implementation ledger

Implemented sequentially on `codex/hex-inspired-redesign`. All weights, imports and inference caches stay inside this project’s ignored `.aurascribe/` directory.

| Order | Capability | State | Evidence / remaining verification |
| --- | --- | --- | --- |
| 1 | Custom global shortcuts and raw dictation | Implemented | Binding validation, conflicts, transactional registration and persistence tests. Live global shortcut/AX permission journey remains manual. |
| 2 | Duck/mute other audio, restore on stop/error | Implemented | Serialized lease tests; native CoreAudio restore uses stable device UID and preserves manual volume changes. Hardware/crash recovery check remains manual. |
| 3 | Terminal paste and clipboard policies | Implemented | Native destination PID/field pinning, propagated failures, and focus-safe 104×30 native panel. Real text-only insertion into TextEdit passed after approved Accessibility refresh. Terminal-specific paste and broader app coverage remain manual. |
| 4 | Per-app ordered output pipelines and translation | Implemented | Pipeline validation/order tests; target app snapshotted before recording; local text-model transforms. User-language quality remains manual. |
| 5 | Personal commands and file editing | Implemented | Project-local JSON CRUD, command editor, Smart Commands integration and file reveal. |
| 6 | Full speech catalog and project-local custom model import | Implemented | 17 Hex 3.4 artifacts plus Moonshine Streaming Tiny Q8; pinned SHA/size verification; architecture-checked imports. Real SenseVoice and Moonshine Streaming Tiny sample decodes passed; other catalog models have not all been downloaded/run. |
| 7 | Benchmarks, decoder hotwords, keyboard input model switching | Implemented | User WAV benchmarking, project JSONL results, Parakeet vocabulary/Whisper context prompts, per-input-source model selection. RSS explicitly excludes inference subprocess memory. |
| 8 | Meeting microphone/system capture and retention | Implemented | Native ScreenCaptureKit and AVAudioEngine compile; separate normalized WAV tracks and timestamps, one-hour cap, Trash retention. Live permissions/audio journey remains manual. |
| 9 | Meeting transcription, diarization and notes | Implemented | Bounded WAV chunks, partial results/cancellation, anonymous speaker spans, Markdown/JSON and local notes. Real diarization fixture produced 10 segments across 4 speakers. |
| 10 | Voice filter, echo cancellation, preview and virtual microphone | Implemented | Native voice processing, AGC/gain/gate, preview, metering and adapted HAL driver; installer built and bundled. Driver has not been installed; routing and audio quality remain manual. |
| 11 | Annotation / capture workflow | Implemented | Region capture, Vision OCR, drawing, text/dictated notes, project history and PNG export. Screen permission and live capture remain manual. |
| 12 | Automatic release update checks and installation | Implemented | Version/release tests, digest-verified project download, idle installation, same-team signature/Gatekeeper/version checks and replacement recovery. Newer Developer ID signed release is required to exercise installation. |
| 13 | Developer Playground / diagnostics | Implemented | HUD preview, pipeline test, runtime state and metadata-only diagnostic export. No audio/transcripts/tokens in diagnostics. |
| 14 | Native acceptance, permissions and distribution gates | Open validation gates | Live mic/system capture, AX insertion/shortcuts, driver installation/activation, signed update replacement, login startup, and macOS 13/14 compatibility require separate acceptance. |

See [design, storage and verification details](hex-redesign.md). “Implemented” means wired code and controls are present; it does not imply every hardware or distribution path has been exercised.

## Hex 3.4 follow-up

See [all 72 released options, implementation boundaries and the combined acceptance checklist](hex-3.4-parity.md), plus [the local API and CLI](local-api.md). The broad implementation rows above do not establish full Hex 3.4 parity.

## Remaining interface features completed (November 13, 2026)

- General → Interface language: all 11 Hex interface languages plus System; stored separately
  from recognition language. Catalogs load on demand, with English fallback for unknown native
  errors. Transcripts, custom instructions, user titles and model identifiers remain unchanged.
- Playground → Story browser: 63 isolated, interactive fixtures, localized search, preview
  appearance/language/size, reset, local story links and Command-Shift-D. Diagnostics remain
  available in their own tab. `lib/diagnostics/story_*` never imports application services.
- Meetings → Browser-tab naming: visible-page Accessibility lookup for microphone-active
  browsers; optional bounded Automation fallback, helper-process ownership, supported-site
  naming, short-lived context recovery and protection of manually entered meeting names.
- `tool/build_localizations.py` regenerates bundled language catalogs from checked-in authored
  rows and pinned MIT-licensed Hex translations. No translation service is used at runtime.

These implementations still require the combined manual permission, hardware, model-quality
and distribution checks described in [the acceptance ledger](hex-3.4-parity.md).

## Flutter 3.50 and retained Metal speech runtime

See [direct native interop and the live Hex comparison](metal-native-interop.md).
GGUF dictation now uses generated FFI bindings, Metal with CPU recovery, retained
model/session ownership, warm-up, and the existing idle/memory-pressure policy.
