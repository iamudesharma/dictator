import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart-side bridge to the native Swift AccessibilityPlugin.
/// Handles text insertion into the currently focused system-wide text field.
class AccessibilityService {
  static const _channel = MethodChannel('com.dictator/accessibility');

  /// Check if Accessibility permission has been granted.
  Future<bool> hasPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkPermission');
      final granted = result ?? false;
      debugPrint('[Dictator][Accessibility] checkPermission → $granted');
      return granted;
    } catch (e, st) {
      debugPrint('[Dictator][Accessibility] checkPermission failed: $e\n$st');
      return false;
    }
  }

  /// Open System Settings → Privacy & Security → Accessibility.
  Future<void> requestPermission() async {
    debugPrint('[Dictator][Accessibility] requestPermission → opening System Settings');
    try {
      await _channel.invokeMethod('requestPermission');
    } catch (e, st) {
      debugPrint('[Dictator][Accessibility] requestPermission failed: $e\n$st');
    }
  }

  /// Replaces the user's prior text selection in the app that was active when
  /// [copySelectedText] ran. Activates that app before pasting.
  Future<bool> replaceSelectedText(String text) async {
    debugPrint(
      '[Dictator][Accessibility] replaceSelectedText (${text.length} chars) → native',
    );
    try {
      final result =
          await _channel.invokeMethod<bool>('replaceSelectedText', {'text': text});
      final usedAx = result ?? false;
      debugPrint(
        '[Dictator][Accessibility] replaceSelectedText native result: usedAx=$usedAx',
      );
      return usedAx;
    } catch (e, st) {
      debugPrint('[Dictator][Accessibility] replaceSelectedText channel error: $e\n$st');
      return false;
    }
  }

  /// Insert [text] into the currently focused text field.
  /// Returns true if AX insertion succeeded, false if clipboard fallback was used.
  Future<bool> insertText(String text) async {
    debugPrint(
      '[Dictator][Accessibility] insertText (${text.length} chars) → native',
    );
    try {
      final result = await _channel.invokeMethod<bool>('insertText', {'text': text});
      final usedAx = result ?? false;
      debugPrint('[Dictator][Accessibility] insertText native result: usedAx=$usedAx');
      return usedAx;
    } catch (e, st) {
      debugPrint('[Dictator][Accessibility] insertText channel error: $e\n$st');
      return false;
    }
  }

  /// Grabs the currently selected text by simulating Cmd+C natively.
  /// Returns the selected text, or null if copy fails or no text is selected.
  Future<String?> copySelectedText() async {
    debugPrint('[Dictator][Accessibility] copySelectedText → native');
    try {
      final result = await _channel.invokeMethod<String>('copySelectedText');
      debugPrint('[Dictator][Accessibility] copySelectedText native result: ${result?.length ?? 0} chars');
      return result;
    } catch (e, st) {
      debugPrint('[Dictator][Accessibility] copySelectedText channel error: $e\n$st');
      return null;
    }
  }
}
