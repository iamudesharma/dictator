import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_to_text/settings/settings_service.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_to_text/shared/dictation_state.dart';
import 'package:voice_to_text/tray/tray_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'tray avoids redundant image uploads while keeping activity/menu updates',
    () async {
      final calls = <MethodCall>[];
      Completer<void>? pendingIcon;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel('tray_manager'), (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'setIcon' &&
            (call.arguments['iconPath'] as String).endsWith(
              'tray_icon_recording.png',
            )) {
          await pendingIcon?.future;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('tray_manager'),
          null,
        ),
      );
      final tray = TrayService();
      await tray.updateState(DictationState.idle);
      await tray.refresh();
      expect(calls.where((c) => c.method == 'setIcon').length, 1);
      await tray.updateActivity('API transcription');
      expect(calls.where((c) => c.method == 'setIcon').length, 2);
      await tray.refresh();
      expect(calls.where((c) => c.method == 'setIcon').length, 2);
      await tray.updateActivity(null);
      await tray.updateState(DictationState.transcribing);
      await tray.updateState(DictationState.grammarCleanup);
      await tray.updateState(DictationState.inserting);
      expect(calls.where((c) => c.method == 'setIcon').length, 4);
      expect(calls.where((c) => c.method == 'setContextMenu').length, 8);
      expect(calls.where((c) => c.method == 'setToolTip').length, 8);
      await tray.updateState(DictationState.idle);
      pendingIcon = Completer<void>();
      final busy = tray.updateState(DictationState.recording);
      await Future<void>.delayed(Duration.zero);
      final ready = tray.updateState(DictationState.idle);
      pendingIcon.complete();
      await Future.wait([busy, ready]);
      final lastIcon = calls.lastWhere((c) => c.method == 'setIcon');
      expect(
        (lastIcon.arguments['iconPath'] as String).endsWith('tray_icon.png'),
        true,
      );
    },
  );
  test(
    'tray hides optional tools and retains the active meeting stop action',
    () async {
      SharedPreferences.setMockInitialValues({});
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.aurascribe/accessibility'),
        (_) async => '',
      );
      Object? menu;
      messenger.setMockMethodCallHandler(const MethodChannel('tray_manager'), (
        call,
      ) async {
        if (call.method == 'setContextMenu') menu = call.arguments;
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(
          const MethodChannel('tray_manager'),
          null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('com.aurascribe/accessibility'),
          null,
        );
      });
      final settings = SettingsService();
      await settings.init();
      final tray = TrayService(settings: settings);
      await tray.refresh();
      expect(jsonEncode(menu), isNot(contains('Record meeting')));
      expect(jsonEncode(menu), isNot(contains('Capture')));
      await settings.setSettingsPageVisible(7, true);
      await settings.setSettingsPageVisible(9, true);
      await tray.refresh();
      expect(jsonEncode(menu), contains('Record meeting'));
      expect(jsonEncode(menu), contains('Capture'));
      await settings.setSettingsPageVisible(7, false);
      await tray.updateActivity('Meeting recording');
      expect(jsonEncode(menu), contains('Stop meeting'));
    },
  );
}
