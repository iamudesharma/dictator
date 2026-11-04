import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../settings/settings_service.dart';
import '../shared/stt_engine.dart';
import 'gemma_transcription_backend.dart';
import 'stt_backend.dart';
import 'gguf_transcription_backend.dart';
import 'moonshine_transcription_backend.dart';
import 'whisper_transcription_backend.dart';
import 'sherpa_nemotron_transcription_backend.dart';

/// Facade for speech-to-text — delegates to Whisper or Gemma per [SettingsService].
///
/// Backends are constructed **lazily** so only the active engine occupies RAM.
/// The unused engine's heavy resources (2.4 GB Gemma install, 75-500 MB Whisper
/// model) are never allocated until the user actually selects that engine.
class TranscriptionService extends ChangeNotifier {
  final SettingsService _settings;

  GgufTranscriptionBackend? _gguf;
  MoonshineTranscriptionBackend? _moonshine;
  WhisperTranscriptionBackend? _whisper;
  GemmaTranscriptionBackend? _gemma;
  SherpaNemotronTranscriptionBackend? _nemotron;
  SttEngine _activeEngine;

  TranscriptionService(this._settings)
      : _activeEngine = SttEngineX.fromIndex(_settings.sttEngineIndex);

  Future<String?>? _loadInFlight;

  SttEngine get activeEngine => _activeEngine;

  bool get isLoaded {
    final backend = _activeBackend();
    return backend != null && backend.isLoaded;
  }

  bool get isLoading {
    final backend = _activeBackend();
    return backend != null && backend.isLoading;
  }

  String get modelLabel {
    final backend = _activeBackend();
    return backend?.modelLabel ?? _labelFor(_activeEngine);
  }

  String get statusMessage {
    final backend = _activeBackend();
    return backend?.statusMessage ?? '';
  }

  bool get supportsTrueStreaming => _activeEngine == SttEngine.nemotron;

  void startStream() {
    if (supportsTrueStreaming) {
      _nemotron?.startStream();
    }
  }

  void addAudioChunk(Uint8List pcmChunk) {
    if (supportsTrueStreaming) {
      _nemotron?.addAudioChunk(pcmChunk);
    }
  }

  String getLiveTranscript() {
    if (supportsTrueStreaming) {
      return _nemotron?.getLiveTranscript() ?? '';
    }
    return '';
  }

  String getFinalizedTranscript() {
    if (supportsTrueStreaming) {
      return _nemotron?.getFinalizedTranscript() ?? '';
    }
    return '';
  }

  Future<String> endStream() async {
    if (supportsTrueStreaming) {
      final text = await _nemotron?.endStream() ?? '';
      return _cleanTranscriptionNoise(text);
    }
    return '';
  }

  /// When using Gemma STT, grammar and Smart Commands reuse this model.
  /// Whisper / Nemotron use the separate Gemma 3 270M text model instead.
  InferenceModel? get sharedGemmaModelForGrammar {
    if (_activeEngine != SttEngine.gemma) return null;
    final g = _gemma;
    if (g == null || !g.isLoaded) return null;
    return g.model;
  }

  /// Load the engine selected in settings (unloads the other backend).
  /// Concurrent callers share the same in-flight load.
  Future<String?> loadModel() => ensureLoaded();

  /// Blocks until the active STT engine is ready. Safe to call while a load is
  /// already in progress (e.g. background preload + user hotkey).
  Future<String?> ensureLoaded() async {
    if (isLoaded) return null;
    _loadInFlight ??= _loadSelectedEngine();
    return _loadInFlight!;
  }

  Future<String?> _loadSelectedEngine() async {
    try {
      final target = SttEngineX.fromIndex(_settings.sttEngineIndex);
      if (target != _activeEngine) {
        await _disposeActive();
        _activeEngine = target;
      }
      return await _loadActive();
    } finally {
      _loadInFlight = null;
    }
  }

  /// Call after user changes STT engine in settings.
  Future<void> switchEngine(SttEngine engine) async {
    if (engine == _activeEngine && isLoaded) return;
    await _loadInFlight;
    await _disposeActive();
    _activeEngine = engine;
    await _settings.setSttEngineIndex(engine.index);
    final error = await ensureLoaded();
    if (error != null) debugPrint('[AuraScribe] switchEngine: $error');
    notifyListeners();
  }

