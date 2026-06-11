# Hotkey Service

Global keyboard shortcut handling for dictation and smart commands.

## Files

- `hotkey_service.dart` — Hotkey registration and native event bridging

## Supported Triggers

| Trigger | Action |
|---------|--------|
| Double `⌃` (Control) | Toggle dictation |
| Triple `⌃` (Control) | Toggle dictation |
| `⌘⇧Space` | Toggle dictation |
| `⌃⇧C` | Trigger Smart Command (always active) |

## Implementation

- Double/triple Control taps use a native Swift `NSEvent` monitor via `MethodChannel('com.dictator/hotkey')`
- `⌘⇧Space` uses the `hotkey_manager` package
- `⌃⇧C` always registered via `hotkey_manager` with system scope

## Configuration

Hotkey type is persisted via `SettingsService` (0=double ctrl, 1=triple ctrl, 2=cmd+shift+space).

## STT Engine Interaction

When hotkey triggers:
1. If Gemma/Whisper: Records full audio, then transcribes batch
2. If Nemotron: Starts streaming session, text appears live as you speak
3. VAD detects silence or max recording reached → stops → processes transcript
