import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_to_text/history/history_service.dart';
import 'package:voice_to_text/storage/project_storage.dart';
import 'package:voice_to_text/transcription/gguf_catalog.dart';

void main() {
  late Directory project;
  setUp(() async {
    project = await Directory.systemTemp.createTemp('aura-history-');
    await File('${project.path}/pubspec.yaml').writeAsString('name: fixture');
    ProjectStorage.instance = ProjectStorage(project);
  });
  tearDown(() => project.delete(recursive: true));

  test('migrates legacy history and persists bounded replacement versions',
      () async {
    final dir = await ProjectStorage.instance.directory('history');
    await File('${dir.path}/dictations.json').writeAsString(jsonEncode([
      {'text': 'old', 'model': 'Whisper', 'date': '2026-11-12T00:00:00Z'}
    ]));
    final history = HistoryService();
    await history.init();
    expect(history.entries.single.language, 'unknown');
    for (var i = 0; i < 8; i++) {
      await history.replace(history.entries.single, 'revision $i');
    }
    expect(history.entries.single.versions.length, 5);
    final restored = HistoryService();
    await restored.init();
    expect(restored.entries.single.text, 'revision 7');
    expect(restored.entries.single.versions.first, 'revision 6');
    await restored.replace(restored.entries.single, '  ');
    expect(restored.entries.single.text, 'revision 7');
  });

  test('retention removes expired entries on restart and preserves language',
      () async {
    final history = HistoryService();
    history.now = () => DateTime.utc(2026, 11, 1);
    await history.add('expired', 'Whisper', language: 'fr');
    history.now = () => DateTime.utc(2026, 11, 12);
    await history.add('current', 'Orukeet', language: 'auto');
    final restored = HistoryService()..retentionDays = 7;
    restored.now = history.now;
    await restored.init();
    expect(restored.entries.map((e) => e.text), ['current']);
    expect(restored.entries.single.language, 'auto');
    await restored.clear();
    final empty = HistoryService();
    await empty.init();
    expect(empty.entries, isEmpty);
  });

  test('retained recordings belong to history and are deleted with their entry',
      () async {
    final source = File('${project.path}/clip.wav');
    await source.writeAsBytes([1, 2, 3, 4]);
    final history = HistoryService();
    final name = await history.retainAudio(source.path);
    await history.add('hello', 'fixture', language: 'en', audio: name);
    final entry = history.entries.single;
    expect(await (await history.audioFile(entry))!.readAsBytes(), [1, 2, 3, 4]);
    await history.replace(entry, 'bonjour', model: 'other', language: 'fr');
    expect(history.entries.single.model, 'other');
    expect(history.entries.single.language, 'fr');
    expect(history.entries.single.audio, name);
    await history.remove(history.entries.single);
    expect(await history.audioFile(entry), isNull);
    expect(await source.exists(), isTrue);
  });

  test('Hex 3.4 catalog has all 17 artifacts plus existing Moonshine', () {
    expect(ggufCatalog.length, 18);
    expect(ggufCatalog.map((m) => m.id).toSet().length, 18);
    for (final model in ggufCatalog) {
      expect(model.sha256, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(model.revision, matches(RegExp(r'^[a-f0-9]{40}$')));
      expect(model.bytes, greaterThan(0));
    }
    expect(
        ggufCatalog.singleWhere((m) => m.id == 'granite_speech_5').architecture,
        'granite_speech5_ctc');
  });
}
