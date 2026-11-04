import 'dart:async';

/// Idle unloading shares one activity fence across model loads, sessions and
/// long-lived recording/meeting tasks. Arrivals wait for an unloading model.
class ModelMemoryPolicy {
  ModelMemoryPolicy({
    required Future<void> Function() unload,
    this.enabled = true,
    this.delay = const Duration(seconds: 60),
    this.onError,
  }) : _unload = unload;

  final Future<void> Function() _unload;
  final void Function(Object, StackTrace)? onError;
  bool enabled;
  Duration delay;
  final Set<Object> _activities = {};
  Timer? _timer;
  Future<void>? _unloading;
  bool _disposed = false, _trimPending = false;
  int get activeCount => _activities.length;
  bool get isUnloading => _unloading != null;

  void configure({required bool enabled, required Duration delay}) {
    this.enabled = enabled;
    this.delay = delay;
    _timer?.cancel();
    _schedule();
  }

  void setActive(Object owner, bool active) {
    if (_disposed) return;
    if (active) {
      _activities.add(owner);
      _timer?.cancel();
      _timer = null;
    } else if (_activities.remove(owner)) {
      if (_trimPending && _activities.isEmpty) {
        unawaited(releaseIfIdle());
      } else {
        _schedule();
      }
    }
  }

  Future<T> run<T>(Future<T> Function() operation) async {
    final lease = Object();
    setActive(lease, true);
    try {
      await _unloading;
      return await operation();
    } finally {
      setActive(lease, false);
    }
  }

  void _schedule() {
    if (_disposed || !enabled || _activities.isNotEmpty || _unloading != null) {
      return;
    }
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(releaseIfIdle()));
  }

  /// OS memory pressure may reclaim idle models even in keep-warm mode. A busy
  /// operation is never interrupted; cleanup runs after its last lease ends.
  Future<void> releaseIfIdle() {
    _timer?.cancel();
    _timer = null;
    if (_disposed) return Future.value();
    if (_activities.isNotEmpty) {
      _trimPending = true;
      return Future.value();
    }
    _trimPending = false;
    return _unloading ??=
        Future<void>.sync(_unload).catchError((Object e, StackTrace s) {
      onError?.call(e, s);
    }).whenComplete(() {
      _unloading = null;
      // Arm again after activity, not repeatedly for an already-empty engine.
    });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _activities.clear();
  }
}
