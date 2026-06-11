# Accessibility Service

Handles system-wide text insertion and clipboard operations via macOS Accessibility API.

## Files

- `accessibility_service.dart` — Dart bridge to native Swift `AccessibilityPlugin`

## Responsibilities

- Check/request Accessibility permission
- Insert text at the active cursor position (AX API)
- Clipboard paste fallback (`⌘V`) for non-AX-compliant apps
- Copy selected text (simulates `⌘C`)
- Replace selected text in the previously-focused app

## Platform Channel

Uses `MethodChannel('com.dictator/accessibility')` to communicate with native Swift code.
