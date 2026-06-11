import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import '../settings/settings_service.dart';

typedef HotkeyTriggeredCallback = void Function();

class HotkeyService {
  static const _channel = MethodChannel('com.dictator/hotkey');
  
  final SettingsService _settings;
  HotkeyTriggeredCallback? onTriggered;
  HotkeyTriggeredCallback? onSmartCommandTriggered;

  HotKey? _registeredHotKey;
  HotKey? _smartCommandHotKey;

  HotkeyService(this._settings);

  Future<void> init() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onHotkeyTriggered') {
        debugPrint('[Dictator][Hotkey] native hotkey triggered');
        onTriggered?.call();
      }
      return null;
    });
    
    await hotKeyManager.unregisterAll();
    await _register();
  }

  Future<void> _register() async {
    final type = _settings.hotkeyType;

    // Always register Control + Shift + C for Smart Commands
    if (_smartCommandHotKey != null) {
      await hotKeyManager.unregister(_smartCommandHotKey!);
      _smartCommandHotKey = null;
    }
    _smartCommandHotKey = HotKey(
      key: PhysicalKeyboardKey.keyC,
      modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
      scope: HotKeyScope.system,
    );
    debugPrint('[Dictator][Hotkey] registering global Control+Shift+C for Smart Commands');
    await hotKeyManager.register(
      _smartCommandHotKey!,
      keyDownHandler: (_) {
        debugPrint('[Dictator][Hotkey] Control+Shift+C triggered');
        onSmartCommandTriggered?.call();
      },
    );

    if (type == 0 || type == 1) {
      // Clean up hotkey manager registration
      if (_registeredHotKey != null) {
        await hotKeyManager.unregister(_registeredHotKey!);
        _registeredHotKey = null;
      }
      
      // Start native macOS double/triple Ctrl listener
      try {
        final count = type == 0 ? 2 : 3;
        debugPrint('[Dictator][Hotkey] native Ctrl×$count listener starting');
        await _channel.invokeMethod('startListening', {
          'targetCount': count,
        });
      } catch (e) {
        debugPrint('[Dictator][Hotkey] ❌ Failed to start native listening: $e');
      }
    } else {
      // Stop native listener
      try {
        await _channel.invokeMethod('stopListening');
      } catch (_) {}
      
      // Register via hotkey_manager (Cmd+Shift+Space)
      _registeredHotKey = HotKey(
        key: PhysicalKeyboardKey.space,
        modifiers: [HotKeyModifier.meta, HotKeyModifier.shift],
        scope: HotKeyScope.system,
      );
      
      debugPrint('[Dictator][Hotkey] registered Cmd+Shift+Space');
      await hotKeyManager.register(
        _registeredHotKey!,
        keyDownHandler: (_) {
          debugPrint('[Dictator][Hotkey] Cmd+Shift+Space triggered');
          onTriggered?.call();
        },
      );
    }
  }

  Future<void> updateHotkey() async {
    await hotKeyManager.unregisterAll();
    await _register();
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _channel.invokeMethod('stopListening').catchError((_) {});
    hotKeyManager.unregisterAll();
  }
}
