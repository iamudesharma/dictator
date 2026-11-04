import 'package:tray_manager/tray_manager.dart';
import '../shared/dictation_state.dart';
import '../settings/settings_service.dart';
import '../hotkeys/shortcut_binding.dart';

typedef TrayMenuCallback = void Function(String key);

class TrayService with TrayListener {
  final SettingsService? settings;
  TrayService({this.settings});
  DictationState _state = DictationState.idle;
  String? _external, _voice;
  Future<void> updateActivity(String? value) async {
    _external = value;
    await updateState(_state);
  }

  Future<void> updateVoiceActivity(String? value) async {
    _voice = value;
    await updateState(_state);
  }

  String get shortcutLabel => switch (settings?.hotkeyType ?? 5) {
        0 => '⌃⌃',
        1 => '⌃⌃⌃',
        2 => '⌘ ⇧ Space',
        4 => '⌥ T',
        5 => 'Hold ⌥',
        _ => settings?.shortcuts[ShortcutAction.dictation]?.label ??
            'Custom shortcut'
      };

  TrayMenuCallback? onMenuItemClick;

  Future<void> init() async {
    trayManager.addListener(this);
    await trayManager.setIcon('assets/tray_icon.png', isTemplate: true);
    await trayManager.setToolTip('AuraScribe');
    await _buildMenu(DictationState.idle);
  }

  Future<void> updateState(DictationState state) async {
    _state = state;
    switch (state) {
      case DictationState.recording:
        await trayManager.setIcon('assets/tray_icon_recording.png',
            isTemplate: true);
        break;
      case DictationState.transcribing:
      case DictationState.grammarCleanup:
      case DictationState.inserting:
        await trayManager.setIcon('assets/tray_icon_transcribing.png',
            isTemplate: true);
        break;
      case DictationState.idle:
      case DictationState.error:
        await trayManager.setIcon('assets/tray_icon.png', isTemplate: true);
        break;
    }
    if (state == DictationState.idle && (_external != null || _voice != null)) {
      await trayManager.setIcon('assets/tray_icon_recording.png',
          isTemplate: true);
    }
    await trayManager.setToolTip(
        'AuraScribe · ${state == DictationState.idle ? (_external ?? _voice ?? "Ready") : state.label}');
    await _buildMenu(state);
  }

  Future<void> _buildMenu(DictationState state) async {
    final String statusLabel;
    switch (state) {
      case DictationState.idle:
        statusLabel = _external ?? _voice ?? 'Idle';
        break;
      case DictationState.recording:
        statusLabel = '🔴 Recording…';
        break;
      case DictationState.transcribing:
        statusLabel = '🎙️ Transcribing…';
        break;
      case DictationState.grammarCleanup:
        statusLabel = '✨ Cleaning up…';
        break;
      case DictationState.inserting:
        statusLabel = '📥 Inserting…';
        break;
      case DictationState.error:
        statusLabel = '❌ Error';
        break;
    }

    await trayManager.setContextMenu(Menu(items: [
      MenuItem(
        key: 'status',
        label: statusLabel,
        disabled: true,
      ),
      MenuItem.separator(),
      MenuItem(
        key: 'toggle_recording',
        label: state == DictationState.recording
            ? 'Stop Recording'
            : 'Start Recording  ($shortcutLabel)',
      ),
      MenuItem.separator(),
      if (_external != null || _voice != null)
        MenuItem(key: 'stop_background_audio', label: 'Stop background audio'),
      MenuItem(key: 'settings', label: 'Settings…'),
      MenuItem(key: 'about', label: 'About AuraScribe'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit AuraScribe'),
    ]));
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    onMenuItemClick?.call(menuItem.key ?? '');
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  void dispose() {
    trayManager.removeListener(this);
  }
}
