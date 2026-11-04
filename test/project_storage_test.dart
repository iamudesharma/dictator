import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_to_text/storage/project_storage.dart';

void main() {
  test(
      'keeps weights and partial downloads inside project; rejects unsafe paths',
      () async {
    final project = await Directory.current.createTemp('.storage-test-');
    addTearDown(() => project.delete(recursive: true));
    await File('${project.path}/pubspec.yaml').writeAsString('name: fixture');
    final storage = ProjectStorage(project);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.contentLength = 6;
      request.response.add([1, 2, 3, 4, 5, 6]);
      await request.response.close();
    });
    final url = Uri.parse('http://127.0.0.1:${server.port}/model');
    final path =
        await storage.download(folder: 'tiny', name: 'model.bin', url: url);
    expect(path, startsWith('${project.path}/.aurascribe/models/'));
    expect(await File(path).length(), 6);
    expect(await File('$path.part').exists(), isFalse);
    await storage.download(folder: 'tiny', name: 'model.bin', url: url);
    expect(requests, 1, reason: 'verified receipt allows offline reuse');
    await File(path).writeAsBytes([1]);
    await storage.download(folder: 'tiny', name: 'model.bin', url: url);
    expect(requests, 2, reason: 'truncated cache must be replaced');
    await expectLater(storage.directory('../escape'), throwsArgumentError);
    await Link('${project.path}/.aurascribe/models/external')
        .create(project.parent.path);
    await expectLater(storage.directory('models/external'), throwsStateError);
  });

  test('cancelled model downloads close the transfer and remove partial files',
      () async {
    final project = await Directory.current.createTemp('.cancel-test-');
    addTearDown(() => project.delete(recursive: true));
    await File('${project.path}/pubspec.yaml').writeAsString('name: fixture');
    final storage = ProjectStorage(project),
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      try {
        request.response.contentLength = 1000000;
        request.response.add(List.filled(1024, 1));
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await request.response.close();
      } catch (_) {}
    });
    await expectLater(
        storage.download(
            folder: 'fixture',
            name: 'cancel.bin',
            url: Uri.parse('http://127.0.0.1:${server.port}/model'),
            onProgress: (_) => storage.cancelDownloads()),
        throwsA(anything));
    expect(storage.hasActiveDownloads, isFalse);
    expect(
        await File('${project.path}/.aurascribe/models/fixture/cancel.bin.part')
            .exists(),
        isFalse);
    expect(
        await File('${project.path}/.aurascribe/models/fixture/cancel.bin')
            .exists(),
        isFalse);
  });
}
