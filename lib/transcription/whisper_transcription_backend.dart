import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import '../settings/settings_service.dart';
import 'stt_backend.dart';
import '../storage/project_storage.dart';

/// Whisper.cpp STT via [whisper_ggml].
class WhisperTranscriptionBackend implements SttBackend {
  final SettingsService _settings;

  String? _modelPath;
  String _status = '';
  VoidCallback? onProgress;
  WhisperModel? _cachedModel;
  bool _loaded = false;
  bool _loading = false;

  WhisperTranscriptionBackend(this._settings);

  @override
  bool get isLoaded => _loaded;
  @override
  bool get isLoading => _loading;

  WhisperModel get _model {
    switch (_settings.whisperModelIndex) {
      case 1:
        return WhisperModel.base;
      case 2:
        return WhisperModel.small;
      case 3:
        return WhisperModel.tiny;
      default:
        return WhisperModel.tinyEn;
    }
  }

  @override
  String get modelLabel {
    switch (_settings.whisperModelIndex) {
      case 1:
        return 'Whisper base';
      case 2:
        return 'Whisper small';
      case 3:
        return 'Whisper tiny (multilingual)';
      default:
        return 'Whisper tiny.en';
    }
  }

  @override
  String get statusMessage => _status;

  @override
  Future<String?> load() async {
    final model = _model;
    if (_loaded && _cachedModel == model) return null;
    if (_loading) return null;

    _loading = true;
    try {
      debugPrint(
          '[AuraScribe][Whisper] Preparing ggml-${model.modelName}.bin…');
      final path = await ProjectStorage.instance.download(
          folder: 'whisper',
          name: 'ggml-${model.modelName}.bin',
          url: model.modelUri,
          minBytes: 10000000,
          onProgress: (message) {
            _status = message;
            onProgress?.call();
          });
      _modelPath = path;
      _status = '';
      _cachedModel = model;
      _loaded = true;
      debugPrint('[AuraScribe][Whisper] ✅ Ready at $path');
      return null;
    } catch (e) {
      debugPrint('[AuraScribe][Whisper] ❌ Load error: $e');
      return 'Failed to load Whisper: $e';
    } finally {
      _loading = false;
    }
  }

  Future<void> reloadIfModelChanged() async {
    if (_cachedModel != _model) {
      _loaded = false;
      await load();
    }
  }

  @override
  Future<String> transcribe(String audioPath) async {
    if (!_loaded) {
      return '[Model not loaded — please wait for initialization]';
    }

    final sw = Stopwatch()..start();
    final file = File(audioPath);
    if (!await file.exists()) return '';

    final bytes = await file.length();
    debugPrint('[AuraScribe][Whisper] transcribe: $audioPath ($bytes bytes)');

    if (bytes < 1000) {
      debugPrint(
          '[AuraScribe][Whisper] Audio file too small ($bytes bytes), skipping transcription');
      await _deleteQuietly(file);
      return '';
    }

    const maxBytes = 3 * 1024 * 1024;
    if (bytes > maxBytes) {
      debugPrint(
          '[AuraScribe][Whisper] Audio file too large ($bytes bytes), skipping transcription');
      await _deleteQuietly(file);
      return '';
    }

    try {
      final result = await Whisper(model: _model).transcribe(
        modelPath: _modelPath!,
        transcribeRequest: TranscribeRequest(
            audio: audioPath,
            language: _model == WhisperModel.tinyEn ? 'en' : _settings.language,
            isNoTimestamps: true,
            isRealtime: false),
      );
      final text = result.text.trim();
      debugPrint('[AuraScribe][Whisper] done in ${sw.elapsedMilliseconds}ms');
      return text;
    } finally {
      await _deleteQuietly(file);
      await _deleteQuietly(File('$audioPath.wav'));
    }
  }

  @override
  Future<void> dispose() async {
    _loaded = false;
    _loading = false;
    _cachedModel = null;
  }

  Future<void> _deleteQuietly(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
