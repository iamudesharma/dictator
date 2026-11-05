import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../storage/project_storage.dart';

class DictationEntry {
  final String text;
  final String model;
  final DateTime date;
  const DictationEntry(this.text, this.model, this.date);
  Map<String, String> toJson() =>
      {'text': text, 'model': model, 'date': date.toIso8601String()};
}

/// Opt-in text history; audio recordings are never kept in history.
class HistoryService extends ChangeNotifier {
  static final instance = HistoryService();
  List<DictationEntry> _entries = [];
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
              DateTime.parse(e['date'] as String)))
          .take(100)
          .toList();
    } catch (_) {
      _entries = [];
    }
  }

  Future<void> add(String text, String model) async {
    if (text.trim().isEmpty) return;
    _entries.insert(0, DictationEntry(text, model, DateTime.now()));
    _entries = _entries.take(100).toList();
    await _save();
  }

  Future<void> remove(DictationEntry entry) async {
    _entries.remove(entry);
    await _save();
  }

  Future<void> clear() async {
    _entries.clear();
    await _save();
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
