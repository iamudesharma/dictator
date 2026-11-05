# AuraScribe

Offline voice dictation for macOS, built with Flutter/Dart and native Swift integration. AuraScribe lives in the menu bar with no Dock icon. **Hold either Option key to listen, then release to transcribe and insert text into the app you were using.**

Speech recognition runs on your Mac. Download the selected model once; ordinary dictation then works offline. Optional grammar cleanup and text transformations use a local text model.

## Features

- **Configurable shortcuts:** Option hold is the default. Toggle mode, modifier-only bindings, custom chords, and double/triple Control taps are also available.
- **Compact feedback:** a click-through, non-activating 104×30 point native indicator shows listening and processing animations without taking keyboard focus. Top or bottom placement and bundled feedback sounds are configurable.
- **Cross-app insertion:** captures the original application and editable field before recording. Uses native paste so browser editors receive input events, with Unicode input for the Chromium 155–156 clipboard workaround. Insertion failures preserve the transcript for Paste last recovery.
- **Local speech models:** five backend families, including a pinned GGUF catalog and custom GGUF imports. Nemotron supports true streaming; the GGUF adapter processes completed clips.
- **Output controls:** per-app pipelines, vocabulary replacements, supported decoder hints, personal commands, optional history, clipboard policies, and audio duck/mute with restoration.
- **Additional tools:** model benchmarks, meeting recording/transcription/diarization/notes, voice filtering, an optional virtual microphone, screen annotation/OCR, verified release updates, and diagnostics.

Implemented controls and compiled native paths do not establish live hardware acceptance for every feature. See the [implementation checklist](docs/implementation-checklist.md).

## Speech models

| Backend | Model/download information | Recognition and hardware |
| --- | --- | --- |
| Moonshine Tiny INT8 | About 120 MB of weights | English, clip-based CPU inference; per-clip worker in low-memory mode |
| Whisper | tiny.en/tiny/base/small: about 75/75/142/466 MB | CPU; English-only or multilingual variants |
| Nemotron-3.5 | 0.6B, ONNX INT8 | True streaming, English |
| GGUF catalog | 16 pinned artifacts, including Parakeet variants, Qwen, SenseVoice, Cohere, and Moonshine Streaming Tiny Q8 | CPU clip inference; languages depend on the model |
| Gemma 4 E2B | Large multimodal model | GPU/Metal; 16 GB system RAM recommended |

**Parakeet Unified English 0.6B Q8_0** is included as **Parakeet Unified English**. Choose it in **Settings → Speech models → GGUF speech catalog → Catalog or imported model**. Its pinned model file is approximately **731 MB**. Parakeet v3 is a separate option.

Disk size is not runtime RAM. Moonshine Streaming Tiny Q8 in the GGUF catalog is also a different model from the original Moonshine Tiny INT8 backend. Its name describes the model architecture; this app's GGUF adapter does not provide live partial transcription.

Only the selected model downloads. Model selection can trigger a download; merely starting the app does not download a model unless preload is enabled. The GGUF runtime verifies pinned catalog downloads by size and SHA-256. See the [model and runtime guide](docs/hex-redesign.md).

## Memory controls and measurements

**Settings → General → Memory → Release models when idle** is enabled by default.

- Moonshine uses a short-lived standalone worker in low-memory mode. The worker exits after each partial/final decode, reclaiming its native model allocations. Turn this setting off to keep Moonshine warm for faster repeated dictation.
- GGUF inference already uses a per-clip worker. Other resident speech/text models unload after inactivity; the default timeout is one minute. Active recording, inference, grammar, meetings, and benchmarks are protected from cleanup.
- Hidden settings UI is released while page drafts are preserved. An active modal editor stays alive until accepted or cancelled.
- Recording uses a bounded project-local PCM spool and chunked snapshots instead of retaining and repeatedly copying a growing integer list. Capture previews and benchmark reads also have bounded lifetimes/sizes.

Measurements from November 4, 2026 on an Apple silicon Mac with 8 GiB RAM:

| Measurement | Observed result | Scope |
| --- | ---: | --- |
| Final release, fresh hidden tray | **38.0 MiB median**; 37.0–38.1 MiB range | Three launches, eight-second settling period, preload off, no loaded model |
| Moonshine release worker sample | 234 MiB peak RSS | Temporary child process during one public fixture transcription |
| Parakeet v3 Q8_0 worker sample | About 1,036 MiB sampled peak RSS | Temporary child process; includes memory-mapped model pages |

**The idle figure excludes transient inference workers.** Physical footprint, RSS, model download size, and packaged app size are different measurements. These samples do not establish a fixed saving or the maximum memory for every model and recording length.

Low-memory Moonshine adds model startup time to processing. In a test-process experiment, its per-clip operation had a 707.5 ms median including worker startup, loading, and decoding; the keep-warm path decoded with an already-loaded model in 137.5 ms. These are different operation scopes, not release end-to-end dictation timings.

See [memory results, methodology, and limitations](docs/memory-results.md) and the [optimization plan](docs/memory-optimization-plan.md).

## Storage and privacy

All model weights, custom imports, inference caches, and generated runtime tools stay inside this checkout's ignored `.aurascribe/` directory:

