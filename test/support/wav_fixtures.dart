import 'dart:typed_data';

// Exact fmt chunk captured from the installed app's AVCaptureAudioFileOutput.
const appleFmt = [
  0xfe,
  0xff,
  1,
  0,
  0x80,
  0x3e,
  0,
  0,
  0,
  0x7d,
  0,
  0,
  2,
  0,
  16,
  0,
  22,
  0,
  16,
  0,
  4,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  0,
  0,
  16,
  0,
  0x80,
  0,
  0,
  0xaa,
  0,
  0x38,
  0x9b,
  0x71,
];

List<int> chunk(String name, List<int> payload) {
  final size = ByteData(4)..setUint32(0, payload.length, Endian.little);
  return [
    ...name.codeUnits,
    ...size.buffer.asUint8List(),
    ...payload,
    if (payload.length.isOdd) 0,
  ];
}

Uint8List appleWave(List<int> pcm, [List<int> format = appleFmt]) {
  final body = [
    ...'WAVE'.codeUnits,
    ...chunk('JUNK', [1, 2, 3]),
    ...chunk('fmt ', format),
    ...chunk('FLLR', List.filled(30, 0)),
    ...chunk('data', pcm),
  ];
  final size = ByteData(4)..setUint32(0, body.length, Endian.little);
  return Uint8List.fromList([
    ...'RIFF'.codeUnits,
    ...size.buffer.asUint8List(),
    ...body,
  ]);
}
