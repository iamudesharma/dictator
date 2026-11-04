# AuraScribe — Offline macOS Voice Dictation App

AuraScribe is a high-performance, fully offline macOS menu bar application built with Flutter. It implements a global system-wide dictation shortcut (e.g., double-tapping `Control`) that captures your voice, transcribes it on-device using one of five speech-to-text backend families, refines the grammar and punctuation locally, and inserts the final text directly into your currently focused input field.

---

## Key Features
* 🎤 **Pure Menu Bar App**: Runs entirely in the menu bar with no Dock icon (`LSUIElement` enabled).
* ⌨️ **Global Modifier Hotkey**: Custom native Swift event monitors track double or triple taps of the `Control` key (Left or Right) system-wide, even when the app is out of focus.
* 🧠 **Five On-Device STT Backend Families**: Choose from Gemma 4 E2B (GPU), Whisper (CPU), Nemotron-3.5 (streaming), Moonshine Tiny INT8 (CPU), or the native GGUF speech catalog—all run 100% locally with no cloud APIs, no telemetry, no internet needed after model download.
* 🎙️ **Streaming Transcription**: Nemotron-3.5 provides true streaming with live text appearing as you speak—ultra-low latency for real-time dictation.
* 🛠️ **System-Wide Text Insertion**: Uses the macOS Accessibility API (AX) to insert text at the active cursor position, falling back to an automatic clipboard paste (`⌘V`) for non-AX-compliant applications.
* 🔊 **Audio Status Feedback**: Plays native system chimes (Start, Stop, Success, and Error) when dictating.
* 🇮🇳 **Indian English Optimized**: Prompts are custom-tuned to handle Indian English retroflex consonants, rhythmic stress, and spelling/phrasing patterns accurately.

---

## Speech-to-Text Engines

| Engine | Disk / model information | Recognition | Hardware guidance |
|--------|--------------------------|-------------|-------------------|
| **Gemma 4 E2B** | Large multimodal model | Batch, English prompt | 16 GB system RAM recommended |
| **Whisper** tiny.en/tiny/base/small | About 75 / 75 / 142 / 466 MB | Clip-based; multilingual variants available | CPU; start with tiny on 8 GB Macs |
| **Nemotron-3.5** | 0.6B parameters, ONNX INT8 | True streaming, English | CPU; runtime RAM not measured here |
| **GGUF catalog** | 16 pinned artifacts; includes 50 MB Moonshine Streaming Tiny Q8 | CPU clip inference; architecture-specific languages | User-WAV benchmarks available |
| **Moonshine Tiny INT8** | About 120 MB of model weights | Clip-based, English | CPU; public sample verified on this Mac |

Disk sizes are not runtime RAM requirements. See the [research and validation notes](docs/hex-redesign.md).

### Gemma 4 E2B
Google's multimodal model handles audio-to-text directly. GPU-accelerated via Metal on Apple Silicon. Requires 16 GB RAM recommended. Downloads automatically from Hugging Face on first use.

### Whisper
OpenAI's speech recognition via `whisper_ggml`. Four choices available:
- **tiny.en** (~75 MB) — English-only
- **tiny** (~75 MB) — Multilingual
- **base** (~142 MB) — Balanced speed/accuracy
- **small** — Most accurate, slower

### Nemotron-3.5 0.6B
NVIDIA's streaming ASR model via `sherpa-onnx`. True streaming architecture processes audio in real-time—text appears as you speak. ONNX INT8 quantized for efficiency. Best for live typing mode.

---

## Project Structure & Assets
```
voice_to_text/
├── assets/
│   ├── tray_icon.png                  # Menu bar icon (Idle)
│   ├── tray_icon_recording.png        # Menu bar icon (Recording state)
│   └── tray_icon_transcribing.png     # Menu bar icon (Transcribing state)
├── lib/
│   ├── main.dart                      # App entry point
│   ├── app/                           # Orchestrator and UI shell
│   ├── audio/                         # Microphone recording
│   ├── transcription/                 # STT backends (Gemma, Whisper, Nemotron, Moonshine)
│   ├── grammar/                       # LLM grammar cleanup + Smart Commands
│   ├── accessibility/                 # macOS AX text insertion
│   ├── hotkeys/                       # Global keyboard shortcuts
│   ├── vad/                           # Voice Activity Detection
│   ├── tray/                          # Menu bar icon management
│   ├── settings/                      # Preferences UI
│   └── shared/                        # Common types and utilities
```

