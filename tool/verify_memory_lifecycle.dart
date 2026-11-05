// Opt-in: uses installed Moonshine weights and a supplied WAV. Never downloads
// models or opens the microphone. Run with SHERPA_LIBRARY_DIR pointing to the
// release app's Contents/Frameworks and MEMORY_FIXTURE to an existing sample.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_to_text/memory/model_memory_policy.dart';
import 'package:voice_to_text/storage/project_storage.dart';
import 'package:voice_to_text/transcription/moonshine_transcription_backend.dart';

void main() {
  test(
      '20 installed Moonshine load/decode/idle-unload cycles retain fixture output',
      () async {
    final project = Directory.current;
    await ProjectStorage.initialize(projectPath: project.path);
    for (final name in [
      'preprocess.onnx',
      'encode.int8.onnx',
      'uncached_decode.int8.onnx',
      'cached_decode.int8.onnx',
      'tokens.txt',
      'LICENSE'
    ]) {
      expect(
          await File(
                  '${ProjectStorage.instance.models.path}/moonshine_tiny_int8/$name')
              .exists(),
          true,
          reason:
              'Install Moonshine manually first. This probe must not download weights.');
    }
    const path = String.fromEnvironment('MEMORY_FIXTURE');
    final fixture = File(path);
    expect(await fixture.exists(), true, reason: 'Supply MEMORY_FIXTURE');
    final directory =
        await ProjectStorage.instance.directory('benchmarks/memory');
    final records = <Map<String, Object>>[];
    String? reference;
    for (var cycle = 0; cycle < 20; cycle++) {
      const isolated = bool.fromEnvironment('MEMORY_PROCESS_WORKER');
      final backend = MoonshineTranscriptionBackend(releaseAfterClip: isolated);
      final policy = ModelMemoryPolicy(
          unload: backend.dispose, delay: const Duration(milliseconds: 50));
      try {
        final before = ProcessInfo.currentRss;
        final result = await policy.run(() async {
          final timer = Stopwatch()..start();
          expect(await backend.load(), isNull);
          final load = timer.elapsedMilliseconds;
          final loaded = ProcessInfo.currentRss;
          final copy = await fixture.copy('${directory.path}/cycle.wav');
          timer.reset();
          final text = await backend.transcribe(copy.path);
          reference ??= text;
          expect(text, reference);
          expect(text.toLowerCase(), contains('after early nightfall'));
          return <String, Object>{
            'cycle': cycle,
            'beforeRss': before,
            'loadedRss': loaded,
            'loadMs': load,
            'decodeMs': timer.elapsedMilliseconds
          };
        });
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(backend.isLoaded, false);
        result['idleRss'] = ProcessInfo.currentRss;
        records.add(result);
      } finally {
        policy.dispose();
        await backend.dispose();
      }
    }
    const isolated = bool.fromEnvironment('MEMORY_PROCESS_WORKER');
    final target = File(
        '${directory.path}/moonshine-${isolated ? 'process' : 'isolate'}-lifecycle.json');
    await target
        .writeAsString(const JsonEncoder.withIndent('  ').convert(records));
    // Metadata only: no recognized text or private audio is written to the report.
    // ignore: avoid_print
    print(
        '20 cycles passed. First=${records.first}; last=${records.last}; report=${target.path}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