```text
.aurascribe/
├── models/       # Downloaded and imported model weights
├── tools/        # Built inference workers and optional driver installer
├── tmp/          # Temporary audio and inference results
└── benchmarks/   # Local benchmark reports and opt-in fixtures
```

No model weights are bundled in Git. The checkout must remain accessible; there is no global model-storage fallback. Existing downloads outside this project are not moved or removed automatically.

Hugging Face tokens are stored in macOS Keychain and used for model downloads. Optional history, meetings, captures, and benchmark transcripts are local data; diagnostics exports contain lifecycle metadata rather than audio, transcripts, or tokens. Model downloads and optional update checks require network access.

## Setup

### Requirements

- macOS 13+ is the app's build target. The bundled ONNX Runtime reports a macOS 15.5 deployment target, so Moonshine/Nemotron compatibility with older macOS remains unverified.
- Flutter stable, Xcode with command-line tools, CocoaPods, Git, and CMake for the native speech runtime.
- Enough free disk space and RAM for the selected model; Gemma is intended for higher-memory Macs.

### Clone and install dependencies

```bash
git clone https://github.com/iamudesharma/dictator.git
cd dictator
flutter pub get
cd macos
pod install
cd ..
```

### Run

```bash
flutter run -d macos
```

The app starts hidden in the menu bar. Open **Settings → Speech models**, choose a backend/model, and use **Download & load** when needed. Preload is off by default.

For gated Gemma models, accept the publisher's license on Hugging Face and save a read token in **Settings → Privacy & storage → Hugging Face access**.

### Permissions

Grant **AuraScribe** access in **System Settings → Privacy & Security → Accessibility** for global shortcuts and cross-app insertion. The app's General page provides **Grant access** or **Refresh**. Microphone permission is requested when recording starts; meeting/system capture and screen annotation need their relevant macOS permissions.

A rebuilt ad hoc app can leave a stale Accessibility entry. If macOS shows the switch enabled but AuraScribe reports access denied, remove the old entry, add the exact rebuilt `AuraScribe.app`, and restart it. This grants system-wide keyboard/control access and should be done deliberately for your trusted build.

## Build and native components

```bash
flutter build macos --release
open build/macos/Build/Products/Release/AuraScribe.app
```

The native setup phases preserve Gemma companion dylibs and build/package the GGUF helper, Moonshine AOT worker, and optional virtual-microphone installer. First builds may fetch native source dependencies and compile these tools; building does not download speech weights or install the audio driver.

Optional explicit builds:

```bash
bash tool/build_transcribe_runtime.sh
bash tool/build_moonshine_worker.sh
bash tool/build_virtual_microphone.sh
```

Installing the virtual microphone requires a separate administrator action. Verified update installation requires a newer Developer ID signed release; a local ad hoc build is not a notarized distribution build.

To package the release:

```bash
bash create_dmg.sh
```

## Validation

```bash
flutter analyze
flutter test
```

At the memory-improvement revision, analysis was clean, **42 standard tests passed**, the release build passed, and strict deep code-signature verification passed. Additional opt-in checks covered 20 Moonshine isolate cycles, 20 Moonshine worker cycles, an installed Parakeet v3 fixture, and settings allocation/collection checks. No additional model weights were downloaded by that optimization work.

Memory tooling writes metadata reports under `.aurascribe/benchmarks/memory/`:

```bash
python3 tool/measure_memory.py --pid PID --seconds 30 --label tray-idle
python3 tool/benchmark_launch_memory.py --app /path/AuraScribe.app --label hidden-tray
flutter test --enable-vmservice --dart-define=MEMORY_HEAP_PROFILE=true test/settings_lifecycle_test.dart
```

Native model probes are opt-in; read each `tool/verify_*.dart` file before running it. Some older probes download project-local weights. The memory-lifecycle probe requires already-installed Moonshine weights and a supplied WAV. See [reproduction commands](docs/memory-results.md#automated-verification).

Live microphone-to-cross-app insertion was not repeated for the final memory build. Long meeting/capture sessions, virtual-microphone routing/echo quality, signed update replacement, login startup, and older-OS compatibility remain separate acceptance checks.

## Project layout

```text
lib/
├── app/             # Dictation state machine and on-demand UI
├── accessibility/   # Original-target capture and insertion bridge
├── audio/           # Recording, bounded PCM spool, audio controls
├── transcription/   # Five backend families and pinned GGUF catalog
├── grammar/         # Local cleanup, transformations, Smart Commands
├── memory/          # Activity leases, idle/pressure cleanup, editor release
├── settings/        # macOS-style sidebar settings
├── meetings/        # Capture, transcription, diarization, notes
├── capture/         # Annotation and OCR
├── hotkeys/         # Hold/toggle and customizable global shortcuts
├── output/          # Per-app pipelines and personal commands
└── shared/          # Common types, sounds, and indicator widgets
macos/Runner/        # Native panel, accessibility, audio, capture, updates
tool/                # Worker builds, verification, memory measurement
```

Implementation references: [checklist](docs/implementation-checklist.md), [design/storage/runtime notes](docs/hex-redesign.md), and [third-party notices](THIRD_PARTY_NOTICES.md). Hex inspired the interface and portions of the native tooling; AuraScribe uses Flutter for its settings UI and a native AppKit dictation indicator.
