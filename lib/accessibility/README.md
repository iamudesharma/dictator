# Accessibility Service

Handles system-wide text insertion and clipboard operations via macOS Accessibility API.

## Files

- `accessibility_service.dart` — Dart bridge to native Swift `AccessibilityPlugin`

## Responsibilities

- Check/request Accessibility permission
- Pin the original application/editable field using AX, then insert at its cursor
- Native clipboard paste (`⌘V`) so web editors receive input events; Unicode
  typing for Chromium 155–156 avoids their clipboard race
- Copy selected text (simulates `⌘C`)
- Replace selected text in the previously-focused app

## Platform Channel

Uses `MethodChannel('com.aurascribe/accessibility')` to communicate with native Swift code.
