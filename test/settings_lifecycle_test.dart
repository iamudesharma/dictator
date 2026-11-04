import 'dart:async';
import 'dart:convert';
import '../tool/vm_heap_profile.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_to_text/accessibility/accessibility_service.dart';
import 'package:voice_to_text/app/app.dart';
import 'package:voice_to_text/app/dictation_orchestrator.dart';
import 'package:voice_to_text/audio/audio_service.dart';
import 'package:voice_to_text/grammar/grammar_model_service.dart';
import 'package:voice_to_text/grammar/grammar_service.dart';
import 'package:voice_to_text/grammar/smart_command_service.dart';
import 'package:voice_to_text/history/history_service.dart';
import 'package:voice_to_text/hotkeys/hotkey_service.dart';
import 'package:voice_to_text/settings/settings_screen.dart';
import 'package:voice_to_text/settings/settings_service.dart';
import 'package:voice_to_text/settings/settings_shell.dart';
import 'package:voice_to_text/storage/project_storage.dart';
import 'package:voice_to_text/transcription/transcription_service.dart';
import 'package:voice_to_text/vad/vad_service.dart';
import 'all_settings_pages_test.dart' show FakeRecord, FakeTray;

void main() {
  testWidgets(
      '20 settings visibility cycles dispose listeners and preserve unsaved vocabulary',
      (tester) async {
    late Directory dir;
    late SettingsService settings;
    await tester.runAsync(() async {
      dir = await Directory.current.createTemp('.memory-ui-test-');
      await File('${dir.path}/pubspec.yaml').writeAsString('name: fixture');
      ProjectStorage.instance = ProjectStorage(dir);
      SharedPreferences.setMockInitialValues({});
      RecordPlatform.instance = FakeRecord();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('window_manager'), (_) async => null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('flutter/platform', JSONMethodCodec()),
              (call) async => call.method == 'Clipboard.hasStrings'
                  ? {'value': false}
                  : null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('com.aurascribe/accessibility'),
              (call) async => switch (call.method) {
                    'readHfToken' => '',
                    'checkPermission' => false,
                    'launchAtLogin' => false,
                    'keyboardSources' => [],
                    _ => null,
                  });
      settings = SettingsService();
      await settings.init();
    });
    final audio = AudioService(settings),
        model = TranscriptionService(settings);
    final grammar = GrammarService.simple(settings),
        ax = AccessibilityService();
    final orchestrator = DictationOrchestrator(
        audio: audio,
        vad: VadService(audio, settings),
        transcription: model,
        grammar: grammar,
        accessibility: ax,
        tray: FakeTray(),
        smartCommand:
            SmartCommandService(() => GrammarModelService(settings), model),
        settings: settings);
    await tester.pumpWidget(AuraScribeApp(
        orchestrator: orchestrator,
        settings: settings,
        hotkeyService: HotkeyService(settings),
        accessibility: ax,
        transcriptionService: model,
        grammarService: grammar));
    expect(find.byType(SettingsScreen), findsNothing);
    const profileHeap = bool.fromEnvironment('MEMORY_HEAP_PROFILE');
    final heapSamples = <Map<String, Object?>>[];
    if (profileHeap) {
      heapSamples
          .add({'cycle': 0, ...await tester.runAsync(captureHeapCounts) ?? {}});
    }
    for (var cycle = 0; cycle < 20; cycle++) {
      orchestrator.setSettingsVisible(true);
      await tester.pumpAndSettle();
      tester.widget<SettingsShell>(find.byType(SettingsShell)).onSelected(3);
      await tester.pumpAndSettle();
      final field = find.byWidgetPredicate((w) =>
          w is TextField &&
          w.decoration?.labelText == 'Recognition vocabulary');
      if (cycle == 0) {
        await tester.enterText(field, 'Unsaved proper name');
      } else {
        expect(tester.widget<TextField>(field).controller!.text,
            'Unsaved proper name');
      }
      orchestrator.onWindowClose();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
      // ignore: invalid_use_of_protected_member
      expect(model.hasListeners, false);
      // ignore: invalid_use_of_protected_member
      expect(HistoryService.instance.hasListeners, false);
      if (profileHeap && [4, 9, 19].contains(cycle)) {
        heapSamples.add({
          'cycle': cycle + 1,
          ...await tester.runAsync(captureHeapCounts) ?? {}
        });
      }
    }
    if (profileHeap) {
      final target = File(
          '${Directory.current.path}/.aurascribe/benchmarks/memory/settings-heap.json');
      await tester.runAsync(() => target.writeAsString(
          const JsonEncoder.withIndent('  ').convert(heapSamples)));
    }
    // Modal behavior is checked in the normal run. Its synthetic completer
    // retains the test's async scope, so exclude it from the separate 20-cycle
    // allocation experiment (which measures normal settings close/reopen).
    if (!profileHeap) {
      // A hidden window keeps an in-progress modal editor alive until its draft
      // is accepted/cancelled, then releases the UI normally.
      orchestrator.setSettingsVisible(true);
      await tester.pumpAndSettle();
      final editor = Completer<String?>();
      final dialog = orchestrator.withSettingsDialog(() => editor.future);
      orchestrator.onWindowClose();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      editor.complete(null);
      await dialog;
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.idle();
    orchestrator.dispose();
    model.dispose();
    await tester.pump();
    await tester.pump();
    await tester.runAsync(() => dir.delete(recursive: true));
  });
  if (const bool.fromEnvironment('MEMORY_HEAP_PROFILE')) {
    test(
        'disposed settings are collectible after the async test scope completes',
        () async {
      final profile = await captureHeapCounts(retainingPath: true);
      final target = File(
          '${Directory.current.path}/.aurascribe/benchmarks/memory/settings-heap-after-scope.json');
      await target
          .writeAsString(const JsonEncoder.withIndent('  ').convert(profile));
      final classes = profile['classes'] as Map;
      expect(
          (classes['_SettingsScreenState'] as Map?)?['instancesCurrent'] ?? 0,
          0);
      expect(
          (classes['TextEditingController'] as Map?)?['instancesCurrent'] ?? 0,
          0);
    });
  }
}
