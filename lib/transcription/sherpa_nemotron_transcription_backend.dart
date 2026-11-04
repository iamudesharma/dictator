import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../storage/project_storage.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'stt_backend.dart';

class SherpaNemotronTranscriptionBackend implements SttBackend {
  sherpa_onnx.OnlineRecognizer? _recognizer;
  bool _loaded = false;
  bool _loading = false;
  String _statusMessage = '';
  VoidCallback? onProgress;
  sherpa_onnx.OnlineStream? _activeStream;
  String _currentText = '';
  String _finalizedText = '';

  SherpaNemotronTranscriptionBackend();

  @override
  bool get isLoaded => _loaded;

  @override
  bool get isLoading => _loading;

  @override
  String get modelLabel => 'Nemotron-3.5 0.6B (ONNX INT8)';

  @override
  String get statusMessage => _statusMessage;

  @override
  Future<String?> load() async {
    if (_loaded) return null;
    if (_loading) return null;

    _loading = true;
    _statusMessage = 'Initializing bindings…';
    onProgress?.call();

    try {
      debugPrint('[AuraScribe][Nemotron] Initializing sherpa-onnx bindings…');
      sherpa_onnx.initBindings();

      final modelDir = await ProjectStorage.instance
          .directory('models/nemotron_3.5_0.6b_int8');

      const repoId =
          'csukuangfj/sherpa-onnx-nemotron-speech-streaming-en-0.6b-int8-2026-01-14';
      final infoFile = File('${modelDir.path}/model_info.json');
      var needsClean = true;
      if (await infoFile.exists()) {
        try {
          final content = await infoFile.readAsString();
          final info = json.decode(content);
          if (info['repoId'] == repoId) {
            needsClean = false;
          }
        } catch (_) {}
      }

      if (needsClean) {
        debugPrint(
            '[AuraScribe][Nemotron] Model repo change or stale files. Cleaning $modelDir…');
        if (await modelDir.exists()) {
          await modelDir.delete(recursive: true);
        }
        await modelDir.create(recursive: true);
      }

      const repoBaseUrl =
          'https://huggingface.co/csukuangfj/sherpa-onnx-nemotron-speech-streaming-en-0.6b-int8-2026-01-14/resolve/main';

      final encoderPath = '${modelDir.path}/encoder.int8.onnx';
      final decoderPath = '${modelDir.path}/decoder.int8.onnx';
      final joinerPath = '${modelDir.path}/joiner.int8.onnx';
      final tokensPath = '${modelDir.path}/tokens.txt';

      // Download all required files
      await _downloadFileIfNeeded(
          url: '$repoBaseUrl/encoder.int8.onnx',
          savePath: encoderPath,
          fileName: 'encoder.int8.onnx');
      await _downloadFileIfNeeded(
          url: '$repoBaseUrl/decoder.int8.onnx',
          savePath: decoderPath,
          fileName: 'decoder.int8.onnx');
      await _downloadFileIfNeeded(
          url: '$repoBaseUrl/joiner.int8.onnx',
          savePath: joinerPath,
          fileName: 'joiner.int8.onnx');
      await _downloadFileIfNeeded(
          url: '$repoBaseUrl/tokens.txt',
          savePath: tokensPath,
          fileName: 'tokens.txt');

      // Write info file to mark successful setup
      await infoFile.writeAsString(json.encode({'repoId': repoId}));

      // Configure the transducer models
      _statusMessage = 'Loading model into memory…';
      onProgress?.call();

      final transducerConfig = sherpa_onnx.OnlineTransducerModelConfig(
        encoder: encoderPath,
        decoder: decoderPath,
        joiner: joinerPath,
      );

      final modelConfig = sherpa_onnx.OnlineModelConfig(
        transducer: transducerConfig,
        tokens: tokensPath,
        numThreads: 4, // 4 CPU threads for balanced decoding performance
        debug: kDebugMode,
      );

      final config = sherpa_onnx.OnlineRecognizerConfig(
        model: modelConfig,
        enableEndpoint: true,
        rule1MinTrailingSilence: 2.0,
      );

      debugPrint('[AuraScribe][Nemotron] Initializing OnlineRecognizer…');
      _recognizer = sherpa_onnx.OnlineRecognizer(config);
      _warmUpRecognizer();
      _loaded = true;
      _statusMessage = '';
      onProgress?.call();
      debugPrint('[AuraScribe][Nemotron] ✅ Ready.');
      return null;
    } catch (e) {
      debugPrint('[AuraScribe][Nemotron] ❌ Loading failed: $e');
      _statusMessage = 'Error: $e';
      onProgress?.call();
      return 'Failed to load Nemotron: $e';
    } finally {
      _loading = false;
    }
  }

