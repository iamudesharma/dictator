import 'package:tray_manager/tray_manager.dart';
import '../shared/dictation_state.dart';

typedef TrayMenuCallback = void Function(String key);

class TrayService with TrayListener {
  TrayMenuCallback? onMenuItemClick;

  Future<void> init() async {
    trayManager.addListener(this);
    await trayManager.setIcon('assets/tray_icon.png');
    await trayManager.setToolTip('Dictator');
    await _buildMenu(DictationState.idle);
  }

  Future<void> updateState(DictationState state) async {
    switch (state) {
      case DictationState.recording:
        await trayManager.setIcon('assets/tray_icon_recording.png');
        break;
      case DictationState.transcribing:
      case DictationState.grammarCleanup:
      case DictationState.inserting:
        await trayManager.setIcon('assets/tray_icon_transcribing.png');
        break;
      case DictationState.idle:
      case DictationState.error:
        await trayManager.setIcon('assets/tray_icon.png');
        break;
    }
    await _buildMenu(state);
  }

  Future<void> _buildMenu(DictationState state) async {
    final String statusLabel;
    switch (state) {
      case DictationState.idle:
        statusLabel = '🟢 Idle';
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
            : 'Start Recording  (⌃⌃)',
      ),
      MenuItem.separator(),
      MenuItem(key: 'settings', label: 'Settings…'),
      MenuItem(key: 'about', label: 'About Dictator'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit Dictator'),
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
