import 'package:flutter/foundation.dart';

import 'dart:async';

import '../storage/project_storage.dart';
import 'pcm_spool.dart';

import 'package:record/record.dart';

import '../settings/settings_service.dart';

class AudioService {
  final SettingsService settings;
  String? microphoneOverride;
  AudioService(this.settings);
  Future<InputDevice?> _device() async {
    final selected = microphoneOverride ?? settings.microphoneId;
    if (selected.isEmpty) return null;
    final devices = await _recorder.listInputDevices();
    return devices.firstWhere(
      (d) => d.id == selected,
      orElse: () => throw StateError(
        'Selected microphone is disconnected. Choose another microphone in Settings.',
      ),
    );
  }

  final AudioRecorder _recorder = AudioRecorder();
  String? _currentPath;
  PcmSpool? _fileSpool;
  StreamSubscription<Uint8List>? _fileSubscription;
  Object? _fileError;
  StackTrace? _fileErrorStack;

  /// Returns the current amplitude in dBFS. Used by VAD.
  Future<Amplitude> getAmplitude() => _recorder.getAmplitude();

  bool get isRecording => _currentPath != null;

  Future<void> start() async {
    if (isRecording) throw StateError('Microphone is already recording');
    final spool = await PcmSpool.create(
      await ProjectStorage.instance.directory('tmp/pcm'),
      settings.maxRecordingSeconds,
    );
    _fileSpool = spool;
    _fileError = null;
    _fileErrorStack = null;
    try {
      // Use the same converted PCM stream as the streaming backends. Writing
      // our own WAV avoids platform-dependent file codecs and header layouts.
      final stream = await startStream();
      _currentPath = spool.file.path;
      _fileSubscription = stream.listen(
        (chunk) {
          if (_fileError != null) return;
          try {
            spool.append(chunk);
          } catch (error, stack) {
            _fileError = error;
            _fileErrorStack = stack;
          }
        },
        onError: (Object error, StackTrace stack) {
          _fileError = error;
          _fileErrorStack = stack;
        },
      );
    } catch (_) {
      await cancel();
      rethrow;
    }
  }

  /// Starts streaming raw PCM audio chunks.
  Future<Stream<Uint8List>> startStream() async {
    debugPrint('[AuraScribe][Audio] startStream → (16kHz mono, PCM 16-bit)');
    _currentPath = 'stream';
    return _recorder.startStream(
      RecordConfig(
        device: await _device(),
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
  }

  /// Stops recording and returns the path to the WAV file.
  /// Returns null if not recording.
  Future<String?> stop() async {
    final spool = _fileSpool;
    if (spool == null) {
      try {
        return await _recorder.stop();
      } finally {
        _currentPath = null;
      }
    }
    try {
      // AudioRecorder.stop closes its output stream after queued chunks drain.
      // Keep our listener attached until then, including the final audio chunk.
      await _recorder.stop();
      if (_fileError != null) {
        Error.throwWithStackTrace(_fileError!, _fileErrorStack!);
      }
      return (await spool.finish()).path;
    } finally {
      await _releaseFileCapture();
    }
  }

  Future<void> _releaseFileCapture() async {
    final subscription = _fileSubscription;
    final spool = _fileSpool;
    _fileSubscription = null;
    _fileSpool = null;
    _currentPath = null;
    try {
      await subscription?.cancel();
    } finally {
      await spool?.dispose();
    }
  }

  Future<void> cancel() async {
    try {
      await _recorder.cancel();
    } finally {
      await _releaseFileCapture();
    }
  }

  void dispose() {
    unawaited(
      _dispose().catchError((Object error) {
        debugPrint('[AuraScribe][Audio] dispose: $error');
      }),
    );
  }

  Future<void> _dispose() async {
    try {
      await _recorder.dispose();
    } finally {
      await _releaseFileCapture();
    }
  }
}
