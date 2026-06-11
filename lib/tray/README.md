# Tray Service

macOS menu bar icon and context menu management.

## Files

- `tray_service.dart` — Tray icon state, menu building, click handling

## Features

- **Dynamic icon** — Switches between idle, recording, and transcribing icons
- **Status menu** — Shows current state (Idle, Recording, Transcribing, etc.)
- **Menu actions** — Start/Stop Recording, Settings, About, Quit

## Icons

| State | Asset |
|-------|-------|
| Idle / Error | `tray_icon.png` |
| Recording | `tray_icon_recording.png` |
| Transcribing / Grammar / Inserting | `tray_icon_transcribing.png` |

## Behavior

- Right-click tray icon opens context menu
- App has no Dock icon (`LSUIElement` enabled)
