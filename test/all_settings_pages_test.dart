import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_to_text/accessibility/accessibility_service.dart';
import 'package:voice_to_text/app/dictation_orchestrator.dart';
import 'package:voice_to_text/audio/audio_service.dart';
import 'package:voice_to_text/grammar/grammar_model_service.dart';
import 'package:voice_to_text/grammar/grammar_service.dart';
import 'package:voice_to_text/grammar/smart_command_service.dart';
import 'package:voice_to_text/hotkeys/hotkey_service.dart';
import 'package:voice_to_text/settings/settings_screen.dart';
import 'package:voice_to_text/settings/settings_service.dart';
import 'package:voice_to_text/settings/settings_shell.dart';
import 'package:voice_to_text/shared/app_theme.dart';
import 'package:voice_to_text/shared/dictation_state.dart';
import 'package:voice_to_text/storage/project_storage.dart';
import 'package:voice_to_text/transcription/transcription_service.dart';
import 'package:voice_to_text/tray/tray_service.dart';
import 'package:voice_to_text/vad/vad_service.dart';

class FakeRecord extends RecordPlatform {
  @override
  Future<void> create(String id) async {}
  @override
  Future<void> dispose(String id) async {}
  @override
  Future<List<InputDevice>> listInputDevices(String id) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTray extends TrayService {
  @override
  Future<void> updateState(DictationState state) async {}
  @override
  Future<void> updateActivity(String? value) async {}
  @override
  Future<void> updateVoiceActivity(String? value) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final width in [680.0, 960.0]) {
    testWidgets('all feature pages render without overflow at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Directory dir;
      late SettingsService settings;
      await tester.runAsync(() async {
        dir = await Directory.current.createTemp('.pages-test-');
        await File('${dir.path}/pubspec.yaml').writeAsString('name: fixture');
        ProjectStorage.instance = ProjectStorage(dir);
        SharedPreferences.setMockInitialValues({});
        RecordPlatform.instance = FakeRecord();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
                const MethodChannel('com.aurascribe/accessibility'),
                (call) async => switch (call.method) {
                      'readHfToken' => '',
                      'launchAtLogin' => false,
                      'keyboardSources' => [],
                      'checkPermission' => false,
                      _ => null
                    });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
                const MethodChannel('com.aurascribe/voice_filter'),
                (call) async => {
                      'installed': false,
                      'running': false,
                      'levelDb': -90,
                      'error': ''
                    });
        settings = SettingsService();
        await settings.init();
      });
      final audio = AudioService(settings),
          transcription = TranscriptionService(settings);
      final model = GrammarModelService(settings),
          grammar = GrammarService.simple(settings),
          accessibility = AccessibilityService();
      final orchestrator = DictationOrchestrator(
          audio: audio,
          vad: VadService(audio, settings),
          transcription: transcription,
          grammar: grammar,
          accessibility: accessibility,
          tray: FakeTray(),
          smartCommand: SmartCommandService(() => model, transcription),
          settings: settings);
      await tester.pumpWidget(MaterialApp(
          theme: auraTheme(Brightness.dark),
          home: SettingsScreen(
              settings: settings,
              hotkeyService: HotkeyService(settings),
              accessibility: accessibility,
              transcriptionService: transcription,
              grammarService: grammar,
              orchestrator: orchestrator)));
      for (var i = 0; i < settingsPages.length; i++) {
        final icon = find.byIcon(settingsIcons[i]).first;
        await tester.scrollUntilVisible(icon, 70,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(icon);
        await tester.pumpAndSettle();
        expect(find.text(settingsPages[i]), findsWidgets);
        expect(tester.takeException(), isNull,
            reason: 'Page ${settingsPages[i]} at $width');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      orchestrator.dispose();
      transcription.dispose();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await dir.delete(recursive: true);
      });
    });
  }
}
