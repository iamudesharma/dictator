/// Serialize live deltas, committing progress only after native insertion succeeds.
class LiveTextInserter {
  final Future<bool> Function(String) insert;
  LiveTextInserter(this.insert);
  String _inserted = '', _scheduled = '';
  String get inserted => _inserted;
  Object? _error;
  Future<void> _pending = Future.value();

  void enqueue(String text, {String? finalizedFallback}) {
    if (_error != null) return;
    var candidate = text.trim();
    if (!candidate.startsWith(_scheduled)) {
      candidate = finalizedFallback?.trim() ?? '';
    }
    if (candidate.isEmpty || !candidate.startsWith(_scheduled)) return;
    final delta = candidate.substring(_scheduled.length);
    if (delta.isEmpty) return;
    _scheduled = candidate;
    final committed = candidate;
    _pending = _pending.then((_) async {
      if (_error != null) return;
      try {
        await insert(delta);
        _inserted = committed;
      } catch (e) {
        _error = e;
        _scheduled = _inserted;
      }
    });
  }

  Future<void> finish() async {
    await _pending;
    if (_error != null) throw _error!;
  }
}
