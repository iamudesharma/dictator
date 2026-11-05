import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import '../storage/project_storage.dart';

import '../settings/settings_service.dart';

/// Lightweight Gemma 3 270M for grammar cleanup and Smart Commands.
///
/// When STT uses [SttEngine.gemma], grammar and smart commands reuse that
/// multimodal model instead (no separate download). For Whisper or Nemotron STT,
/// this service loads the ~300 MB Gemma 3 270M IT model.
class GrammarModelService {
  static const _fileName = 'gemma3-270m-it-q8.litertlm';
  static const _downloadUrl =
      'https://huggingface.co/litert-community/gemma-3-270m-it/resolve/main/$_fileName';

  /// Weight files and compiled caches stay inside project storage.
  static const _minValidBytes = 200 * 1024 * 1024; // ~200 MB

  final SettingsService _settings;

  GrammarModelService(this._settings);

  InferenceModel? _model;
  bool _loaded = false;
  bool _loading = false;
  Future<void>? _loadInFlight;

  bool get isLoaded => _loaded;
  bool get isLoading => _loading;
  InferenceModel? get model => _model;

  /// Gemma model for text tasks (grammar, summarize, rewrite, …).
  ///
  /// Pass [sttSharedModel] when audio STT is Gemma 4 E2B so we reuse one model.
  /// Otherwise loads Gemma 3 270M IT (Whisper / Nemotron path).
  Future<InferenceModel?> resolveTextModel(
      {InferenceModel? sttSharedModel}) async {
    if (sttSharedModel != null) {
      debugPrint(
          '[AuraScribe][GrammarModel] Reusing Gemma STT model for text task');
      return sttSharedModel;
    }
    await ensureLoaded();
    return _model;
  }

  /// Loads Gemma 3 270M. Concurrent callers await the same in-flight load.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loadInFlight ??= _load();
    await _loadInFlight!;
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loading = true;
    try {
      debugPrint('[AuraScribe][GrammarModel] Initializing flutter_gemma…');
      await FlutterGemma.initialize();

      await _installGemma270m();
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 2048,
        maxConcurrentSessions: 1,
        preferredBackend: PreferredBackend.cpu,
      );
      _loaded = true;
      debugPrint('[AuraScribe][GrammarModel] ✅ Gemma 3 270M IT ready (CPU)');
    } finally {
      _loading = false;
      _loadInFlight = null;
    }
  }

  Future<void> _installGemma270m() async {
    final path = await ProjectStorage.instance.download(
        folder: 'grammar',
        name: _fileName,
        url: Uri.parse(_downloadUrl),
        minBytes: _minValidBytes,
        token: _settings.hfToken.isNotEmpty
            ? _settings.hfToken
            : Platform.environment['HF_TOKEN']);
    await FlutterGemma.installModel(
            modelType: ModelType.gemmaIt, fileType: ModelFileType.litertlm)
        .fromFile(path)
        .install();
  }

  Future<void> unload() async {
    await _loadInFlight;
    await _model?.close();
    _model = null;
    _loaded = false;
  }
}
