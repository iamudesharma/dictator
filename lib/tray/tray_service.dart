import '../l10n/app_localizations.dart';
import '../history/history_service.dart';

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
  bool paused = false;
  bool _hidden = false;
  String? _lastIcon;
  Future<void> _updates = Future.value();
  String model = '';
  Future<void> refresh() => updateState(_state);
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
    _ =>
      settings?.shortcuts[ShortcutAction.dictation]?.label ?? 'Custom shortcut',
  };

  TrayMenuCallback? onMenuItemClick;

  Future<void> init() async {
    trayManager.addListener(this);
    await updateState(DictationState.idle);
  }

  Future<void> updateState(DictationState state) {
    _state = state;
    // Serialize native updates so a quick busy/idle transition cannot leave
    // an earlier icon upload completing after the later state.
    final next = _updates.then((_) => _render(state));
    _updates = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> _render(DictationState state) async {
    if (settings?.option('hideMenuBarIcon') == true) {
      if (!_hidden) await trayManager.destroy();
      _hidden = true;
      _lastIcon = null;
      return;
    }
    _hidden = false;
    final icon = switch (state) {
      DictationState.recording => 'assets/tray_icon_recording.png',
      DictationState.transcribing ||
      DictationState.grammarCleanup ||
      DictationState.inserting => 'assets/tray_icon_transcribing.png',
      _ =>
        state == DictationState.idle && (_external != null || _voice != null)
            ? 'assets/tray_icon_recording.png'
            : 'assets/tray_icon.png',
    };
    if (icon != _lastIcon) {
      await trayManager.setIcon(icon, isTemplate: true);
      _lastIcon = icon;
    }
    await trayManager.setToolTip(
      'AuraScribe · ${state == DictationState.idle ? tr(_external ?? _voice ?? 'Ready') : state.label}',
    );
    await _buildMenu(state);
  }

  Future<void> _buildMenu(DictationState state) async {
    final String statusLabel;
    switch (state) {
      case DictationState.idle:
        statusLabel = _external ?? _voice ?? tr('Idle');
        break;
      case DictationState.recording:
        statusLabel = '🔴 ${tr('Recording…')}';
        break;
      case DictationState.transcribing:
        statusLabel = '🎙️ ${tr('Transcribing…')}';
        break;
      case DictationState.grammarCleanup:
        statusLabel = '✨ ${tr('Cleaning up…')}';
        break;
      case DictationState.inserting:
        statusLabel = '📥 ${tr('Inserting…')}';
        break;
      case DictationState.error:
        statusLabel = '❌ ${tr('Error')}';
        break;
    }

    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(
            key: 'model',
            label: model.isEmpty
                ? tr("Speech models…")
                : tr("Speech model: {v0}", values: {"v0": model}),
          ),
          MenuItem(
            key: 'pause',
            label: paused
                ? tr("Resume dictation shortcuts")
                : tr("Pause dictation shortcuts"),
          ),
          MenuItem(key: 'paste_last', label: tr("Paste last dictation")),
          if (settings?.isSettingsPageVisible(7) == true ||
              _external == 'Meeting recording')
            MenuItem(
              key: 'meeting',
              label: _external == 'Meeting recording'
                  ? tr("Stop meeting")
                  : tr("Record meeting"),
            ),
          if (settings?.isSettingsPageVisible(9) == true)
            MenuItem(key: 'capture', label: tr("Capture")),
          if (settings?.historyEnabled == true &&
              settings?.isSettingsPageVisible(4) == true)
            for (
              var i = 0;
              i < HistoryService.instance.entries.length && i < 5;
              i++
            )
              MenuItem(
                key: 'recent:$i',
                label: HistoryService.instance.entries[i].text
                    .replaceAll('\n', ' ')
                    .substring(
                      0,
                      HistoryService.instance.entries[i].text.length.clamp(
                        0,
                        60,
                      ),
                    ),
              ),
          MenuItem.separator(),
          MenuItem(key: 'status', label: tr(statusLabel), disabled: true),
          MenuItem.separator(),
          MenuItem(
            key: 'toggle_recording',
            label: state == DictationState.recording
                ? tr("Stop Recording")
                : tr("Start Recording  ({v0})", values: {"v0": shortcutLabel}),
          ),
          MenuItem.separator(),
          if (_external != null || _voice != null)
            MenuItem(
              key: 'stop_background_audio',
              label: tr("Stop background audio"),
            ),
          MenuItem(key: 'settings', label: tr("Settings…")),
          MenuItem(key: 'about', label: tr("About AuraScribe")),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: tr("Quit AuraScribe")),
        ],
      ),
    );
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