  Future<void> unloadModel() async {
    await _loadInFlight;
    await _disposeActive();
    notifyListeners();
  }

  Future<void> reloadModelIfNeeded() async {
    final w = _whisper;
    if (_activeEngine == SttEngine.whisper && w != null) {
      await w.reloadIfModelChanged();
      notifyListeners();
    }
  }

  Future<String> transcribe(String audioPath) async {
    final backend = _activeBackend();
    if (backend == null) {
      return '[Model not loaded — please wait for initialization]';
    }
    if (!backend.isLoaded) {
      final error = await backend.load();
      if (error != null) {
        debugPrint('[AuraScribe] lazy load failed: $error');
        return '[Model not loaded — please wait for initialization]';
      }
      notifyListeners();
    }
    final rawTranscript = await backend.transcribe(audioPath);
    return _cleanTranscriptionNoise(rawTranscript);
  }

  String _cleanTranscriptionNoise(String text) {
    // Matches any [noise] or (noise) annotations generated by Whisper for non-speech events
    final bracketPattern = RegExp(r'\[[^\]]*\]|\([^)]*\)');
    String cleaned = text.replaceAll(bracketPattern, '');
    // Clean up multiple spaces or leading/trailing whitespace
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.trim();
  }

  Future<String?> _loadActive() async {
    notifyListeners();
    final backend = _ensureBackend(_activeEngine);
    if (backend == null) {
      notifyListeners();
      return 'Unknown STT engine: $_activeEngine';
    }
    final error = await backend.load();
    notifyListeners();
    return error;
  }

  Future<void> _disposeActive() async {
    final backend = _activeBackend();
    if (backend != null) await backend.dispose();
    switch (_activeEngine) {
      case SttEngine.gemma:
        _gemma = null;
        break;
      case SttEngine.whisper:
        _whisper = null;
        break;
      case SttEngine.nemotron:
        _nemotron = null;
        break;
      case SttEngine.gguf:
        _gguf = null;
        break;
      case SttEngine.moonshine:
        _moonshine = null;
        break;
    }
  }

  SttBackend? _activeBackend() => _ensureBackend(_activeEngine);

  SttBackend? _ensureBackend(SttEngine engine) {
    switch (engine) {
      case SttEngine.gguf:
        final b = _gguf ??= GgufTranscriptionBackend(_settings);
        b.onProgress = notifyListeners;
        return b;
      case SttEngine.moonshine:
        final b = _moonshine ??= MoonshineTranscriptionBackend();
        b.onProgress = notifyListeners;
        return b;
      case SttEngine.gemma:
        const promptText =
            'Transcribe the following speech segment in English into English text. '
            'The speaker has an Indian English accent. Transcribe the spoken English accurately, '
            'accounting for retroflex sounds, syllable-timed rhythm, and typical Indian English pronunciation patterns. '
            'Use digits for numbers. Output only the transcription, nothing else.';
        final b =
            _gemma ??= GemmaTranscriptionBackend(_settings, prompt: promptText);
        b.onProgress = notifyListeners;
        return b;
      case SttEngine.whisper:
        final b = _whisper ??= WhisperTranscriptionBackend(_settings);
        b.onProgress = notifyListeners;
        return b;
      case SttEngine.nemotron:
        final b = _nemotron ??= SherpaNemotronTranscriptionBackend();
        b.onProgress = notifyListeners;
        return b;
    }
  }

  String _labelFor(SttEngine engine) {
    switch (engine) {
      case SttEngine.gemma:
        return 'Gemma 4 E2B (GPU)';
      case SttEngine.gguf:
        return 'GGUF speech catalog';
      case SttEngine.whisper:
        return 'Whisper';
      case SttEngine.moonshine:
        return 'Moonshine Tiny INT8';
      case SttEngine.nemotron:
        return 'Nemotron-3.5 0.6B (ONNX INT8)';
    }
  }

  @override
  void dispose() {
    _gguf?.dispose();
    _moonshine?.dispose();
    _whisper?.dispose();
    _gemma?.dispose();
    _nemotron?.dispose();
    super.dispose();
  }
}
