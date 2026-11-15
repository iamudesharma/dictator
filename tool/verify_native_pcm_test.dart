import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_to_text/audio/pcm_wave.dart';
import 'package:voice_to_text/shared/wav_header_helper.dart';
import 'package:voice_to_text/transcription/native/transcribe_bindings.g.dart';

void main() {
  test('native PCM conversion and silence gate match the previous Dart path', () async {
    final api = TranscribeBindings(
      DynamicLibrary.open(
        '${Directory.current.path}/.aurascribe/tools/native/libaurascribe_audio.dylib',
      ),
    );
    final folder = await Directory('.aurascribe/benchmarks')
        .createTemp('pcm-check-');
    try {
      final file = File('${folder.path}/source.wav');
      final clip = File('${folder.path}/clip.wav');
      for (final amplitude in [0, 56, 57, 1500, 32767]) {
        final pcm = Uint8List(32000), data = ByteData.sublistView(pcm);
        for (var i = 0; i < 16000; i++) {
          data.setInt16(
            i * 2,
            i.isEven ? amplitude : -amplitude,
            Endian.little,
          );
        }
        await file.writeAsBytes([
          ...WavHeaderHelper.buildHeader(pcm.length),
          ...pcm,
        ]);
        final wave = await PcmWave.open(file.path);
        final accepted = await wave.writeClip(clip, 0, 1);
        using((arena) {
          final output = arena<Float>(16000);
          final path = file.path.toNativeUtf8(allocator: arena).cast<Char>();
          expect(
            api.aurascribe_pcm_read(path, wave.dataOffset, 16000, output, 1),
            accepted ? 0 : 1,
          );
          final floats = output.asTypedList(16000);
          for (var i = 0; i < 16000; i++) {
            expect(floats[i], data.getInt16(i * 2, Endian.little) / 32768);
          }
          expect(
            api.aurascribe_pcm_read(
              path,
              wave.dataOffset + 31800,
              100,
              output,
              0,
            ),
            0,
          );
          expect(
            api.aurascribe_pcm_read(
              path,
              wave.dataOffset + 31800,
              101,
              output,
              0,
            ),
            -2,
          );
          expect(api.aurascribe_pcm_read(path, -1, 100, output, 0), -1);
          expect(api.aurascribe_pcm_read(path, 0, 400001, output, 0), -1);
        });
      }
    } finally {
      await folder.delete(recursive: true);
    }
  });
}
