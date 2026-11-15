import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../storage/project_storage.dart';

class DictationEntry {
  final String text;
  final String model;
  final DateTime date;
  final String language;
  final String? audio;
  final List<String> versions;
  const DictationEntry(this.text, this.model, this.date,
      {this.language = 'unknown', this.audio, this.versions = const []});
  Map<String, dynamic> toJson() => {
        'text': text,
        'model': model,
        'date': date.toIso8601String(),
        'language': language,
        'audio': audio,
        'versions': versions
      };
}

/// Opt-in project-local history, with separately opted-in recordings.
class HistoryService extends ChangeNotifier {
  static final instance = HistoryService();
  List<DictationEntry> _entries = [];
  int retentionDays = 0;
  DateTime Function() now = DateTime.now;
  List<DictationEntry> get entries => List.unmodifiable(_entries);
  Future<void> _pending = Future.value();
  Future<File> get _file async => File(p.join(
      (await ProjectStorage.instance.directory('history')).path,
      'dictations.json'));
  Future<void> init() async {
    final file = await _file;
    if (!await file.exists()) return;
    try {
      final rows = jsonDecode(await file.readAsString()) as List;
      _entries = rows
          .map((e) => DictationEntry(e['text'] as String, e['model'] as String,
              DateTime.parse(e['date'] as String),
              language: e['language'] as String? ?? 'unknown',
              audio: e['audio'] as String?,
              versions: (e['versions'] as List? ?? [])
                  .cast<String>()
                  .take(5)
                  .toList()))
          .take(100)
          .toList();
      await prune();
      await _removeOrphanAudio();
    } catch (_) {
      _entries = [];
    }
  }

  Future<void> add(String text, String model,
      {String language = 'unknown', String? audio}) async {
    if (text.trim().isEmpty) return;
    _entries.insert(0,
        DictationEntry(text, model, now(), language: language, audio: audio));
    _entries = _entries.take(100).toList();
    await prune();
    await _save();
    await _removeOrphanAudio();
  }

  Future<void> prune() async {
    if (retentionDays <= 0) return;
    final cutoff = now().subtract(Duration(days: retentionDays));
    final count = _entries.length;
    _entries.removeWhere((entry) => entry.date.isBefore(cutoff));
    if (_entries.length != count) {
      await _save();
      await _removeOrphanAudio();
    }
  }

  Future<void> replace(DictationEntry entry, String text,
      {String? model, String? language}) async {
    final index = _entries.indexOf(entry);
    if (index < 0 ||
        text.trim().isEmpty ||
        (text == entry.text && model == null && language == null)) {
      return;
    }
    _entries[index] = DictationEntry(text, model ?? entry.model, entry.date,
        language: language ?? entry.language,
        audio: entry.audio,
        versions: List.unmodifiable([entry.text, ...entry.versions].take(5)));
    await _save();
  }

  Future<void> discardAudio(String? name) async {
    if (name == null || _entries.any((e) => e.audio == name)) return;
    final file = await audioFile(DictationEntry('', '', now(), audio: name));
    if (file != null) await file.delete();
  }

  Future<String?> retainAudio(String path) async {
    final directory = await ProjectStorage.instance.directory('history/audio');
    final name = '${DateTime.now().microsecondsSinceEpoch}.wav';
    await File(path).copy('${directory.path}/$name');
    return name;
  }

  Future<File?> audioFile(DictationEntry entry) async {
    final name = entry.audio;
    if (name == null || !RegExp(r'^\d+\.wav$').hasMatch(name)) return null;
    final directory = await ProjectStorage.instance.directory('history/audio');
    final file = File('${directory.path}/$name');
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    return file;
  }

  Future<void> _removeOrphanAudio() async {
    final directory = await ProjectStorage.instance.directory('history/audio');
    final kept = _entries.map((e) => e.audio).whereType<String>().toSet();
    await for (final file in directory.list(followLinks: false)) {
      if (file is File && !kept.contains(p.basename(file.path))) {
        await file.delete();
      }
    }
  }

  Future<void> remove(DictationEntry entry) async {
    _entries.remove(entry);
    await _save();
    await _removeOrphanAudio();
  }

  Future<void> clear() async {
    _entries.clear();
    await _save();
    await _removeOrphanAudio();
  }

  Future<void> _save() {
    final snapshot = jsonEncode(_entries.map((e) => e.toJson()).toList());
    _pending = _pending.catchError((_) {}).then((_) async {
      final file = await _file;
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(snapshot, flush: true);
      await temp.rename(file.path);
    });
    notifyListeners();
    return _pending;
  }
}
