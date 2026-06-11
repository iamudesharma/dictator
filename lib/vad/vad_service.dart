import 'dart:async';
import 'package:flutter/foundation.dart';
import '../audio/audio_service.dart';
import '../settings/settings_service.dart';

typedef SilenceDetectedCallback = void Function();

/// Voice Activity Detection using amplitude polling.
/// Polls every [pollInterval] and fires [onSilenceDetected] when
/// the amplitude stays below [settings.vadThreshold] dBFS
/// for [settings.vadSilenceDuration] milliseconds.
class VadService {
  final AudioService _audio;
  final SettingsService _settings;

  SilenceDetectedCallback? onSilenceDetected;

  Timer? _pollTimer;
  int _silentMs = 0;
  int _recordingMs = 0;
  static const _pollInterval = Duration(milliseconds: 150);

  bool _hasSpeech = false;

  VadService(this._audio, this._settings);

  void start() {
    _silentMs = 0;
    _recordingMs = 0;
    _hasSpeech = false;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, _tick);
    debugPrint(
      '[AuraScribe][VAD] started (threshold=${_settings.vadThreshold} dBFS, '
      'silence=${_settings.vadSilenceDuration}ms, '
      'max=${_settings.maxRecordingSeconds}s)',
    );
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _silentMs = 0;
    _recordingMs = 0;
    _hasSpeech = false;
    debugPrint('[AuraScribe][VAD] stopped');
  }

  Future<void> _tick(Timer _) async {
    try {
      _recordingMs += _pollInterval.inMilliseconds;
      final maxMs = _settings.maxRecordingSeconds * 1000;
      if (_recordingMs >= maxMs) {
        debugPrint(
          '[AuraScribe][VAD] max recording ${_settings.maxRecordingSeconds}s reached → stopping',
        );
        stop();
        onSilenceDetected?.call();
        return;
      }

      final amp = await _audio.getAmplitude();
      final current = amp.current; // dBFS, negative

      final isSilent = current < _settings.vadThreshold;

      if (!isSilent) {
        if (!_hasSpeech) {
          debugPrint('[AuraScribe][VAD] speech detected (${current.toStringAsFixed(1)} dBFS)');
        }
        _hasSpeech = true;
        _silentMs = 0;
      } else if (_hasSpeech) {
        _silentMs += _pollInterval.inMilliseconds;
        if (_silentMs >= _settings.vadSilenceDuration) {
          debugPrint(
            '[AuraScribe][VAD] silence ${_silentMs}ms after speech → triggering stop',
          );
          stop();
          onSilenceDetected?.call();
        }
      }
    } catch (_) {
      // Ignore amplitude read errors during stop
    }
  }

  void dispose() {
    _pollTimer?.cancel();
  }
}
