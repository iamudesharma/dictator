import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_to_text/audio/pcm_wave.dart';
import 'package:voice_to_text/shared/wav_header_helper.dart';
import 'package:voice_to_text/storage/project_storage.dart';
import 'package:voice_to_text/transcription/custom_model_store.dart';
import 'package:voice_to_text/updates/update_service.dart';

void main() {
  test('update selection rejects downgrades, prereleases and foreign assets',
      () {
    Map<String, dynamic> release(String tag, String url) => {
          'tag_name': tag,
          'assets': [
            {
              'name': 'AuraScribe.dmg',
              'browser_download_url': url,
              'size': 123,
              'digest': 'sha256:${'a' * 64}'
            }
          ]
        };
    const good =
        'https://github.com/iamudesharma/dictator/releases/download/v1.2.0/AuraScribe.dmg';
    expect(
        AppRelease.parse(release('v1.2.0', good), '1.1.9')?.version, 'v1.2.0');
    expect(AppRelease.parse(release('v1.0.0', good), '1.1.9'), isNull);
    expect(
        AppRelease.parse(
            {...release('v2.0.0', good), 'prerelease': true}, '1.0.0'),
        isNull);
    expect(
        () => AppRelease.parse(
            release('v2.0.0', 'https://example.org/app.dmg'), '1.0.0'),
        throwsFormatException);
  });
  test('WAV clips retain PCM format and do not transcribe silent spans',
      () async {
    final dir = await Directory.current.createTemp('.wav-test-');
    addTearDown(() => dir.delete(recursive: true));
    final samples = Uint8List(32000), view = ByteData.sublistView(samples);
    for (var i = 0; i < samples.length; i += 2) {
      view.setInt16(i, i % 4 == 0 ? 1000 : -1000, Endian.little);
    }
    final file = File('${dir.path}/input.wav');
    await file.writeAsBytes(
        [...WavHeaderHelper.buildHeader(samples.length), ...samples]);
    final source = await PcmWave.open(file.path);
    expect(source.seconds, 1);
    final clip = File('${dir.path}/clip.wav');
    expect(await source.writeClip(clip, 0.2, 0.7), isTrue);
    expect((await PcmWave.open(clip.path)).seconds, closeTo(0.5, 0.001));
    await file.writeAsBytes(
        [...WavHeaderHelper.buildHeader(32000), ...Uint8List(32000)]);
    expect(await source.writeClip(clip, 0, 1), isFalse);
  });
  test(
      'custom model import stays in project storage and rejects wrong architectures',
      () async {
    final dir = await Directory.current.createTemp('.model-test-');
    addTearDown(() => dir.delete(recursive: true));
    await File('${dir.path}/pubspec.yaml').writeAsString('name: fixture');
    ProjectStorage.instance = ProjectStorage(dir);
    Uint8List gguf(String architecture) {
      final out = BytesBuilder();
      void intValue(int value, int bytes) {
        final buffer = ByteData(bytes);
        if (bytes == 4) {
          buffer.setUint32(0, value, Endian.little);
        } else {
          buffer.setUint64(0, value, Endian.little);
        }
        out.add(buffer.buffer.asUint8List());
      }

      void string(String text) {
        final bytes = utf8.encode(text);
        intValue(bytes.length, 8);
        out.add(bytes);
      }

      intValue(0x46554747, 4);
      intValue(3, 4);
      intValue(0, 8);
      intValue(2, 8);
      string('general.architecture');
      intValue(8, 4);
      string(architecture);
      string('general.name');
      intValue(8, 4);
      string('Fixture speech model');
      return out.toBytes();
    }

    final input = File('${dir.path}/source.gguf');
    await input.writeAsBytes(gguf('whisper'));
    final store = CustomModelStore(),
        model = await CustomModelStore().importFile(input.path);
    final path = await store.path(model);
    expect(path, contains('/.aurascribe/models/imports/'));
    expect(await File(path).exists(), isTrue);
    await input.writeAsBytes(gguf('llama'));
    await expectLater(store.importFile(input.path), throwsFormatException);
    await File(path).delete();
    await Link(path).create(input.path);
    await expectLater(store.path(model), throwsA(isA<FileSystemException>()));
  });
}
