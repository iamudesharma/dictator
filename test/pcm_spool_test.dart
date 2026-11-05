import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_to_text/audio/pcm_spool.dart';
import 'package:voice_to_text/audio/pcm_wave.dart';

void main() {
  test('snapshots contain stable complete prefixes while capture continues',
      () async {
    final directory = await Directory.systemTemp.createTemp('spool-test');
    addTearDown(() => directory.delete(recursive: true));
    final spool = await PcmSpool.create(directory, 1);
    addTearDown(spool.dispose);
    spool.append(Uint8List.fromList([1, 2, 3]));
    final snapshot = spool.snapshot(File('${directory.path}/prefix.wav'));
    spool.append(Uint8List.fromList([4, 5, 6]));
    final prefix = await snapshot;
    expect((await prefix.readAsBytes()).sublist(44), [1, 2]);
    expect((await PcmWave.open(prefix.path)).dataBytes, 2);
    final finalFile = await spool.snapshot(File('${directory.path}/final.wav'));
    expect((await finalFile.readAsBytes()).sublist(44), [1, 2, 3, 4, 5, 6]);
    await spool.dispose();
    expect(await spool.file.exists(), isFalse);
    expect(() => spool.append(Uint8List(2)), throwsStateError);
  });

  test('recording is bounded and snapshots copy more than one block exactly',
      () async {
    final directory = await Directory.systemTemp.createTemp('spool-test');
    addTearDown(() => directory.delete(recursive: true));
    final spool = await PcmSpool.create(directory, 3);
    addTearDown(spool.dispose);
    final input = Uint8List.fromList(List.generate(100000, (i) => i % 251));
    expect(spool.append(input), isTrue);
    expect(spool.bytes, 96000);
    final output = await spool.snapshot(File('${directory.path}/snapshot.wav'));
    expect((await output.readAsBytes()).sublist(44), input.sublist(0, 96000));
    expect(spool.append(Uint8List(2000)), isTrue);
    expect(spool.bytes, 96000);
  });
}
