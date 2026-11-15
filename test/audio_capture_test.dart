import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_to_text/audio/audio_service.dart';
import 'package:voice_to_text/audio/pcm_wave.dart';
import 'package:voice_to_text/settings/settings_service.dart';
import 'package:voice_to_text/storage/project_storage.dart';

class PcmRecorder extends RecordPlatform {
  StreamController<Uint8List>? chunks;
  RecordConfig? config;
  bool failStart = false;
  @override
  Future<void> create(String id) async {}
  @override
  Stream<RecordState> onStateChanged(String id) => const Stream.empty();
  @override
  Future<Stream<Uint8List>> startStream(String id, RecordConfig config) async {
    if (failStart) throw StateError('Disconnected microphone');
    this.config = config;
    chunks = StreamController<Uint8List>();
    return chunks!.stream;
  }

  @override
  Future<String?> stop(String id) async {
    // Final samples delivered while stopping must be included in the WAV.
    chunks?.add(Uint8List.fromList([7, 8, 9]));
    await Future<void>.delayed(Duration.zero);
    return null;
  }

  @override
  Future<void> cancel(String id) async {}
  @override
  Future<void> dispose(String id) async {
    await chunks?.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory project;
  late PcmRecorder recorder;
  late AudioService audio;
  late RecordPlatform previous;
  setUp(() async {
    project = await Directory.systemTemp.createTemp('audio-capture');
    await File('${project.path}/pubspec.yaml').writeAsString('name: fixture');
    ProjectStorage.instance = ProjectStorage(project);
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.aurascribe/accessibility'),
          (call) async => call.method == 'readHfToken' ? '' : null,
        );
    final settings = SettingsService();
    await settings.init();
    previous = RecordPlatform.instance;
    recorder = PcmRecorder();
    RecordPlatform.instance = recorder;
    audio = AudioService(settings);
  });
  tearDown(() async {
    await audio.cancel();
    audio.dispose();
    await Future<void>.delayed(Duration.zero);
    RecordPlatform.instance = previous;
    await project.delete(recursive: true);
  });
  test('batch capture writes canonical WAV with final samples and no partial frame', () async {
    await audio.start();
    expect(recorder.config!.encoder, AudioEncoder.pcm16bits);
    expect(recorder.config!.sampleRate, 16000);
    expect(recorder.config!.numChannels, 1);
    recorder.chunks!.add(Uint8List.fromList([1, 2, 3]));
    recorder.chunks!.add(Uint8List.fromList([4, 5, 6]));
    final path = (await audio.stop())!;
    final bytes = await File(path).readAsBytes();
    expect(bytes.sublist(44), [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(ByteData.sublistView(bytes).getUint16(20, Endian.little), 1);
    expect((await PcmWave.open(path)).dataBytes, 8);
    expect(audio.isRecording, isFalse);
  });
  test('cancel discards capture and allows a fresh recording', () async {
    await audio.start();
    recorder.chunks!.add(Uint8List(200));
    await audio.cancel();
    final dir = await ProjectStorage.instance.directory('tmp/pcm');
    expect(await dir.list().toList(), isEmpty);
    await audio.start();
    expect(await audio.stop(), isNotNull);
  });
  test(
    'failed microphone startup removes partial WAV and recording state',
    () async {
      recorder.failStart = true;
      await expectLater(audio.start(), throwsStateError);
      expect(audio.isRecording, isFalse);
      final dir = await ProjectStorage.instance.directory('tmp/pcm');
      expect(await dir.list().toList(), isEmpty);
    },
  );
}
