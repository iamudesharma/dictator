import 'dart:async';
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
import 'package:voice_to_text/settings/settings_service.dart';
import 'package:voice_to_text/shared/dictation_indicator.dart';
import 'package:voice_to_text/shared/dictation_state.dart';
import 'package:voice_to_text/shared/dictation_mode.dart';
import 'package:voice_to_text/shared/sound_service.dart';
import 'package:voice_to_text/shared/stt_engine.dart';
import 'package:voice_to_text/storage/project_storage.dart';
import 'package:voice_to_text/transcription/transcription_service.dart';
import 'package:voice_to_text/vad/vad_service.dart';
import 'all_settings_pages_test.dart' show FakeRecord, FakeTray;

class HeldAudio extends AudioService {
  HeldAudio(super.settings);
  final entered = Completer<void>();
  Completer<void>? barrier;
  int starts = 0, cancels = 0;
  String? resultPath;
  @override
  Future<String?> stop() async => resultPath;
  @override
  Future<void> start() async {
    starts++;
    if (!entered.isCompleted) entered.complete();
    await barrier?.future;
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }
}

class HeldModel extends TranscriptionService {
  HeldModel(super.settings);
  final entered = Completer<void>(), barrier = Completer<void>();
  bool ready = false;
  @override
  bool get isLoaded => ready;
  @override
  SttEngine get activeEngine => SttEngine.gguf;
  @override
  String get modelLabel => 'Fixture';
  @override
  Future<String> transcribe(String path) async => 'Fixture transcript';
  @override
  Future<String?> ensureLoaded() async {
    entered.complete();
    await barrier.future;
    ready = true;
    return null;
  }
}

class HeldVad extends VadService {
  HeldVad(super.audio, super.settings);
  @override
  void start() {}
  @override
  void stop() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late SettingsService settings;
  late HeldAudio audio;
  late HeldModel model;
  late DictationOrchestrator orchestrator;
  setUp(() async {
    dir = await Directory.current.createTemp('.hold-test-');
    await File('${dir.path}/pubspec.yaml').writeAsString('name: fixture');
    ProjectStorage.instance = ProjectStorage(dir);
    SharedPreferences.setMockInitialValues(
        {'show_indicator': false, 'hold_shortcut': true});
    RecordPlatform.instance = FakeRecord();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.aurascribe/accessibility'),
            (call) async => switch (call.method) {
                  'readHfToken' => '',
                  'frontmostApplication' => <String, String>{},
                  'currentKeyboardSource' => '',
                  'checkPermission' => false,
                  _ => null,
                });
    settings = SettingsService();
    await settings.init();
    SoundService.volume = 0;
    audio = HeldAudio(settings);
    model = HeldModel(settings);
    orchestrator = DictationOrchestrator(
        audio: audio,
        vad: HeldVad(audio, settings),
        transcription: model,
        grammar: GrammarService.simple(settings),
        accessibility: AccessibilityService(),
        tray: FakeTray(),
        smartCommand:
            SmartCommandService(() => GrammarModelService(settings), model),
        settings: settings);
  });
  tearDown(() async {
    orchestrator.dispose();
    model.dispose();
    await Future<void>.delayed(Duration.zero);
    await dir.delete(recursive: true);
  });
  test('early hold release during model preparation never opens microphone',
      () async {
    final pending = orchestrator.startHeldDictation();
    await model.entered.future;
    expect(orchestrator.isPreparing, isTrue);
    await orchestrator.startHeldDictation(); // Ignore key repeat.
    await orchestrator.stopHeldDictation();
    model.barrier.complete();
    await pending;
    expect(audio.starts, 0);
    expect(orchestrator.state, DictationState.idle);
    expect(orchestrator.isPreparing, isFalse);
  });
  test('hold release during audio startup cancels without entering recording',
      () async {
    model.ready = true;
    audio.barrier = Completer<void>();
    final pending = orchestrator.startHeldDictation();
    await audio.entered.future;
    await orchestrator.stopHeldDictation();
    audio.barrier!.complete();
    await pending;
    expect(audio.cancels, 1);
    expect(orchestrator.state, DictationState.idle);
  });
  test(
      'destination is captured before native panel; main Flutter window is never shown',
      () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.aurascribe/accessibility'), (call) async {
      calls.add(call.method);
      if (call.method == 'beginDictationTarget') {
        return {'bundleId': 'fixture.editor', 'name': 'Fixture'};
      }
      if (call.method == 'currentKeyboardSource') return '';
      return null;
    });
    await settings.setShowIndicator(true);
    final pending = orchestrator.startHeldDictation();
    await model.entered.future;
    expect(calls.indexOf('beginDictationTarget'),
        lessThan(calls.indexOf('showDictationIndicator')));
    // There is deliberately no window_manager mock: using it would fail startup.
    expect(orchestrator.isPreparing, isTrue);
    await orchestrator.stopHeldDictation();
    model.barrier.complete();
    await pending;
    await Future<void>.delayed(Duration.zero);
    expect(calls, contains('hideDictationIndicator'));
  });
  for (final mode in DictationMode.values) {
    test('failed $mode insertion reports an error and retains transcript',
        () async {
      await settings.setDictationMode(mode);
      model.ready = true;
      audio.resultPath = '${dir.path}/fixture.wav';
      await File(audio.resultPath!).writeAsBytes([0]);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('com.aurascribe/accessibility'),
              (call) async {
        if (call.method == 'beginDictationTarget') {
          return {'bundleId': 'fixture.editor'};
        }
        if (call.method == 'currentKeyboardSource') return '';
        if (call.method == 'checkPermission') return false;
        if (call.method == 'insertText') {
          throw PlatformException(code: 'ACCESSIBILITY_REQUIRED');
        }
        return null;
      });
      await orchestrator.startHeldDictation();
      await orchestrator.stopHeldDictation();
      expect(orchestrator.state, DictationState.error);
      expect(orchestrator.lastTranscript, 'Fixture transcript');
      expect(orchestrator.errorMessage, contains('ACCESSIBILITY_REQUIRED'));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('com.aurascribe/accessibility'),
              (call) async {
        if (call.method == 'beginDictationTarget') {
          return {'bundleId': 'fixture.other-editor'};
        }
        if (call.method == 'insertText') return true;
        return null;
      });
      await orchestrator.pasteLast();
      expect(orchestrator.state, DictationState.idle);
    });
  }
  test('each clip session inserts its text even when live mode is selected',
      () async {
    model.ready = true;
    audio.resultPath = '${dir.path}/fixture.wav';
    await File(audio.resultPath!).writeAsBytes([0]);
    var inserts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.aurascribe/accessibility'), (call) async {
      if (call.method == 'beginDictationTarget') {
        return {'bundleId': 'fixture.editor'};
      }
      if (call.method == 'currentKeyboardSource') return '';
      if (call.method == 'checkPermission') return true;
      if (call.method == 'insertText') {
        inserts++;
        return true;
      }
      return null;
    });
    for (var i = 0; i < 2; i++) {
      await orchestrator.startHeldDictation();
      await orchestrator.stopHeldDictation();
      expect(orchestrator.state, DictationState.idle);
    }
    expect(inserts, 2);
  });
  testWidgets('preparation preview stays compact without capture controls',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: DictationIndicator(
                label: 'Preparing speech model', preparing: true))));
    expect(find.byType(VoiceLevelBars), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('dictation-pill'))),
        const Size(104, 30));
  });
}
