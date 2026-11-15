import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_to_text/audio/pcm_wave.dart';
import 'package:voice_to_text/audio/pause_compactor.dart';
import 'package:voice_to_text/shared/wav_header_helper.dart';

import 'support/wav_fixtures.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('aura-wav-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  test(
    'Apple microphone extensible PCM supports slicing and pause compaction',
    () async {
      final pcm = Uint8List(6400), data = ByteData.sublistView(pcm);
      for (var i = 0; i < 3200; i++) {
        data.setInt16(i * 2, i.isEven ? 1500 : -1500, Endian.little);
      }
      final file = await File('${dir.path}/apple.wav')
          .writeAsBytes(appleWave(pcm));
      final wave = await PcmWave.open(file.path);
      expect(wave.seconds, 0.2);
      expect(wave.dataBytes, pcm.length);
      expect(wave.dataOffset, greaterThan(44));
      final clip = File('${dir.path}/clip.wav');
      expect(await wave.writeClip(clip, 0.1, 0.2), true);
      final clipped = await PcmWave.open(clip.path);
      expect(clipped.seconds, 0.1);
      expect(
        (await clip.readAsBytes()).sublist(clipped.dataOffset),
        pcm.sublist(3200),
      );
      final compacted = File('${dir.path}/compact.wav');
      await compactPauses(file.path, compacted);
      final compact = await PcmWave.open(compacted.path);
      expect((await compacted.readAsBytes()).sublist(compact.dataOffset), pcm);
    },
  );
  test('classic PCM16 WAV remains supported', () async {
    final file = await File('${dir.path}/classic.wav')
        .writeAsBytes([...WavHeaderHelper.buildHeader(320), ...Uint8List(320)]);
    expect((await PcmWave.open(file.path)).seconds, 0.01);
  });
  test(
    'rejects float/custom subtypes, invalid valid bits and extension sizes',
    () async {
      for (final entry in <(int, int)>[
        (24, 3),
        (28, 1),
        (18, 24),
        (16, 0),
        (16, 24),
        (2, 2),
        (4, 0),
        (12, 4),
        (14, 32),
      ]) {
        final fmt = List<int>.from(appleFmt)..[entry.$1] = entry.$2;
        final file = await File('${dir.path}/bad.wav')
            .writeAsBytes(appleWave(Uint8List(320), fmt));
        await expectLater(PcmWave.open(file.path), throwsFormatException);
      }
      final file = await File('${dir.path}/short.wav')
          .writeAsBytes(appleWave(Uint8List(320), appleFmt.sublist(0, 38)));
      await expectLater(PcmWave.open(file.path), throwsFormatException);
    },
  );
}
