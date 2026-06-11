import 'dart:typed_data';

/// Helper to generate a 44-byte WAV header in memory.
/// Used to wrap raw 16kHz mono 16-bit signed PCM data so it can be parsed by Whisper.cpp.
class WavHeaderHelper {
  static Uint8List buildHeader(int pcmLengthBytes) {
    final header = ByteData(44);

    // 0-3: "RIFF" marker
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F

    // 4-7: Size of the file minus 8 bytes (chunk size)
    header.setUint32(4, 36 + pcmLengthBytes, Endian.little);

    // 8-11: "WAVE" format
    header.setUint8(8, 0x57);  // W
    header.setUint8(9, 0x41);  // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E

    // 12-15: "fmt " subchunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6d); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // space

    // 16-19: Length of fmt subchunk = 16
    header.setUint32(16, 16, Endian.little);

    // 20-21: Audio format = 1 (PCM)
    header.setUint16(20, 1, Endian.little);

    // 22-23: Number of channels = 1 (Mono)
    header.setUint16(22, 1, Endian.little);

    // 24-27: Sample rate = 16000 Hz
    header.setUint32(24, 16000, Endian.little);

    // 28-31: Byte rate = sampleRate * channels * bytesPerSample (16000 * 1 * 2) = 32000 B/s
    header.setUint32(28, 32000, Endian.little);

    // 32-33: Block align = channels * bytesPerSample = 2
    header.setUint16(32, 2, Endian.little);

    // 34-35: Bits per sample = 16
    header.setUint16(34, 16, Endian.little);

    // 36-39: "data" marker
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a

    // 40-43: Size of data subchunk in bytes
    header.setUint32(40, pcmLengthBytes, Endian.little);

    return header.buffer.asUint8List();
  }
}
