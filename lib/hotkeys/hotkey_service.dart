import 'dart:async';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:uni_platform/uni_platform.dart';
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
      onCapture,
      onCancel,
      onTerminal,
      onTypedText,
      onReplay;
  String? configurationError;
  Future<void> updateRecording(bool active) =>
      _channel.invokeMethod<void>('setRecordingCapsLock', active);
  bool _paused = false;
  final Map<ShortcutAction, DateTime> _pressed = {};
  DateTime? _lastModifierTap;
  Future<void> setPaused(bool value) async {
    if (_paused == value) return;
    _paused = value;
    if (value) {
      await suspendForRecorder();
    } else {
      await updateHotkey();
    }
  }

  HotkeyService(this._settings);
  bool _cancelEnabled = false;
  Future<void> _cancelPending = Future.value();
  Future<void> setCancelEnabled(bool enabled) {
    if (_cancelEnabled == enabled) return _cancelPending;
    _cancelEnabled = enabled;
    _cancelPending = _cancelPending.catchError((_) {}).then((_) async {
      final key = _settings.shortcuts[ShortcutAction.cancel]!
          .toHotKey(ShortcutAction.cancel);
      if (_cancelEnabled) {
        await hotKeyManager.register(key,
            keyDownHandler: (_) => onCancel?.call());
      } else {
        await hotKeyManager.unregister(key);
      }
    });
    return _cancelPending;
  }

  Future<void> init() async {
    _channel.setMethodCallHandler((call) async {
      if (_paused) return;
      if (call.method == 'onNativeShortcut') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final action = ShortcutAction.values.byName(args['action'] as String);
        if (args['down'] == true) {
          _keyDown(action);
        } else {
          _keyUp(action);
        }
      }
      if (call.method == 'onAuxiliaryToggle') onTriggered?.call();
      if (call.method == 'onHotkeyTriggered') onTriggered?.call();
      if (call.method == 'onModifierPressed') {
        _keyDown(ShortcutAction.dictation);
      }
      if (call.method == 'onModifierReleased') _keyUp(ShortcutAction.dictation);
    });
    try {
      await updateHotkey();
    } catch (e) {
      configurationError = e.toString();
    }
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
    if (_paused) return;
    configurationError = null;
    await _channel.invokeMethod<void>('configureAuxiliary', {
      'capsLock': _settings.option('capsLock'),
      'mouseButton':
          int.tryParse(_settings.optionText('mouseButton', '-1')) ?? -1
    });
    _pressed.clear();
    _cancelEnabled = false;
    await _channel.invokeMethod<void>('configureNativeShortcuts', []);
    await hotKeyManager.unregisterAll();
    await _channel.invokeMethod<void>('stopListening');
    final nativeBindings = <Map<String, dynamic>>[];
    for (final action in ShortcutAction.values) {
      if (action == ShortcutAction.cancel) continue;
      if (action == ShortcutAction.dictation && type < 2) continue;
      if (action.isOptional && !_settings.extraShortcutEnabled(action)) {
        continue;
      }
      final binding = bindings[action]!;
      if (binding.sides.isNotEmpty ||
          (binding.isModifierOnly && binding.modifiers.isNotEmpty) ||
          _settings.option('shareShortcut') ||
          binding.usage == 0x70064) {
        nativeBindings.add({
          'action': action.name,
          'keyCode': binding.key.keyCode ??
              (throw ArgumentError('This key has no macOS shortcut mapping.')),
          'modifierOnly': binding.isModifierOnly,
          'anyOption': action == ShortcutAction.dictation && type == 5,
          'modifiers': binding.modifiers.map((m) => m.name).toList(),
          'sides': binding.sides
              .map((u) => ShortcutBinding.modifierKeyCodes[u])
              .toList(),
          'share': _settings.option('shareShortcut')
        });
        continue;
      }
      if (binding.isModifierOnly) {
        await _channel.invokeMethod<void>('startModifierListening', {
          'keyCode': binding.modifierKeyCode,
          'anyOption': type == 5,
          'hold':
              _settings.holdShortcut && !_settings.option('doubleTapModifier'),
        });
        continue;
      }
      await hotKeyManager.register(binding.toHotKey(action),
          keyDownHandler: (_) => _keyDown(action),
          keyUpHandler: (_) => _keyUp(action));
    }
    await _channel.invokeMethod<void>(
        'configureNativeShortcuts', nativeBindings);
    if (type < 2) {
      await _channel.invokeMethod<void>(
          'startListening', {'targetCount': type == 0 ? 2 : 3});
    }
  }

  void _keyDown(ShortcutAction action) {
    if (_paused || _pressed.containsKey(action)) return;
    _pressed[action] = DateTime.now();
    if (action == ShortcutAction.dictation &&
        _settings.option('doubleTapModifier') &&
        _settings.shortcuts[action]!.isModifierOnly) {
      final now = DateTime.now();
      if (_lastModifierTap != null &&
          now.difference(_lastModifierTap!).inMilliseconds <= 400) {
        _lastModifierTap = null;
        onTriggered?.call();
      } else {
        _lastModifierTap = now;
      }
      return;
    }
    if (action == ShortcutAction.dictation || action.isAdditionalDictation) {
      final hold = action == ShortcutAction.dictation
          ? _settings.holdShortcut
          : _settings.extraShortcutHold(action);
      if (hold) {
        onHoldStarted?.call();
      } else {
        onTriggered?.call();
      }
      return;
    }
    switch (action) {
      case ShortcutAction.rawDictation:
        onRawTriggered?.call();
      case ShortcutAction.pasteLast:
        onPasteLast?.call();
      case ShortcutAction.smartCommands:
        onSmartCommandTriggered?.call();
      case ShortcutAction.capture:
        onCapture?.call();
      case ShortcutAction.cancel:
        onCancel?.call();
      case ShortcutAction.terminalDictation:
        onTerminal?.call();
      case ShortcutAction.typedText:
        onTypedText?.call();
      case ShortcutAction.replay:
        onReplay?.call();
      default:
        break;
    }
  }

  void _keyUp(ShortcutAction action) {
    final start = _pressed.remove(action);
    if (start == null || _paused) return;
    if (action == ShortcutAction.dictation &&
        _settings.option('doubleTapModifier') &&
        _settings.shortcuts[action]!.isModifierOnly) {
      return;
    }
    if (action == ShortcutAction.dictation || action.isAdditionalDictation) {
      final hold = action == ShortcutAction.dictation
          ? _settings.holdShortcut
          : _settings.extraShortcutHold(action);
      if (hold) {
        onHoldEnded?.call();
      } else if (_settings.option('tapOrHold') &&
          DateTime.now().difference(start).inMilliseconds >= 350) {
        onHoldEnded?.call();
      }
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
    _pressed.clear();
    await _channel.invokeMethod<void>('configureNativeShortcuts', []);
    await _channel.invokeMethod<void>(
        'configureAuxiliary', {'capsLock': false, 'mouseButton': -1});
    _cancelEnabled = false;
    await hotKeyManager.unregisterAll();
    await _channel.invokeMethod<void>('stopListening');
  }

  Future<void> updateHotkey() =>
      _register(_settings.shortcuts, _settings.hotkeyType);
  void dispose() {
    _channel.invokeMethod<void>(
        'configureAuxiliary', {'capsLock': false, 'mouseButton': -1});
    _channel.invokeMethod<void>('configureNativeShortcuts', []);
    _channel.setMethodCallHandler(null);
    _channel.invokeMethod<void>('stopListening');
    hotKeyManager.unregisterAll();
  }
}
