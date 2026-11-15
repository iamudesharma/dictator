// Isolates preprocessing cost; excludes inference, Flutter and tray updates.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:voice_to_text/audio/pcm_wave.dart';
import 'package:voice_to_text/transcription/native/transcribe_bindings.g.dart';

Future<void> main(List<String> args) async {
  final native = args.first == 'native';
  final source =
      '${Directory.current.path}/.aurascribe/benchmarks/metal-comparison/sample.wav';
  final clip = File(
    '${Directory.current.path}/.aurascribe/benchmarks/resource-comparison/pcm-clip.wav',
  );
  final api = TranscribeBindings(
    DynamicLibrary.open(
      '${Directory.current.path}/.aurascribe/tools/native/libaurascribe_audio.dylib',
    ),
  );
  final watch = Stopwatch()..start();
  final iterations = int.parse(args[1]);
  double check = 0;
  try {
    for (var i = 0; i < iterations; i++) {
      final wave = await PcmWave.open(source);
      final count = wave.dataBytes ~/ 2;
      final arena = Arena();
      try {
        final output = arena<Float>(count);
        if (native) {
          final code = api.aurascribe_pcm_read(
            source.toNativeUtf8(allocator: arena).cast(),
            wave.dataOffset,
            count,
            output,
            1,
          );
          if (code != 0) throw StateError('Unexpected PCM result $code');
        } else {
          if (!await wave.writeClip(clip, 0, wave.seconds)) {
            throw StateError('Silent fixture');
          }
          final copied = await PcmWave.open(clip.path);
          final file = await clip.open();
          late Uint8List bytes;
          try {
            await file.setPosition(copied.dataOffset);
            bytes = await file.read(count * 2);
          } finally {
            await file.close();
          }
          final data = ByteData.sublistView(bytes),
              floats = output.asTypedList(count);
          for (var j = 0; j < count; j++) {
            floats[j] = data.getInt16(j * 2, Endian.little) / 32768;
          }
        }
        check += output[count ~/ 2];
      } finally {
        arena.releaseAll();
      }
    }
  } finally {
    if (await clip.exists()) await clip.delete();
  }
  stdout.writeln(
    jsonEncode({
      'mode': native ? 'native' : 'old',
      'iterations': iterations,
      'wallSeconds': watch.elapsedMicroseconds / 1e6,
      'peakRssBytes': ProcessInfo.maxRss,
      'check': check,
    }),
  );
}
