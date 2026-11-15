import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_to_text/storage/project_storage.dart';
import 'package:voice_to_text/transcription/gguf_catalog.dart';

class _Offline extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => throw StateError(
      'Benchmark requires an already installed verified model; network disabled.');
}

void main() {
  test('installed Parakeet cold validation and unchanged session reuse',
      () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final model =
          ggufCatalog.firstWhere((m) => m.id == 'parakeet_unified_english');
      final storage = ProjectStorage(Directory.current);
      final file =
          File('${storage.models.path}/gguf/${model.id}/${model.filename}');
      expect(await file.exists(), true);
      Future<String> prepare() => storage.download(
          folder: 'gguf/${model.id}',
          name: model.filename,
          url: model.url,
          expectedSha256: model.sha256,
          expectedBytes: model.bytes);
      final clock = Stopwatch()..start();
      await prepare();
      final cold = clock.elapsedMicroseconds;
      clock.reset();
      await prepare();
      final warm = clock.elapsedMicroseconds;
      stdout.writeln(
          'Parakeet validation: cold=${cold / 1000} ms, unchanged reuse=${warm / 1000} ms, bytes=${await file.length()}');
      expect(warm, lessThan(cold));
    }, _Offline());
  });
}
