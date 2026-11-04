import 'dart:io';
import 'dart:typed_data';
import '../shared/wav_header_helper.dart';

class PcmWave {
  final String path;
  final int dataOffset, dataBytes;
  const PcmWave._(this.path, this.dataOffset, this.dataBytes);
  double get seconds => dataBytes / 32000;
  static Future<PcmWave> open(String path) async {
    final file = await File(path).open();
    try {
      final header = await file.read(12);
      if (header.length != 12 ||
          String.fromCharCodes(header.sublist(0, 4)) != 'RIFF' ||
          String.fromCharCodes(header.sublist(8, 12)) != 'WAVE') {
        throw const FormatException('Expected a PCM WAV recording.');
      }
      var validFormat = false;
      while (await file.position() + 8 <= await file.length()) {
        final chunk = await file.read(8),
            size = ByteData.sublistView(chunk).getUint32(4, Endian.little);
        final id = String.fromCharCodes(chunk.sublist(0, 4)),
            position = await file.position();
        if (position + size > await file.length()) {
          throw const FormatException('Incomplete WAV recording.');
        }
        if (id == 'fmt ') {
          if (size < 16) throw const FormatException('Invalid WAV format.');
          final format = ByteData.sublistView(await file.read(16));
          validFormat = format.getUint16(0, Endian.little) == 1 &&
              format.getUint16(2, Endian.little) == 1 &&
              format.getUint32(4, Endian.little) == 16000 &&
              format.getUint16(14, Endian.little) == 16;
        }
        if (id == 'data') {
          if (!validFormat) {
            throw const FormatException('Use mono, 16 kHz, 16-bit PCM WAV.');
          }
          return PcmWave._(path, position, size);
        }
        await file.setPosition(position + size + (size % 2));
      }
      throw const FormatException('WAV recording has no audio.');
    } finally {
      await file.close();
    }
  }

  Future<bool> writeClip(File target, double start, double end) async {
    final first = (start * 16000).floor().clamp(0, dataBytes ~/ 2);
    final last = (end * 16000).ceil().clamp(first, dataBytes ~/ 2);
    final source = await File(path).open();
    Uint8List bytes;
    try {
      await source.setPosition(dataOffset + first * 2);
      bytes = await source.read((last - first) * 2);
    } finally {
      await source.close();
    }
    var energy = 0.0;
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final sample = data.getInt16(i, Endian.little) / 32768;
      energy += sample * sample;
    }
    if (bytes.isEmpty || energy / (bytes.length / 2) < 0.000003) return false;
    final sink = target.openWrite();
    sink.add(WavHeaderHelper.buildHeader(bytes.length));
    sink.add(bytes);
    await sink.close();
    return true;
  }
}
