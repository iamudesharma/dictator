import 'dart:io';
import 'dart:typed_data';
import 'pcm_wave.dart';
import '../shared/wav_header_helper.dart';

/// Shortens only pauses over one second, retaining 200 ms on either side.
/// Reads in 20 ms frames; memory use does not grow with recording length.
Future<void> compactPauses(String input, File output) async {
  final wave = await PcmWave.open(input);
  final source = await File(input).open();
  final sink = output.openWrite();
  var written = 0, silentCount = 0;
  final first = <Uint8List>[], last = <Uint8List>[];
  void write(Uint8List bytes) {
    sink.add(bytes);
    written += bytes.length;
  }

  void flushSilence() {
    for (final bytes in first) {
      write(bytes);
    }
    for (final bytes in last) {
      write(bytes);
    }
    first.clear();
    last.clear();
    silentCount = 0;
  }

  try {
    sink.add(WavHeaderHelper.buildHeader(0));
    await source.setPosition(wave.dataOffset);
    var remaining = wave.dataBytes;
    while (remaining > 0) {
      final bytes = await source.read(remaining.clamp(0, 640));
      if (bytes.isEmpty) throw const FormatException('Incomplete recording.');
      remaining -= bytes.length;
      final data = ByteData.sublistView(bytes);
      var energy = 0.0;
      for (var i = 0; i + 1 < bytes.length; i += 2) {
        final v = data.getInt16(i, Endian.little) / 32768;
        energy += v * v;
      }
      if (energy / (bytes.length / 2) < 0.000003) {
        silentCount++;
        if (silentCount <= 10) {
          first.add(bytes);
        } else {
          last.add(bytes);
          if (silentCount > 50 && last.length > 10) {
            last.removeRange(0, last.length - 10);
          }
        }
      } else {
        flushSilence();
        write(bytes);
      }
    }
    flushSilence();
  } finally {
    await source.close();
    await sink.close();
  }
  final file = await output.open(mode: FileMode.writeOnlyAppend);
  try {
    await file.setPosition(0);
    await file.writeFrom(WavHeaderHelper.buildHeader(written));
  } finally {
    await file.close();
  }
}
