import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import '../storage/project_storage.dart';

import 'stt_backend.dart';
import '../settings/settings_service.dart';

/// Gemma 4 E2B multimodal STT via [flutter_gemma] (audio → text).
///
/// Model is downloaded on first use from Hugging Face with live progress.
class GemmaTranscriptionBackend implements SttBackend {
  static const _repoId = 'litert-community/gemma-4-E2B-it-litert-lm';
  static const _fileName = 'gemma-4-E2B-it.litertlm';
  static const _downloadUrl =
      'https://huggingface.co/$_repoId/resolve/main/$_fileName';
  static const _defaultPrompt =
      'Transcribe the following speech segment in English into English text. Use digits for numbers. Output only the transcription, nothing else.';

  final String _prompt;
  final SettingsService settings;

  InferenceModel? _model;
  bool _loaded = false;
  bool _loading = false;
  String _statusMessage = '';
  VoidCallback? onProgress;

  String? _cachePath;
  String? get modelCachePath => _cachePath;

  GemmaTranscriptionBackend(this.settings, {String? prompt})
      : _prompt = prompt ?? _defaultPrompt;

  @override
  bool get isLoaded => _loaded;
  @override
  bool get isLoading => _loading;
  InferenceModel? get model => _model;

  @override
  String get modelLabel => 'Gemma 4 E2B (GPU)';

  @override
  String get statusMessage => _statusMessage;

  @override
  Future<String?> load() async {
    if (_loaded) return null;
    if (_loading) return null;

    _loading = true;
    _statusMessage = 'Initializing…';
    onProgress?.call();

    try {
      debugPrint('[AuraScribe][Gemma] Initializing flutter_gemma…');
      await FlutterGemma.initialize();

      final modelDir =
          await ProjectStorage.instance.directory('models/gemma_4_e2b');

      final infoFile = File('${modelDir.path}/model_info.json');
      var needsClean = true;
      if (await infoFile.exists()) {
        try {
          final content = await infoFile.readAsString();
          final info = json.decode(content);
          if (info['repoId'] == _repoId) {
            needsClean = false;
          }
        } catch (_) {}
      }

      if (needsClean) {
        debugPrint(
            '[AuraScribe][Gemma] Repo change or stale files. Cleaning $modelDir…');
        if (await modelDir.exists()) {
          await modelDir.delete(recursive: true);
        }
        await modelDir.create(recursive: true);
      }

      final localPath = '${modelDir.path}/$_fileName';
      _cachePath = localPath;

      await _downloadFileIfNeeded(
        url: _downloadUrl,
        savePath: localPath,
        fileName: _fileName,
      );

      // Write info file to mark successful setup
      await infoFile.writeAsString(json.encode({'repoId': _repoId}));

      _statusMessage = 'Installing model…';
      onProgress?.call();

      debugPrint('[AuraScribe][Gemma] Installing from file: $localPath');
      await FlutterGemma.installModel(
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
      ).fromFile(localPath).install();

      _statusMessage = 'Loading into memory…';
      onProgress?.call();

      debugPrint('[AuraScribe][Gemma] Loading into memory…');
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 8192,
        supportAudio: true,
        maxConcurrentSessions: 1,
      );

      _loaded = true;
      _statusMessage = '';
      onProgress?.call();
      debugPrint(
          '[AuraScribe][Gemma] ✅ Ready (downloaded on demand, ~16 GB RAM recommended)');
      return null;
    } catch (e) {
      debugPrint('[AuraScribe][Gemma] ❌ Load error: $e');
      _statusMessage = 'Error: $e';
      onProgress?.call();
      return 'Failed to load Gemma: $e';
    } finally {
      _loading = false;
    }
  }

  @override
  Future<String> transcribe(String audioPath) async {
    if (!_loaded || _model == null) {
      return '[Model not loaded — please wait for initialization]';
    }

    final sw = Stopwatch()..start();
    final file = File(audioPath);
    if (!await file.exists()) return '';

    final bytes = await file.length();
    debugPrint('[AuraScribe][Gemma] transcribe: $audioPath ($bytes bytes)');

    const maxBytes = 3 * 1024 * 1024;
    if (bytes > maxBytes) {
      await _deleteQuietly(file);
      return '';
    }

    final audioBytes = await file.readAsBytes();

    final session = await _model!.createSession(enableAudioModality: true);

    try {
      await session.addQueryChunk(
        Message(text: _prompt, audioBytes: audioBytes),
      );
      final response = await session.getResponse();
      final text = response.trim();
      debugPrint('[AuraScribe][Gemma] done in ${sw.elapsedMilliseconds}ms');
      return text;
    } finally {
      await session.close();
      await _deleteQuietly(file);
    }
  }

  @override
  Future<void> dispose() async {
    if (_model != null) {
      try {
        await _model!.close();
      } catch (e) {
        debugPrint('[AuraScribe][Gemma] close: $e');
      }
      _model = null;
    }
    _loaded = false;
    _loading = false;
    _statusMessage = '';
  }

  Future<void> _downloadFileIfNeeded(
      {required String url,
      required String savePath,
      required String fileName}) async {
    await ProjectStorage.instance.download(
        folder: 'gemma_4_e2b',
        name: fileName,
        url: Uri.parse(url),
        token: settings.hfToken.isNotEmpty
            ? settings.hfToken
            : Platform.environment['HF_TOKEN'],
        onProgress: (message) {
          _statusMessage = message;
          onProgress?.call();
        });
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
