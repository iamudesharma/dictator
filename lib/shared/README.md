# Shared Module

Common types, enums, and utility services used across the app.

## Files

- `dictation_state.dart` — `DictationState` enum (idle, recording, transcribing, etc.)
- `dictation_mode.dart` — `DictationMode` enum (liveTyping, enhancedAccuracy)
- `stt_engine.dart` — `SttEngine` enum (gemma, whisper, nemotron)
- `sound_service.dart` — System chime playback (start, stop, success, error)
- `notification_overlay.dart` — In-app notification banner widget
- `smart_command_hud.dart` — Smart Command floating HUD window
- `wav_header_helper.dart` — Builds WAV file headers for raw PCM buffers

## STT Engine Enum

| Value | Engine | Use Case |
|-------|--------|----------|
| `gemma` | Gemma 4 E2B | Best accuracy, GPU-accelerated |
| `whisper` | Whisper | Lower RAM, 8 GB Macs |
| `nemotron` | Nemotron-3.5 0.6B | Streaming, ultra-low latency |

## Dictation Mode Enum

| Value | Mode | Description |
|-------|------|-------------|
| `liveTyping` | Live Typing | Text appears as you speak (best with Nemotron) |
| `enhancedAccuracy` | Enhanced Accuracy | Full recording → grammar cleanup → insert |
