# Settings Module

User preferences persistence and settings UI.

## Files

- `settings_service.dart` — `SharedPreferences` wrapper for all settings
- `settings_screen.dart` — Full settings UI (Material 3 dark theme)

## Persisted Settings

| Key | Default | Description |
|-----|---------|-------------|
| `hotkey_type` | 0 | 0=double ctrl, 1=triple ctrl, 2=cmd+shift+space |
| `stt_engine` | 0 | 0=Whisper, 1=Gemma 4 E2B, 2=Nemotron-3.5 |
| `whisper_model` | 0 | 0=tiny.en, 1=base, 2=small |
| `dictation_mode` | 0 | 0=liveTyping, 1=enhancedAccuracy |
| `vad_threshold_dbfs` | -35.0 | Silence detection threshold |
| `vad_silence_duration_ms` | 1500 | How long silence triggers stop |
| `max_recording_seconds` | 45 | Hard cap on recording length |
| `grammar_enabled` | false | Enable LLM grammar cleanup |
| `fallback_notify` | true | Notify on clipboard fallback |
| `hf_token` | '' | Hugging Face token for gated models |

## STT Engine Options

| Index | Engine | RAM | Streaming |
|-------|--------|-----|-----------|
| 0 | Whisper | 8 GB | No |
| 1 | Gemma 4 E2B | 16 GB+ | No |
| 2 | Nemotron-3.5 0.6B | 8 GB | Yes |

## Dictation Modes

| Mode | Description |
|------|-------------|
| Live Typing | Text streamed directly into field as you speak |
| Enhanced Accuracy | Full recording → grammar cleanup → insert |
