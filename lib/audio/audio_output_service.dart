import 'package:flutter/services.dart';

/// Serializes the audio-output lease so a delayed stop cannot undo a new start.
class AudioOutputService {
  static const _channel = MethodChannel('com.aurascribe/accessibility');
  Future<void> _pending = Future.value();
  Future<void> begin(String mode, double level,
          {bool speakersOnly = false, bool pauseBrowser = false}) =>
      _enqueue(() async {
        await _channel.invokeMethod<void>('beginAudioOutput', {
          'mode': mode,
          'level': level,
          'speakersOnly': speakersOnly,
          'pauseBrowser': pauseBrowser
        });
      });
  Future<void> end() =>
      _enqueue(() => _channel.invokeMethod<void>('restoreAudioOutput'));
  Future<void> _enqueue(Future<void> Function() operation) {
    _pending = _pending.catchError((_) {}).then((_) => operation());
    return _pending;
  }
}
