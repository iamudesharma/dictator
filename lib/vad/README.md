# Voice Activity Detection

Amplitude-based silence detection for auto-stopping recordings.

## Files

- `vad_service.dart` — Polling VAD with configurable thresholds

## How It Works

1. Polls audio amplitude every 150ms
2. Tracks whether speech has been detected (`_hasSpeech`)
3. After speech detected, counts consecutive silent milliseconds
4. Fires `onSilenceDetected` when silence exceeds configured duration
5. Enforces max recording length as a hard cap

## Configuration

| Parameter | Default | Range |
|-----------|---------|-------|
| Silence threshold | -35 dBFS | -60 to -10 |
| Silence duration | 1500 ms | 500–3000 |
| Max recording | 45 s | 15–90 |
| Poll interval | 150 ms | Fixed |

## Threshold Guide

- **-40 to -30 dBFS** — Quiet room, sensitive
- **-35 dBFS** — Default, balanced
- **-25 to -20 dBFS** — Noisy environment
