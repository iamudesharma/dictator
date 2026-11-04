import 'package:flutter/foundation.dart';

/// Deliberately records lifecycle metadata only: no transcripts or credentials.
class ActivityLog extends ChangeNotifier {
  static final instance = ActivityLog();
  final List<Map<String, String>> _events = [];
  List<Map<String, String>> get events => List.unmodifiable(_events);
  void add(String event, {String? model, String? state}) {
    _events.insert(0, {
      'time': DateTime.now().toUtc().toIso8601String(),
      'event': event,
      if (model != null) 'model': model,
      if (state != null) 'state': state
    });
    if (_events.length > 200) _events.removeLast();
    notifyListeners();
  }
}
