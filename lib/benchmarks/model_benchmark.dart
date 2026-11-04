import 'dart:convert';
import 'dart:io';
import '../storage/project_storage.dart';
import '../transcription/transcription_service.dart';

class ModelBenchmark {
  final TranscriptionService transcription;
  ModelBenchmark(this.transcription);
  Future<Map<String, dynamic>> run(String samplePath) async {
    final input = File(samplePath);
    final length = await input.length();
    if (length < 44 || length > 8 * 1024 * 1024) {
      throw const FormatException('Choose a short PCM WAV file, up to 8 MB.');
    }
    final reader = await input.open();
    late List<int> bytes;
    try {
      bytes = await reader.read(12);
    } finally {
      await reader.close();
    }
    if (bytes.length < 12 ||
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'RIFF' ||
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) != 'WAVE') {
      throw const FormatException('Choose a short PCM WAV file, up to 8 MB.');
    }
    final timer = Stopwatch()..start();
    final error = await transcription.ensureLoaded();
    if (error != null) throw StateError(error);
    final loadMs = timer.elapsedMilliseconds;
    final directory = await ProjectStorage.instance.directory('benchmarks');
    final copy = File(
        '${directory.path}/input-${DateTime.now().microsecondsSinceEpoch}.wav');
    await input.copy(copy.path);
    timer.reset();
    try {
      final text = await transcription.transcribe(copy.path);
      final result = <String, dynamic>{
        'model': transcription.modelLabel,
        'engine': transcription.activeEngine.name,
        'time': DateTime.now().toUtc().toIso8601String(),
        'loadMs': loadMs,
        'decodeMs': timer.elapsedMilliseconds,
        'sampleBytes': length,
        'transcript': text,
        'processRssBytes': ProcessInfo.currentRss,
        'processPeakRssBytes': ProcessInfo.maxRss,
        'memoryScope':
            'Flutter process only; subprocess model memory is excluded',
      };
      final target = File('${directory.path}/results.jsonl');
      await target.writeAsString('${jsonEncode(result)}\n',
          mode: FileMode.append, flush: true);
      return result;
    } finally {
      if (await copy.exists()) await copy.delete();
    }
  }

  Future<List<Map<String, dynamic>>> read() async {
    final dir = await ProjectStorage.instance.directory('benchmarks');
    final file = File('${dir.path}/results.jsonl');
    if (!await file.exists()) return [];
    final reader = await file.open();
    late String tail;
    try {
      final length = await reader.length();
      final start = (length - 512 * 1024).clamp(0, length);
      await reader.setPosition(start);
      tail =
          utf8.decode(await reader.read(length - start), allowMalformed: true);
      if (start > 0) {
        final newline = tail.indexOf('\n');
        tail = newline < 0 ? '' : tail.substring(newline + 1);
      }
    } finally {
      await reader.close();
    }
    return const LineSplitter()
        .convert(tail)
        .where((line) => line.trim().isNotEmpty)
        .toList()
        .reversed
        .take(20)
        .map((line) => Map<String, dynamic>.from(jsonDecode(line) as Map))
        .toList();
  }
}