> [!NOTE]
> **Models are downloaded on demand** — No model files are bundled in the repo. Each engine downloads its model from Hugging Face on first use and caches it locally in `<project>/.aurascribe/models/`.

---

## First-Time Setup Instructions

### Prerequisites
* macOS 13.0 Ventura or later for the app target. The bundled sherpa ONNX Runtime advertises macOS 15.5; Moonshine/Nemotron compatibility with older macOS needs validation.
* Flutter SDK (stable channel).
* Xcode 14+ and CocoaPods.

### 1. Clone & Fetch Dependencies
Clone the repository and run:
```bash
flutter pub get
```

### 2. Install Pods
Navigate to the `macos` directory and run:
```bash
cd macos
pod install
cd ..
```

### 3. Run the App
```bash
flutter run -d macos
```

On first launch, the selected STT engine will download its model automatically from Hugging Face. Choose your engine in **Settings → Speech Engine**.

### Optional: Hugging Face Token
For gated models (Gemma), you may need a Hugging Face token:
1. Create an account at [huggingface.co](https://huggingface.co)
2. Generate a read-only token at [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens)
3. Accept the Gemma license on the model page
4. Enter the token in **Settings → Hugging Face**

---

## Building and Running the App

### Debug Mode (Development)
To compile and run the application locally:
```bash
flutter run -d macos
```

### Release Mode (Standalone Application)
To compile the final standalone release build:
```bash
flutter build macos --release
```
The output `.app` bundle will be built at:
`build/macos/Build/Products/Release/voice_to_text.app`

---

## Operating System Configuration

### 1. Grant Accessibility Permissions
Because the application simulates keypresses and uses system-wide APIs to paste/insert text, you must authorize it:
1. Open **System Settings** → **Privacy & Security** → **Accessibility**.
2. Click the `+` button and add the compiled `voice_to_text` application.
3. Toggle the permission switch **ON**.

*(You can also trigger this setup screen by opening the app, right-clicking the tray icon, selecting **Settings**, and clicking **Grant Accessibility Permission**).*

### 2. Bypass Gatekeeper Warnings (For Distribution)
If you transfer the compiled `.app` to another Mac system, macOS will prevent it from running with a security warning since it is built locally.
1. Compress it to a `.zip` before copying (`zip -r -9 voice_to_text.zip voice_to_text.app`).
2. Move it to the `/Applications` folder on the target Mac and extract it.
3. Open Terminal and remove the quarantine flag:
   ```bash
   xattr -d com.apple.quarantine /Applications/voice_to_text.app
   ```
4. **Right-click** (or Control-click) the app in Finder, choose **Open**, and confirm the launch.


## Hex-inspired interface and project-local models

Twelve settings pages now cover custom/raw shortcuts, duck/mute and clipboard policies,
per-app output pipelines, personal commands, speech catalog/custom imports, benchmarks,
meeting capture/diarization/notes, voice filtering and a virtual mic installer, annotation/OCR,
verified release updates, and diagnostics. A tiny 104×30 point animated native panel appears at the top of the active screen (bottom is optional). It is click-through and cannot activate the app or take keyboard focus. Dictation saves the original app/text field and surfaces insertion errors.

All model files and inference caches stay in this checkout’s ignored `.aurascribe/`.
Nothing downloads at startup unless preload is enabled. The checkout must remain accessible;
there is no global storage fallback. Old external downloads are untouched.

The GGUF helper and virtual microphone installer are built and bundled by the existing native
setup phase. The helper source is pinned in `tool/build_transcribe_runtime.sh`. Installing the
optional audio driver requires an explicit administrator action. Signed update installation
requires a newer Developer ID signed release. Live permissions/audio and older macOS support
still require acceptance; see the [sequential implementation checklist](docs/implementation-checklist.md)
and [storage, runtime and validation guide](docs/hex-redesign.md).
