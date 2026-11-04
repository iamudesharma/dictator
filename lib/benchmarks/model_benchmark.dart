import 'dart:convert';
import 'dart:io';
import '../storage/project_storage.dart';
import '../transcription/transcription_service.dart';

class ModelBenchmark {
  final TranscriptionService transcription;
  ModelBenchmark(this.transcription);
  Future<Map<String, dynamic>> run(String samplePath) async {
    final input = File(samplePath);
    final bytes = await input.readAsBytes();
    if (bytes.length < 44 ||
        bytes.length > 8 * 1024 * 1024 ||
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
    await copy.writeAsBytes(bytes);
    timer.reset();
    try {
      final text = await transcription.transcribe(copy.path);
      final result = <String, dynamic>{
        'model': transcription.modelLabel,
        'engine': transcription.activeEngine.name,
        'time': DateTime.now().toUtc().toIso8601String(),
        'loadMs': loadMs,
        'decodeMs': timer.elapsedMilliseconds,
        'sampleBytes': bytes.length,
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
    return (await file.readAsLines())
        .where((l) => l.trim().isNotEmpty)
        .map((l) => Map<String, dynamic>.from(jsonDecode(l) as Map))
        .toList()
        .reversed
        .take(20)
        .toList();
  }
}
