# AGENTS.md — AuraScribe (voice_to_text)

## What This Is

macOS-only Flutter menu bar app for offline voice dictation. Runs in the system tray with no Dock icon (`LSUIElement`). Three STT backends: Gemma 4 E2B (GPU), Whisper (CPU), Nemotron-3.5 (streaming). Optional grammar cleanup via Gemma 3 270M LLM.

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

- **Models download on first use** from Hugging Face to `~/Library/Application Support/`. No model files in repo (`.gitignore` excludes `*.litertlm`).
- **Gemma STT requires 16 GB RAM** recommended. Whisper works on 8 GB.
- **Hugging Face token** may be needed for gated Gemma models. Set in app Settings → Hugging Face.
- **macOS 13.0+** required (set in `Podfile` and `pubspec.yaml`).
- **Podfile has a custom build phase** (`setup_litertlm_macos.sh`) that copies Gemma companion dylibs into the app bundle. This runs automatically during Xcode builds via CocoaPods `post_install`. Do not remove the script phase or the app will crash at runtime.
- **Clipboard fallback**: AX text insertion falls back to `⌘V` paste. The clipboard is saved/restored automatically. Some apps (e.g., Electron-based) may not support AX insertion.
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

The test suite is minimal (smoke test only). The app requires live mic input, AX permissions, and model downloads—full integration testing is manual.

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
