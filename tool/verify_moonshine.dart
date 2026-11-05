// Run with flutter test --dart-define=SHERPA_LIBRARY_DIR=/absolute/native/libs
// tool/verify_moonshine.dart. Downloads only into this checkout's .aurascribe/.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_to_text/storage/project_storage.dart';
import 'package:voice_to_text/transcription/moonshine_transcription_backend.dart';

void main() {
  test('Moonshine recognizes the upstream sample with project-local weights',
      () async {
    await ProjectStorage.initialize(projectPath: Directory.current.path);
    final backend = MoonshineTranscriptionBackend();
    addTearDown(backend.dispose);
    final rssBefore = ProcessInfo.currentRss;
    final timer = Stopwatch()..start();
    expect(await backend.load(), isNull);
    final loadMs = timer.elapsedMilliseconds;
    final rssLoaded = ProcessInfo.currentRss;
    final sample = await ProjectStorage.instance.download(
        folder: 'moonshine_tiny_int8',
        name: 'verification.wav',
        url: Uri.parse(
            '${MoonshineTranscriptionBackend.baseUrl}/test_wavs/0.wav'));
    timer.reset();
    final text = await backend.transcribe(sample);
    expect(text.toLowerCase(), contains('after early nightfall'));
    // Diagnostic output deliberately contains only the public upstream sample.
    // ignore: avoid_print
    print(
        'RSS before=$rssBefore loaded=$rssLoaded peak=${ProcessInfo.maxRss}; Moonshine load=$loadMs ms, decode=${timer.elapsedMilliseconds} ms, sample="$text"');
    expect(ProjectStorage.instance.models.path,
        startsWith(Directory.current.path));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
