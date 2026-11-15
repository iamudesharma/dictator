import 'dart:io';
import 'dart:typed_data';

import 'package:voice_to_text/audio/pcm_wave.dart';

import '../test/support/wav_fixtures.dart';

import 'package:voice_to_text/shared/wav_header_helper.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_to_text/transcription/native/native_speech_session.dart';

void main() {
  test('native Metal reuses a session, survives invalid input and closes cleanly', () async {
    final root = Directory.current.path;
    final library = '$root/.aurascribe/tools/native/libtranscribe.0.4.1.dylib';
    final model =
        '$root/.aurascribe/models/gguf/parakeet_unified_english/parakeet-unified-en-0.6b-Q8_0.gguf';
    final sample = '$root/.aurascribe/benchmarks/comparison/sample.wav';
    final expected = await File(
      '$root/.aurascribe/benchmarks/comparison/reference.txt',
    ).readAsString();
    final native = await NativeSpeechSession.open(
      library,
      model,
      prewarm: true,
    );
    expect(native.backend, startsWith('MTL'));
    try {
      await expectLater(
        native.transcribe('$root/missing.wav', 'en', '', 'parakeet', 'none'),
        throwsA(isA<FileSystemException>()),
      );
      for (var i = 0; i < 3; i++) {
        final result = await native.transcribe(
          sample,
          'en',
          '',
          'parakeet',
          'none',
        );
        expect(result.text, expected.trim());
        expect(native.backend, startsWith('MTL'));
      }
      // Microphone WAVs use an extensible PCM subtype, unlike the old fixture.
      final wave = await PcmWave.open(sample);
      final original = await File(sample).readAsBytes();
      final apple = File(
        '$root/.aurascribe/benchmarks/wav-regression/apple-microphone-fixture.wav',
      );
      await apple.parent.create(recursive: true);
      await apple.writeAsBytes(
        appleWave(
          original.sublist(wave.dataOffset, wave.dataOffset + wave.dataBytes),
        ),
      );
      final appleResult = await native.transcribe(
        apple.path,
        'en',
        '',
        'parakeet',
        'segment',
      );
      expect(appleResult.text, expected.trim());
      expect(appleResult.segments, isNotEmpty);
      expect(native.backend, startsWith('MTL'));
      final silence = File('$root/.aurascribe/benchmarks/slice-silence.wav');
      await silence.writeAsBytes([
        ...WavHeaderHelper.buildHeader(32000),
        ...Uint8List(32000),
      ]);
      try {
        final silent = await native.transcribeSlice(
          silence.path,
          'en',
          '',
          'parakeet',
          'word',
          startSample: 0,
          sampleCount: 16000,
          skipSilence: true,
        );
        expect(silent.skippedSilence, true);
        expect(silent.text, isEmpty);
        await expectLater(
          native.transcribeSlice(
            sample,
            'en',
            '',
            'parakeet',
            'none',
            startSample: -1,
            sampleCount: 16000,
            skipSilence: true,
          ),
          throwsStateError,
        );
        final slice = await native.transcribeSlice(
          sample,
          'en',
          '',
          'parakeet',
          'segment',
          startSample: 0,
          sampleCount: 321585,
          skipSilence: true,
        );
        expect(slice.text, expected.trim());
        expect(slice.skippedSilence, false);
        expect(slice.segments, isNotEmpty);
      } finally {
        await silence.delete();
      }
      final timed = await native.transcribe(
        sample,
        'en',
        '',
        'parakeet',
        'segment',
      );
      expect(timed.segments, isNotEmpty);
      expect(timed.segments.last.end, lessThanOrEqualTo(20.2));
    } finally {
      await native.close();
    }
    await native.close();
    final reloaded = await NativeSpeechSession.open(
      library,
      model,
      prewarm: true,
    );
    try {
      expect(reloaded.backend, startsWith('MTL'));
      expect(
        (await reloaded.transcribe(sample, 'en', '', 'parakeet', 'none')).text,
        expected.trim(),
      );
    } finally {
      await reloaded.close();
    }
    await expectLater(
      native.transcribe(sample, 'en', '', 'parakeet', 'none'),
      throwsStateError,
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
