import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';

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

  /// flutter_gemma stores models under Application Support/flutter_gemma/.
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
  Future<InferenceModel?> resolveTextModel({InferenceModel? sttSharedModel}) async {
    if (sttSharedModel != null) {
      debugPrint('[AuraScribe][GrammarModel] Reusing Gemma STT model for text task');
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
        maxTokens: 512,
        maxConcurrentSessions: 1,
        preferredBackend: PreferredBackend.cpu,
      );
      _loaded = true;
      debugPrint('[AuraScribe][GrammarModel] ✅ Gemma 3 270M IT ready (CPU)');
    } catch (e) {
      debugPrint('[AuraScribe][GrammarModel] ❌ Load failed, retrying clean install: $e');
      await _purgeBrokenInstall();
      await _installGemma270m(force: true);
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 512,
        maxConcurrentSessions: 1,
        preferredBackend: PreferredBackend.cpu,
      );
      _loaded = true;
      debugPrint('[AuraScribe][GrammarModel] ✅ Gemma 3 270M IT ready after retry');
    } finally {
      _loading = false;
      _loadInFlight = null;
    }
  }

  Future<void> _installGemma270m({bool force = false}) async {
    if (!force) {
      await _purgeIfStaleMetadata();
    } else {
      await _purgeBrokenInstall();
    }

    final token = _resolveHfToken();
    debugPrint('[AuraScribe][GrammarModel] Installing Gemma 3 270M (litertlm)…');
    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
      fileType: ModelFileType.litertlm,
    )
        .fromNetwork(_downloadUrl, token: token.isEmpty ? null : token)
        .install();

    final path = await _expectedModelPath();
    final size = await File(path).length();
    if (size < _minValidBytes) {
      throw Exception(
        'Gemma 3 270M download looks incomplete ($size bytes at $path)',
      );
    }
    debugPrint('[AuraScribe][GrammarModel] Verified model on disk ($size bytes)');
  }

  Future<String> _expectedModelPath() async {
    final supportDir = await getApplicationSupportDirectory();
    return '${supportDir.path}/flutter_gemma/$_fileName';
  }

  /// flutter_gemma metadata can say "installed" while the file was deleted.
  Future<void> _purgeIfStaleMetadata() async {
    final path = await _expectedModelPath();
    final file = File(path);
    final onDisk = await file.exists() && await file.length() >= _minValidBytes;
    if (onDisk) return;

    final registered = await FlutterGemma.isModelInstalled(_fileName);
    if (registered || !onDisk) {
      debugPrint(
        '[AuraScribe][GrammarModel] Purging stale install '
        '(registered=$registered, onDisk=$onDisk, path=$path)',
      );
      await _purgeBrokenInstall();
    }
  }

  String _resolveHfToken() {
    if (_settings.hfToken.isNotEmpty) return _settings.hfToken;
    return Platform.environment['HF_TOKEN'] ?? '';
  }

  Future<void> _purgeBrokenInstall() async {
    // Metadata id is the full filename; older builds may have used the base name.
    for (final id in [_fileName, 'gemma3-270m-it-q8']) {
      try {
        await FlutterGemma.uninstallModel(id);
        debugPrint('[AuraScribe][GrammarModel] Uninstalled $id via flutter_gemma');
      } catch (_) {}
    }

    try {
      final path = await _expectedModelPath();
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        debugPrint('[AuraScribe][GrammarModel] Deleted $path');
      }
    } catch (e) {
      debugPrint('[AuraScribe][GrammarModel] File delete skipped: $e');
    }

    try {
      final supportDir = await getApplicationSupportDirectory();
      final legacyDir = Directory('${supportDir.path}/models/gemma_3_270m');
      if (await legacyDir.exists()) {
        await legacyDir.delete(recursive: true);
        debugPrint('[AuraScribe][GrammarModel] Removed legacy cache at ${legacyDir.path}');
      }
    } catch (e) {
      debugPrint('[AuraScribe][GrammarModel] Legacy cache purge skipped: $e');
    }
  }
}
