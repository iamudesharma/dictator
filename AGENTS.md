# AGENTS.md — AuraScribe (voice_to_text)

## What This Is

macOS-only Flutter menu bar app for offline voice dictation. Runs in the system tray with no Dock icon (`LSUIElement`). Five STT backend families: Gemma 4 E2B (GPU), Whisper (CPU), Nemotron-3.5 (streaming), Moonshine Tiny INT8 (CPU), and a pinned native GGUF speech catalog. Optional grammar cleanup via Gemma 3 270M LLM.

## Build & Run

```bash
# Debug
flutter run -d macos

# Release
flutter build macos --release

# After dependency changes (required for native pods)
cd macos && pod install && cd ..

# If Gemma dylib errors occur after update
flutter clean && flutter pub get && cd macos && pod install
```

**No custom lint, typecheck, or test commands.** Standard Flutter analysis:
```bash
flutter analyze
flutter test
```

## Critical Gotchas

- **Models download on first use** from Hugging Face to `<project>/.aurascribe/models/`. Inference caches also stay under `<project>/.aurascribe/`; never fall back to a global directory. No model files in repo (`.gitignore` excludes `*.litertlm`).
- **Gemma STT requires 16 GB RAM** recommended. Whisper works on 8 GB.
- **Hugging Face token** may be needed for gated Gemma models. Set in app Settings → Hugging Face.
- **macOS 13.0+** required (set in `Podfile` and `pubspec.yaml`).
- **Podfile has a custom build phase** (`setup_litertlm_macos.sh`) that copies Gemma companion dylibs into the app bundle. This runs automatically during Xcode builds via CocoaPods `post_install`. Do not remove the script phase or the app will crash at runtime.
- **Text insertion**: AX pins the target; normal insertion uses `⌘V` paste so web editors receive input events. Chromium 155–156 uses Unicode typing to avoid its clipboard race (newlines use Shift-Return). The clipboard is saved/restored automatically. Some apps (e.g., Electron-based) may not support AX insertion.
- **Nemotron streaming**: Uses `sherpa-onnx` with endpoint detection. First inference has ONNX cold-start latency (~seconds). A warm-up decode of 0.5s silence runs on model load.

## Architecture

```
lib/
├── main.dart                    # Entry point, service wiring, background STT preload
├── app/
│   ├── app.dart                 # MaterialApp, view routing (Settings vs SmartCommandHUD)
│   └── dictation_orchestrator.dart  # State machine: idle→recording→transcribing→grammar→insert
├── transcription/
│   ├── transcription_service.dart    # Facade, delegates to active backend
│   ├── stt_backend.dart              # Abstract contract
│   ├── gemma_transcription_backend.dart
│   ├── whisper_transcription_backend.dart
│   └── sherpa_nemotron_transcription_backend.dart
├── grammar/                     # Gemma 3 270M for grammar + smart commands
├── audio/                       # record package wrapper
├── vad/                         # Amplitude-based silence detection
├── hotkeys/                     # Native Ctrl-tap + hotkey_manager
├── accessibility/               # AX text insertion via MethodChannel
├── tray/                        # Menu bar icon + context menu
├── settings/                    # SharedPreferences + Settings UI
└── shared/                      # Enums, sound service, overlays
```

**Platform channels:**
- `com.aurascribe/accessibility` — AX text insertion, clipboard operations
- `com.aurascribe/hotkey` — Native double/triple Control tap listener

**Native Swift code:** `macos/Runner/AccessibilityPlugin.swift` contains both `AccessibilityPlugin` and `HotkeyPlugin` classes. Registers in `MainFlutterWindow.swift`.

## Testing

Tests cover settings navigation, the dictation indicator, storage boundaries/download recovery, vocabulary and token migration. The app requires live mic input, AX permissions, and model downloads—full integration testing is manual.

## Distribution

### Build & Create DMG
```bash
flutter build macos --release
bash create_dmg.sh
# Output: build/AuraScribe-v1.0.0.dmg (56 MB)
```

### Upload to GitHub Releases
1. Create a new release at `https://github.com/<your-repo>/releases/new`
2. Tag: `v1.0.0`
3. Upload `build/AuraScribe-v1.0.0.dmg` as release asset

### User Installation
1. Open DMG → Drag `AuraScribe.app` to Applications
2. Right-click app → Open (bypasses Gatekeeper on first launch)
3. Grant Accessibility permission when prompted (Settings → Privacy & Security → Accessibility)

## Extended options and native tools

- `lib/output`, `meetings`, `capture`, `updates`, `diagnostics`, `benchmarks` implement the extended settings pages. Shared controllers belong to the orchestrator so operations survive navigation.
- `CapturePlugin.swift`, `VoiceFilterPlugin.swift`, `UpdatePlugin.swift` register capture/OCR, audio filtering and verified updates. Their channels use `com.aurascribe/capture`, `com.aurascribe/voice_filter`, `com.aurascribe/updates`.
- The existing Gemma setup phase also calls `macos/scripts/setup_aurascribe_runtime.sh`; preserve both. Native helper and optional HAL installer output stays in `.aurascribe/tools/`.
- Build optional components with `bash tool/build_transcribe_runtime.sh` and `bash tool/build_virtual_microphone.sh`. Building never installs the driver.
- Model fixture checks are opt-in `dart run tool/verify_*.dart`; they download project-local weights. Standard tests mock native permission/device operations.
- See `docs/implementation-checklist.md` for implementation status and manual hardware/signing gates. Do not describe compiled native paths as live-tested.

## Memory policy

- Low-memory mode defaults on (General → Memory): Moonshine uses the bundled
  standalone Dart AOT `aurascribe-moonshine` worker per clip; the existing isolate
  path is used for keep-warm mode or development builds without that worker.
- `setup_aurascribe_runtime.sh` also builds/signs that worker from
  `tool/moonshine_worker.dart`. Preserve it along with both existing runtime phases.
- Shared `ModelMemoryPolicy` leases protect loads, recording, model operations,
  grammar and external jobs from idle/OS-pressure cleanup. Other resident models
  unload after 60 seconds by default; no forced production GC.
- The settings MaterialApp is mounted on demand. Native close is prevented until
  widget disposal has a frame, then the window hides. Drafts/modal editors survive;
  a lightweight closed text client breaks Flutter's last-editor retention.
- `tool/measure_memory.py` and `tool/benchmark_launch_memory.py` record project-local
  metadata. `tool/verify_memory_lifecycle.dart` requires already-installed weights
  and a supplied WAV; `tool/vm_heap_profile.dart` collects aggregate test allocations.
- See `docs/memory-results.md`; fresh launch footprint is not transcription peak,
  and app-only RSS excludes model worker processes.
