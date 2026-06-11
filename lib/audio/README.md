# Audio Service

Manages microphone recording via the `record` package.

## Files

- `audio_service.dart` — Recording start/stop/stream interface

## Features

- **File recording** — WAV output at 16 kHz mono (for Whisper/Gemma batch)
- **Stream recording** — Raw PCM 16-bit chunks (for Nemotron streaming)
- **Amplitude polling** — dBFS readings for VAD

## Recording Config

| Parameter | Value |
|-----------|-------|
| Sample rate | 16,000 Hz |
| Channels | 1 (mono) |
| Encoder | WAV (file) / PCM 16-bit (stream) |
| Bit rate | 256 kbps (file mode) |

## Output

Files are saved to the system temp directory as `dictation_<timestamp>.wav`.
