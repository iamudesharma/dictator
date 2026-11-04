import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import '../settings/settings_service.dart';
import 'shortcut_binding.dart';

class HotkeyService {
  static const _channel = MethodChannel('com.aurascribe/hotkey');
  final SettingsService _settings;
  void Function()? onConfigurationChanged;
  void Function()? onTriggered,
      onRawTriggered,
      onHoldStarted,
      onHoldEnded,
      onPasteLast,
      onSmartCommandTriggered,
      onCapture;
  HotkeyService(this._settings);

  Future<void> init() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onHotkeyTriggered') onTriggered?.call();
      if (call.method == 'onModifierPressed') {
        if (_settings.holdShortcut) {
          onHoldStarted?.call();
        } else {
          onTriggered?.call();
        }
      }
      if (call.method == 'onModifierReleased' && _settings.holdShortcut) {
        onHoldEnded?.call();
      }
    });
    await updateHotkey();
  }

  static void validateBindings(Map<ShortcutAction, ShortcutBinding> values,
      {required bool chordDictation}) {
    final used = <String, ShortcutAction>{};
    for (final entry in values.entries) {
      if (entry.key == ShortcutAction.dictation && !chordDictation) continue;
      entry.value
          .validate(allowModifierOnly: entry.key == ShortcutAction.dictation);
      final collision = used[entry.value.signature];
      if (collision != null) {
        throw ArgumentError('Already used by ${collision.label}.');
      }
      used[entry.value.signature] = entry.key;
    }
  }

  Future<void> _register(
      Map<ShortcutAction, ShortcutBinding> bindings, int type) async {
    if (type == 2 || type == 4 || type == 5) {
      bindings = {
        ...bindings,
        ShortcutAction.dictation: type == 2
            ? ShortcutBinding.legacyDictation
            : type == 4
                ? ShortcutBinding.optionChord
                : ShortcutBinding.defaults[ShortcutAction.dictation]!
      };
    }
    validateBindings(bindings, chordDictation: type >= 2);
    await hotKeyManager.unregisterAll();
    await _channel.invokeMethod<void>('stopListening');
    for (final action in ShortcutAction.values) {
      if (action == ShortcutAction.dictation && type < 2) continue;
      final binding = bindings[action]!;
      if (binding.isModifierOnly) {
        await _channel.invokeMethod<void>('startModifierListening', {
          'keyCode': binding.modifierKeyCode,
          'anyOption': type == 5,
          'hold': _settings.holdShortcut,
        });
        continue;
      }
      await hotKeyManager.register(binding.toHotKey(action),
          keyDownHandler: (_) {
        switch (action) {
          case ShortcutAction.dictation:
            if (_settings.holdShortcut) {
              onHoldStarted?.call();
            } else {
              onTriggered?.call();
            }
          case ShortcutAction.rawDictation:
            onRawTriggered?.call();
          case ShortcutAction.pasteLast:
            onPasteLast?.call();
          case ShortcutAction.smartCommands:
            onSmartCommandTriggered?.call();
          case ShortcutAction.capture:
            onCapture?.call();
        }
      }, keyUpHandler: (_) {
        if (action == ShortcutAction.dictation && _settings.holdShortcut) {
          onHoldEnded?.call();
        }
      });
    }
    if (type < 2) {
      await _channel.invokeMethod<void>(
          'startListening', {'targetCount': type == 0 ? 2 : 3});
    }
  }

  Future<void> saveBinding(ShortcutAction action, ShortcutBinding value) async {
    final previous = _settings.shortcuts;
    final oldType = _settings.hotkeyType;
    final oldHold = _settings.holdShortcut;
    final next = {...previous, action: value};
    final type = action == ShortcutAction.dictation ? 3 : oldType;
    validateBindings(next, chordDictation: type >= 2);
    try {
      if (action == ShortcutAction.dictation && value.isModifierOnly) {
        await _settings.setHoldShortcut(true);
      }
      await _register(next, type);
      await _settings.setShortcuts(next);
      await _settings.setHotkeyType(type);
      onConfigurationChanged?.call();
    } catch (_) {
      await _settings.setHoldShortcut(oldHold);
      await _settings.setShortcuts(previous);
      await _settings.setHotkeyType(oldType);
      await _register(previous, oldType);
      rethrow;
    }
  }

  Future<void> saveType(int type) async {
    final old = _settings.hotkeyType;
    final oldHold = _settings.holdShortcut;
    try {
      if (type == 5) await _settings.setHoldShortcut(true);
      await _register(_settings.shortcuts, type);
      await _settings.setHotkeyType(type);
      onConfigurationChanged?.call();
    } catch (_) {
      await _settings.setHoldShortcut(oldHold);
      await _register(_settings.shortcuts, old);
      rethrow;
    }
  }

  Future<void> suspendForRecorder() async {
    await hotKeyManager.unregisterAll();
    await _channel.invokeMethod<void>('stopListening');
  }

  Future<void> updateHotkey() =>
      _register(_settings.shortcuts, _settings.hotkeyType);
  void dispose() {
    _channel.setMethodCallHandler(null);
    _channel.invokeMethod<void>('stopListening');
    hotKeyManager.unregisterAll();
  }
}