  @override
  Future<String> transcribe(String audioPath) async {
    if (!_loaded || _recognizer == null) {
      return '[Model not loaded — please wait for initialization]';
    }

    final file = File(audioPath);
    if (!await file.exists()) return '';

    try {
      debugPrint('[AuraScribe][Nemotron] Reading WAV samples from $audioPath…');
      final waveData = sherpa_onnx.readWave(audioPath);

      if (waveData.sampleRate == 0 || waveData.samples.isEmpty) {
        debugPrint('[AuraScribe][Nemotron] Empty or invalid WAV file.');
        return '';
      }

      debugPrint(
          '[AuraScribe][Nemotron] Running inference (sampleRate: ${waveData.sampleRate}, samples: ${waveData.samples.length})…');
      final stream = _recognizer!.createStream();
      stream.acceptWaveform(
        samples: waveData.samples,
        sampleRate: waveData.sampleRate,
      );
      stream.inputFinished();

      // Transducer streaming loop
      while (_recognizer!.isReady(stream)) {
        _recognizer!.decode(stream);
      }

      final result = _recognizer!.getResult(stream);
      final text = result.text.trim();

      stream.free();
      debugPrint('[AuraScribe][Nemotron] Inference done: "$text"');
      return text;
    } catch (e) {
      debugPrint('[AuraScribe][Nemotron] Transcription failed: $e');
      return '[Transcription error: $e]';
    } finally {
      await _deleteQuietly(file);
    }
  }

  @override
  Future<void> dispose() async {
    _activeStream?.free();
    _activeStream = null;
    _recognizer?.free();
    _recognizer = null;
    _loaded = false;
    _loading = false;
    _statusMessage = '';
  }

  /// Runs a short silence decode so the first real utterance is not delayed by
  /// ONNX runtime cold-start (often several seconds on first inference).
  void _warmUpRecognizer() {
    final recognizer = _recognizer;
    if (recognizer == null) return;
    final stream = recognizer.createStream();
    try {
      final silence = Float32List(8000); // 0.5 s @ 16 kHz
      stream.acceptWaveform(samples: silence, sampleRate: 16000);
      while (recognizer.isReady(stream)) {
        recognizer.decode(stream);
      }
      debugPrint('[AuraScribe][Nemotron] Warm-up decode complete');
    } catch (e) {
      debugPrint('[AuraScribe][Nemotron] Warm-up skipped: $e');
    } finally {
      stream.free();
    }
  }

  void startStream() {
    if (_recognizer == null) {
      debugPrint(
          '[AuraScribe][Nemotron] Cannot start stream: recognizer is null');
      return;
    }
    _activeStream?.free();
    _activeStream = _recognizer!.createStream();
    _currentText = '';
    _finalizedText = '';
    debugPrint('[AuraScribe][Nemotron] True stream session started');
  }

  void addAudioChunk(Uint8List pcmChunk) {
    final stream = _activeStream;
    if (stream == null || _recognizer == null) return;

    if (pcmChunk.isEmpty) return;

    try {
      // Safely convert Int16 PCM bytes (little endian) to Float32 normalized samples.
      // We use ByteData view to avoid any RangeError alignment issues (e.g. odd byte offsets).
      final byteData = ByteData.sublistView(pcmChunk);
      final len = pcmChunk.length ~/ 2;
      if (len == 0) return;

      final float32List = Float32List(len);
      for (int i = 0; i < len; i++) {
        final int16Val = byteData.getInt16(i * 2, Endian.little);
        float32List[i] = int16Val / 32768.0;
      }

      stream.acceptWaveform(samples: float32List, sampleRate: 16000);
      while (_recognizer!.isReady(stream)) {
        _recognizer!.decode(stream);
      }

      final activeText = _recognizer!.getResult(stream).text.trim();

      if (_recognizer!.isEndpoint(stream)) {
        if (activeText.isNotEmpty) {
          _finalizedText = _finalizedText.isEmpty
              ? activeText
              : '$_finalizedText $activeText';
        }
        _recognizer!.reset(stream);
        _currentText = _finalizedText;
      } else {
        _currentText =
            _finalizedText.isEmpty ? activeText : '$_finalizedText $activeText';
      }
    } catch (e) {
      debugPrint('[AuraScribe][Nemotron] Error during stream decode chunk: $e');
    }
  }

  String getLiveTranscript() => _currentText;

  /// Stable text from completed utterance segments (after [isEndpoint] + [reset]).
  /// Partial hypotheses can revise; this only grows when sherpa-onnx finalizes a segment.
  String getFinalizedTranscript() => _finalizedText;

  Future<String> endStream() async {
    final stream = _activeStream;
    if (stream == null || _recognizer == null) {
      _currentText = '';
      _finalizedText = '';
      return '';
    }

    try {
      stream.inputFinished();
      while (_recognizer!.isReady(stream)) {
        _recognizer!.decode(stream);
      }
      final lastResult = _recognizer!.getResult(stream).text.trim();
      final finalResult = _finalizedText.isEmpty
          ? lastResult
          : (lastResult.isEmpty
              ? _finalizedText
              : '$_finalizedText $lastResult');
      debugPrint(
          '[AuraScribe][Nemotron] True stream session ended. Final text: "$finalResult"');
      return finalResult.trim();
    } catch (e) {
      debugPrint('[AuraScribe][Nemotron] Error ending stream: $e');
      return _currentText;
    } finally {
      stream.free();
      _activeStream = null;
      _currentText = '';
      _finalizedText = '';
    }
  }

  /// Downloads file streaming it directly to disk to minimize memory consumption.
  /// Also verifies file length using HEAD request if file already exists.
  Future<void> _downloadFileIfNeeded(
      {required String url,
      required String savePath,
      required String fileName}) async {
    await ProjectStorage.instance.download(
        folder: 'nemotron_3.5_0.6b_int8',
        name: fileName,
        url: Uri.parse(url),
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
