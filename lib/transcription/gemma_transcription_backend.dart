import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'stt_backend.dart';

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

  InferenceModel? _model;
  bool _loaded = false;
  bool _loading = false;
  String _statusMessage = '';
  VoidCallback? onProgress;

  String? _cachePath;
  String? get modelCachePath => _cachePath;

  GemmaTranscriptionBackend({String? prompt}) : _prompt = prompt ?? _defaultPrompt;

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
      debugPrint('[Dictator][Gemma] Initializing flutter_gemma…');
      await FlutterGemma.initialize();

      final supportDir = await getApplicationSupportDirectory();
      final modelDir = Directory('${supportDir.path}/models/gemma_4_e2b');

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
        debugPrint('[Dictator][Gemma] Repo change or stale files. Cleaning $modelDir…');
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

      debugPrint('[Dictator][Gemma] Installing from file: $localPath');
      await FlutterGemma.installModel(
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
      ).fromFile(localPath).install();

      _statusMessage = 'Loading into memory…';
      onProgress?.call();

      debugPrint('[Dictator][Gemma] Loading into memory…');
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 8192,
        supportAudio: true,
        maxConcurrentSessions: 1,
      );

      _loaded = true;
      _statusMessage = '';
      onProgress?.call();
      debugPrint('[Dictator][Gemma] ✅ Ready (downloaded on demand, ~16 GB RAM recommended)');
      return null;
    } catch (e) {
      debugPrint('[Dictator][Gemma] ❌ Load error: $e');
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
    debugPrint('[Dictator][Gemma] transcribe: $audioPath ($bytes bytes)');

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
      debugPrint('[Dictator][Gemma] done in ${sw.elapsedMilliseconds}ms');
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
        debugPrint('[Dictator][Gemma] close: $e');
      }
      _model = null;
    }
    _loaded = false;
    _loading = false;
    _statusMessage = '';
  }

  Future<void> _downloadFileIfNeeded({
    required String url,
    required String savePath,
    required String fileName,
  }) async {
    final file = File(savePath);
    if (await file.exists()) {
      final localLength = await file.length();
      if (localLength > 0) {
        try {
          final headResponse = await http.head(Uri.parse(url));
          final remoteLengthHeader = headResponse.headers['content-length'];
          if (remoteLengthHeader != null) {
            final remoteLength = int.parse(remoteLengthHeader);
            if (localLength == remoteLength) {
              debugPrint('[Dictator][Gemma] $fileName already exists and matches remote size ($localLength bytes).');
              return;
            } else {
              debugPrint('[Dictator][Gemma] File size mismatch for $fileName (local: $localLength, remote: $remoteLength). Deleting and re-downloading…');
              await file.delete();
            }
          } else {
            debugPrint('[Dictator][Gemma] $fileName already exists (cannot verify size, skipping download).');
            return;
          }
        } catch (e) {
          debugPrint('[Dictator][Gemma] HEAD check failed for $fileName: $e. Assuming existing file is fine.');
          return;
        }
      }
    }

    debugPrint('[Dictator][Gemma] Downloading $url…');
    _statusMessage = 'Downloading $fileName…';
    onProgress?.call();

    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);

    if (response.statusCode == 200) {
      final totalBytes = response.contentLength ?? 0;
      var downloadedBytes = 0;
      final sink = file.openWrite();

      await response.stream.forEach((chunk) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        if (totalBytes > 0) {
          final progressPercent = (downloadedBytes / totalBytes * 100).toStringAsFixed(1);
          final mbDownloaded = (downloadedBytes / (1024 * 1024)).toStringAsFixed(1);
          final mbTotal = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
          _statusMessage = 'Downloading $fileName: $progressPercent% ($mbDownloaded/$mbTotal MB)';
          onProgress?.call();
        } else {
          final mbDownloaded = (downloadedBytes / (1024 * 1024)).toStringAsFixed(1);
          _statusMessage = 'Downloading $fileName: $mbDownloaded MB';
          onProgress?.call();
        }
      });
      await sink.close();
      debugPrint('[Dictator][Gemma] Saved file to $savePath');
    } else {
      throw Exception('Failed to download $url (Status: ${response.statusCode})');
    }
  }

  Future<void> _deleteQuietly(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
