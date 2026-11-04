import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_to_text/benchmarks/model_benchmark.dart';
import 'package:voice_to_text/settings/settings_service.dart';
import 'package:voice_to_text/storage/project_storage.dart';
import 'package:voice_to_text/transcription/transcription_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'benchmark rejects oversized input before loading and reads only recent records',
      () async {
    final directory =
        await Directory.current.createTemp('.benchmark-memory-test-');
    addTearDown(() => directory.delete(recursive: true));
    await File('${directory.path}/pubspec.yaml').writeAsString('name: fixture');
    ProjectStorage.instance = ProjectStorage(directory);
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.aurascribe/accessibility'),
            (_) async => '');
    final settings = SettingsService();
    await settings.init();
    final service = TranscriptionService(settings);
    addTearDown(service.dispose);
    final benchmark = ModelBenchmark(service);
    final huge = File('${directory.path}/huge.wav');
    final handle = await huge.open(mode: FileMode.write);
    await handle.truncate(9 * 1024 * 1024);
    await handle.close();
    await expectLater(benchmark.run(huge.path), throwsFormatException);
    final results = File(
        '${(await ProjectStorage.instance.directory('benchmarks')).path}/results.jsonl');
    await results.writeAsString(
        List.generate(10000, (i) => '{"index":$i,"padding":"${'x' * 100}"}')
            .join('\n'));
    final recent = await benchmark.read();
    expect(recent.length, 20);
    expect(recent.first['index'], 9999);
    expect(recent.last['index'], 9980);
  });
}
