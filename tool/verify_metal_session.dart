import 'dart:io';

import 'package:voice_to_text/transcription/native/native_speech_session.dart';

Future<void> main() async {
  final root = Directory.current.path;
  final session = await NativeSpeechSession.open(
    '$root/.aurascribe/tools/native/libtranscribe.0.4.1.dylib',
    '$root/.aurascribe/models/gguf/parakeet_unified_english/parakeet-unified-en-0.6b-Q8_0.gguf',
  );
  stdout.writeln('backend=${session.backend}');
  try {
    for (var i = 0; i < 3; i++) {
      final timer = Stopwatch()..start();
      final result = await session.transcribe(
        '$root/.aurascribe/benchmarks/comparison/sample.wav',
        'en',
        '',
        'parakeet',
        'none',
      );
      stdout.writeln(
        'run=$i milliseconds=${timer.elapsedMilliseconds} words=${result.text.split(' ').length}',
      );
      if (!result.text.startsWith('Today we are measuring')) {
        throw StateError('Unexpected recognition');
      }
    }
  } finally {
    await session.close();
  }
}
