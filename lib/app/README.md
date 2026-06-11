# App Module

Core application entry point and dictation state machine.

## Files

- `app.dart` — `DictatorApp` MaterialApp widget and `DictatorHome` scaffold
- `dictation_orchestrator.dart` — Central `ChangeNotifier` coordinating the full dictation pipeline

## Dictation Pipeline

```
Hotkey/Tray → toggle() → startRecording()
  → Audio capture → VAD silence detection
  → Transcription (Gemma / Whisper / Nemotron)
  → Grammar cleanup (optional)
  → Text insertion (AX or clipboard fallback)
```

## DictationOrchestrator States

| State | Description |
|-------|-------------|
| `idle` | Ready for input |
| `recording` | Audio capture active, VAD polling |
| `transcribing` | STT model processing audio |
| `grammarCleanup` | LLM grammar pass running |
| `inserting` | Text being inserted into target app |
| `error` | Error occurred (auto-resets after 3s in HUD mode) |

## Dictation Modes

- **Live Typing** — Text streamed directly into the focused field as you speak (requires Nemotron for true streaming)
- **Enhanced Accuracy** — Full recording → grammar cleanup → insert

## Smart Commands

Triggered via `Ctrl+Shift+C`. Grabs selected text, shows HUD overlay, processes with Gemma, and replaces the selection.
