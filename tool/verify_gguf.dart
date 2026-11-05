// Real download/native inference; opt-in tool, excluded from the fast test suite.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_to_text/settings/settings_service.dart';
import 'package:voice_to_text/storage/project_storage.dart';
import 'package:voice_to_text/transcription/gguf_transcription_backend.dart';
import 'package:voice_to_text/transcription/moonshine_transcription_backend.dart';

class FixtureSettings extends SettingsService {
  @override
  String get ggufModel => 'sensevoice';
  @override
  String get language => 'en';
  @override
  String get decoderVocabulary => '';
}

void main() {
  test('pinned GGUF model decodes public audio using the bundled runtime',
      () async {
    await ProjectStorage.initialize(projectPath: Directory.current.path);
    final backend = GgufTranscriptionBackend(FixtureSettings());
    addTearDown(backend.dispose);
    expect(await backend.load(), isNull, reason: backend.statusMessage);
    final sample = await ProjectStorage.instance.download(
        folder: 'benchmark-fixtures',
        name: 'sample.wav',
        url: Uri.parse(
            '${MoonshineTranscriptionBackend.baseUrl}/test_wavs/0.wav'));
    final timer = Stopwatch()..start();
    final result = await backend.transcribe(sample);
    expect(result.toLowerCase(), contains('yellow'));
    // ignore: avoid_print
    print(
        'GGUF native decode ${timer.elapsedMilliseconds} ms; public sample: $result');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
