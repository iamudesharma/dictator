import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import '../settings/settings_service.dart';
import 'stt_backend.dart';

/// Whisper.cpp STT via [whisper_ggml].
class WhisperTranscriptionBackend implements SttBackend {
  final SettingsService _settings;

  final WhisperController _whisper = WhisperController();
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
      default:
        return 'Whisper tiny.en';
    }
  }

  @override
  String get statusMessage => '';

  @override
  Future<String?> load() async {
    final model = _model;
    if (_loaded && _cachedModel == model) return null;
    if (_loading) return null;

    _loading = true;
    try {
      debugPrint('[AuraScribe][Whisper] Preparing ggml-${model.modelName}.bin…');
      final path = await _whisper.downloadModel(model);
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
      debugPrint('[AuraScribe][Whisper] Audio file too small ($bytes bytes), skipping transcription');
      await _deleteQuietly(file);
      return '';
    }

    const maxBytes = 3 * 1024 * 1024;
    if (bytes > maxBytes) {
      debugPrint('[AuraScribe][Whisper] Audio file too large ($bytes bytes), skipping transcription');
      await _deleteQuietly(file);
      return '';
    }

    try {
      final result = await _whisper.transcribe(
        model: _model,
        audioPath: audioPath,
        lang: 'en',
      );
      final text = result?.transcription.text.trim() ?? '';
      debugPrint('[AuraScribe][Whisper] done in ${sw.elapsedMilliseconds}ms');
      return text;
    } finally {
      await _deleteQuietly(file);
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
