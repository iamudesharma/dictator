import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
import 'package:voice_to_text/shared/wav_header_helper.dart';
import 'package:voice_to_text/storage/project_storage.dart';
import 'package:voice_to_text/transcription/transcription_service.dart';
import 'package:voice_to_text/vad/vad_service.dart';
import 'package:voice_to_text/transcription/timed_transcript.dart';

import 'all_settings_pages_test.dart' show FakeRecord, FakeTray;
import 'transcription_lifecycle_test.dart' show FixtureBackend;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final direct in [false, true]) {
    test(
      'loopback API authenticates and processes WAV (direct slices: $direct)',
      () async {
        final directory = await Directory.systemTemp.createTemp('aura-api-');
        await File('${directory.path}/pubspec.yaml')
            .writeAsString('name: fixture');
        ProjectStorage.instance = ProjectStorage(directory);
        SharedPreferences.setMockInitialValues({
          'control_api': true,
          'vocabulary': 'fixture=corrected',
        });
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          const MethodChannel('com.aurascribe/accessibility'),
          (_) async => '',
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (_) async => null,
        );
        RecordPlatform.instance = FakeRecord();
        final settings = SettingsService();
        await settings.init();
        final sliced = SliceFixture();
        final audio = AudioService(settings),
            transcription = TranscriptionService(
              settings,
              backendFactory: (_) => direct ? sliced : FixtureBackend(),
            );
        final model = GrammarModelService(settings),
            grammar = GrammarService.simple(settings);
        final orchestrator = DictationOrchestrator(
          audio: audio,
          vad: VadService(audio, settings),
          transcription: transcription,
          grammar: grammar,
          accessibility: AccessibilityService(),
          tray: FakeTray(),
          smartCommand: SmartCommandService(() => model, transcription),
          settings: settings,
        );
        final previousOverrides = HttpOverrides.current;
        HttpOverrides.global = null;
        addTearDown(() => HttpOverrides.global = previousOverrides);
        final client = HttpClient();
        addTearDown(() async {
          await orchestrator.control.close();
          client.close(force: true);
          orchestrator.dispose();
          transcription.dispose();
          await directory.delete(recursive: true);
        });
        await orchestrator.control.configure();
        final receipt = jsonDecode(
          await File('${directory.path}/.aurascribe/control/connection.json')
              .readAsString(),
        );
        final uri = Uri.parse('http://127.0.0.1:${receipt['port']}');
        final denied = await (await client.getUrl(uri.resolve('/status')))
            .close();
        expect(denied.statusCode, 401);
        await denied.drain<void>();
        final pcm = Uint8List(32000), data = ByteData.sublistView(pcm);
        for (var i = 0; i < pcm.length; i += 2) {
          data.setInt16(i, i % 4 == 0 ? 1500 : -1500, Endian.little);
        }
        final wav = File('${directory.path}/sample.wav');
        await wav.writeAsBytes([
          ...WavHeaderHelper.buildHeader(pcm.length),
          ...pcm,
        ]);
        Future<(int, dynamic)> post(Map<String, dynamic> body) async {
          final request = await client.postUrl(uri.resolve('/transcriptions'));
          request.headers.set('Authorization', 'Bearer ${receipt['token']}');
          request.write(jsonEncode(body));
          final response = await request.close();
          return (
            response.statusCode,
            jsonDecode(await response.transform(utf8.decoder).join()),
          );
        }

        final result = await post({'path': wav.path, 'process': true});
        expect(result.$1, 200);
        expect(result.$2['text'], 'corrected');
        expect(result.$2.containsKey('segments'), false);
        final unsupported = await post({
          'path': wav.path,
          'timestamps': 'word',
        });
        expect(unsupported.$1, direct ? 200 : 422);
        if (direct) {
          expect(sliced.paths, [wav.path, wav.path]);
          expect(sliced.counts, [16000, 16000]);
          expect(unsupported.$2['words'][0]['start'], 0.1);
          expect(
            await File('${directory.path}/.aurascribe/tmp/api-clip.wav')
                .exists(),
            false,
          );
          // Two slices keep native timestamps relative to the original file.
          final longer = File('${directory.path}/long.wav');
          final bytes = Uint8List(26 * 32000);
          await longer.writeAsBytes([
            ...WavHeaderHelper.buildHeader(bytes.length),
            ...bytes,
          ]);
          final multi = await post({'path': longer.path, 'timestamps': 'word'});
          expect(multi.$1, 200);
          expect(sliced.starts.sublist(2), [0, 400000]);
          expect(sliced.counts.sublist(2), [400000, 16000]);
          expect(multi.$2['words'][1]['start'], 25.1);
          sliced.silent = true;
          final silent = await post({'path': wav.path, 'process': true});
          expect(silent.$2['text'], '');
        }
        expect(orchestrator.externalActivity, isNull);
        await orchestrator.control.close();
        expect(
          await File('${directory.path}/.aurascribe/control/connection.json')
              .exists(),
          false,
        );
      },
    );
  }
}

class SliceFixture extends FixtureBackend implements SlicedSttBackend {
  final paths = <String>[];
  final starts = <int>[];
  final counts = <int>[];
  bool silent = false;
  @override
  Future<TimedTranscript> transcribeSlice(
    String path, {
    required int startSample,
    required int sampleCount,
    required String timestamps,
    required bool skipSilence,
  }) async {
    expect(skipSilence, true);
    paths.add(path);
    starts.add(startSample);
    counts.add(sampleCount);
    if (silent) return const TimedTranscript('', skippedSilence: true);
    return const TimedTranscript(
      'fixture',
      words: [TranscriptSpan(0.1, 0.5, 'fixture')],
    );
  }
}
