import '../l10n/app_localizations.dart';
import '../audio/pause_compactor.dart';
import '../control/control_service.dart';
import '../memory/detached_text_input.dart';
import 'dart:async';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../history/history_service.dart';
import '../output/output_pipeline.dart';
import '../output/spoken_text.dart';
import '../meetings/meeting_service.dart';
import '../capture/annotation_service.dart';
import '../updates/update_service.dart';
import '../diagnostics/activity_log.dart';
import 'package:window_manager/window_manager.dart';

import '../shared/dictation_state.dart';
import '../shared/dictation_mode.dart';
import '../audio/audio_service.dart';
import '../audio/audio_output_service.dart';
import '../audio/voice_filter_service.dart';
import '../vad/vad_service.dart';
import '../transcription/transcription_service.dart';
import '../grammar/grammar_service.dart';
import '../accessibility/accessibility_service.dart';
import '../accessibility/live_text_inserter.dart';
import '../tray/tray_service.dart';
import '../shared/sound_service.dart';
import '../shared/stt_engine.dart';
import '../audio/pcm_spool.dart';
import '../storage/project_storage.dart';
import '../grammar/smart_command_service.dart';
import '../settings/settings_service.dart';

enum AppView {
  settings,
  smartCommands,
}

/// Central state machine for the dictation loop.
/// Coordinates: recording → VAD → transcribe → grammar → insert
class DictationOrchestrator extends ChangeNotifier with WindowListener {
  final AudioService _audio;
  final _audioOutput = AudioOutputService();
  final VadService _vad;
  final TranscriptionService _transcription;
  final GrammarService _grammar;
  final AccessibilityService _accessibility;
  final TrayService _tray;
  final SmartCommandService _smartCommand;
  final SettingsService _settings;

  DictationState _state = DictationState.idle;
  String? _lastTranscript;
  String? _errorMessage;
  bool _usedFallback = false;

  // View Routing & Smart Commands HUD
  AppView _currentView = AppView.settings;
  bool _smartCommandRunning = false;
  String? _smartCommandError;
  String? _selectedTextToProcess;

  // Audio Streaming (Phase 6)
  StreamSubscription<Uint8List>? _audioSubscription;
  PcmSpool? _pcmSpool;
  Timer? _streamingTimer;
  bool _isStreamingTranscribing = false;
  Completer<void>? _partialFinished;
  String _liveTranscript = '';
  bool _indicatorVisible = false;

  late LiveTextInserter _liveInserter =
      LiveTextInserter(_accessibility.insertText);
  Timer? _feedbackTimer;

  bool _disposing = false;
  @override
  void notifyListeners() {
    if (_disposing) return;
    _transcription.memory?.setActive(
        this,
        _starting ||
            _smartCommandRunning ||
            _externalActivity != null ||
            (_state != DictationState.idle && _state != DictationState.error));
    super.notifyListeners();
  }

  @override
  void onWindowClose() => unawaited(hideSettingsWindow());
  @override
  void onWindowMinimize() => setSettingsVisible(false);
  @override
  void onWindowRestore() => setSettingsVisible(true);
  @override
  void onWindowFocus() => setSettingsVisible(true);

  bool settingsVisible = false;
  final settingsTreeVisible = ValueNotifier(false);
  int _settingsDialogs = 0;
  final Map<String, String> settingsDrafts = {};

  Future<T?> withSettingsDialog<T>(Future<T?> Function() show) async {
    _settingsDialogs++;
    _publishSettingsVisibility();
    try {
      return await show();
    } finally {
      _settingsDialogs--;
      _publishSettingsVisibility();
    }
  }

  void setSettingsVisible(bool visible) {
    if (settingsVisible == visible) return;
    settingsVisible = visible;
    _publishSettingsVisibility();
    notifyListeners();
  }

  void _publishSettingsVisibility() {
    final keep = settingsVisible || _settingsDialogs > 0;
    settingsTreeVisible.value = keep;
    if (!keep) {
      FocusManager.instance.primaryFocus?.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!settingsTreeVisible.value && !_disposing) {
          releaseDetachedTextInput(
              WidgetsBinding.instance.platformDispatcher.implicitView?.viewId ??
                  0);
        }
      });
    }
  }

  Future<void> hideSettingsWindow() async {
    setSettingsVisible(false);
    // With preventClose enabled, disposal gets a frame before the native view
    // becomes hidden and may stop scheduling Flutter frames.
    await WidgetsBinding.instance.endOfFrame;
    await windowManager.hide();
  }

  bool get isStarting => _starting;
  bool _preparing = false, _cancelStarting = false, _startingFromHold = false;
  double _audioLevel = 0;
  bool get isPreparing => _preparing;
  bool get indicatorAtTop => _settings.indicatorAtTop;
  double get audioLevel => _audioLevel;
  String get recordingHint => _settings.holdShortcut
      ? 'Release shortcut to finish'
      : 'Press shortcut to finish';
  void dismissFeedback() {
    if (_state == DictationState.error) _setState(DictationState.idle);
  }

  void cancelPreparation() {
    if (!_preparing) return;
    _cancelStarting = true;
    _preparing = false;
    _setState(DictationState.idle);
  }

  UpdateService? _updates;
  ControlService? _control;
  ControlService get control =>
      _control ??= ControlService(this, _transcription, _settings);
  UpdateService get updates => _updates ??= UpdateService(_settings, this);
  int settingsPage = 0;
  String? requestedStory;
  int storyRequest = 0;
  Future<void> openStory(String id) async {
    requestedStory = id;
    storyRequest++;
    settingsPage = 11;
    await showSettings();
    notifyListeners();
  }

  AnnotationService? _annotations;
  AnnotationService get annotations => _annotations ??= AnnotationService(this);
  Future<void> Function(String)? _transcriptDestination;
  Future<String> previewOutput(String text, List<OutputStep> steps) =>
      OutputProcessor(_grammar.transform).process(text, steps);
  Future<String> processGlobalOutput(String text) async {
    text = await _grammar.clean(text);
    text = _settings.applyReplacements(text);
    text = await previewOutput(
        text, PipelineStore.resolve(await PipelineStore().read(), '*'));
    return SpokenText.apply(text,
        language: _settings.language,
        symbols: _settings.option('spokenSymbols'),
        formatting: _settings.option('spokenFormatting'),
        fillers: _settings.option('fillers'),
        spacing: _settings.option('smartSpacing'));
  }

  Future<void> processTypedText() async {
    if (!isAvailable || paused) return;
    externalActivity = 'Processing typed text';
    try {
      final target = await _accessibility.captureDictationTarget();
      final text = await const MethodChannel('com.aurascribe/accessibility')
          .invokeMethod<String>('selectFocusedText');
      if (text == null || text.trim().isEmpty) {
        throw StateError('The focused field does not expose editable text.');
      }
      final output = await previewOutput(
          _settings.applyReplacements(text),
          PipelineStore.resolve(
              await PipelineStore().read(), target['bundleId'] ?? ''));
      _accessibility.restoreClipboard = _settings.restoreClipboard;
      await _accessibility.insertText(output);
      await _remember(output);
    } catch (e) {
      _setError('Could not process typed text: $e');
    } finally {
      await _accessibility.releaseDictationTarget();
      externalActivity = null;
    }
  }

  Future<void> dictateTo(Future<void> Function(String) destination) async {
    if (_state == DictationState.recording && _transcriptDestination != null) {
      await toggle(raw: true);
      return;
    }
    if (!isAvailable) throw StateError('Finish the current audio task first.');
    _transcriptDestination = destination;
    try {
      await toggle(raw: true);
    } catch (_) {
      _transcriptDestination = null;
      rethrow;
    }
  }

  VoiceFilterService? _voiceFilter;
  VoiceFilterService get voiceFilter =>
      _voiceFilter ??= VoiceFilterService(this);
  void updateVoiceActivity(String? value) {
    _tray.updateVoiceActivity(value);
  }

  set audioInputOverride(String? uid) {
    _audio.microphoneOverride = uid;
  }

  String get effectiveMicrophoneId =>
      _audio.microphoneOverride ?? _settings.microphoneId;
  MeetingService? _meetings;
  MeetingService get meetings => _meetings ??=
      MeetingService(this, _transcription, _grammar, settings: _settings);
  String? _externalActivity;
  String? get externalActivity => _externalActivity;
  set externalActivity(String? value) {
    _externalActivity = value;
    _tray.updateActivity(value);
    notifyListeners();
  }

  bool get isAvailable =>
      !_starting &&
      !_smartCommandRunning &&
      _externalActivity == null &&
      (_state == DictationState.idle || _state == DictationState.error);
  bool _rawSession = false;
  List<OutputStep> _outputSteps = [];
  DictationMode get dictationMode => (_rawSession ||
          _settings.copyOnly ||
          _outputSteps.isNotEmpty ||
          ['spokenSymbols', 'spokenFormatting', 'fillers', 'smartSpacing']
              .any((key) => _settings.option(key)))
      ? DictationMode.enhancedAccuracy
      : _settings.dictationMode;
  DictationState get state => _state;
  String? get lastTranscript => _lastTranscript;
  String? get errorMessage => _errorMessage;
  bool get usedFallback => _usedFallback;

  AppView get currentView => _currentView;
  bool get smartCommandRunning => _smartCommandRunning;
  String? get smartCommandError => _smartCommandError;
  String get liveTranscript => _liveTranscript;

  DictationOrchestrator({
    required this._audio,
    required this._vad,
    required this._transcription,
    required this._grammar,
    required this._accessibility,
    required this._tray,
    required this._smartCommand,
    required this._settings,
  }) {
    windowManager.addListener(this);
    _vad.onLevel = (value) {
      if (_state != DictationState.recording) return;
      _audioLevel = value;
      _syncIndicator();
    };
    _vad.onSilenceDetected = _onSilenceDetected;
    _vad.onMaxDuration = () => _stopAndProcess();
  }

  /// Called by HotkeyService or tray menu tap.
  bool _starting = false;
  bool _held = false;
  Future<void> startHeldDictation() async {
    if (_held || !isAvailable) return;
    _held = true;
    _startingFromHold = true;
    try {
      await toggle();
    } finally {
      _startingFromHold = false;
    }
  }

  Future<void> stopHeldDictation() async {
    _held = false;
    if (_preparing) cancelPreparation();
    if (_state == DictationState.recording) await _stopAndProcess();
  }

  /// User-triggered diagnostic: click a destination during the countdown.
  /// Uses the production destination/panel/insertion path without opening audio.
  Future<void> testTextInsertion(String text) async {
    if (!isAvailable || text.trim().isEmpty) {
      throw StateError('Finish the current task and enter test text first.');
    }
    externalActivity =
        'Insertion test: click the destination field (5 seconds)';
    try {
      await Future<void>.delayed(const Duration(seconds: 5));
      await _accessibility.captureDictationTarget();
      _cancelStarting = false;
      _setState(DictationState.inserting);
      await _showDictationIndicator();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      _accessibility.returnToApp =
          _settings.option('returnToApp', fallback: true);
      _accessibility.smartSpacing = _settings.option('smartSpacing');
      _accessibility.terminalPaste =
          _terminalSession || _settings.terminalPaste;
      _accessibility.restoreClipboard = _settings.restoreClipboard;
      await _accessibility.insertText(text);
      _setState(DictationState.idle);
    } catch (e) {
      _setError('Text insertion failed: $e');
      rethrow;
    } finally {
      await _accessibility.releaseDictationTarget();
      externalActivity = null;
    }
  }

  void refreshPreferences() {
    unawaited(_tray.refresh());
    notifyListeners();
  }

  Future<void> cancelDictation() async {
    if (_preparing) {
      cancelPreparation();
      return;
    }
    if (_state != DictationState.recording) return;
    _setState(DictationState.transcribing);
    _vad.stop();
    _streamingTimer?.cancel();
    try {
      await _audioSubscription?.cancel();
      await _partialFinished?.future;
      await _audio.cancel();
      if (_transcription.supportsTrueStreaming) {
        await _transcription.endStream();
      }
    } finally {
      try {
        await _pcmSpool?.dispose();
      } finally {
        _pcmSpool = null;
        try {
          await _audioOutput.end();
        } finally {
          try {
            await _restoreSessionSpeech();
          } finally {
            await _accessibility.releaseDictationTarget();
            _setState(DictationState.idle);
          }
        }
      }
    }
  }

  Future<void> pasteLast() async {
    if (_lastTranscript == null || !isAvailable) return;
    _setState(DictationState.inserting);
    try {
      await _accessibility.captureDictationTarget();
      _accessibility.returnToApp =
          _settings.option('returnToApp', fallback: true);
      _accessibility.smartSpacing = _settings.option('smartSpacing');
      _accessibility.terminalPaste =
          _terminalSession || _settings.terminalPaste;
      _accessibility.restoreClipboard = _settings.restoreClipboard;
      await _accessibility.insertText(_lastTranscript!);
      _setState(DictationState.idle);
    } catch (e) {
      _setError('Text insertion failed: $e');
    } finally {
      await _accessibility.releaseDictationTarget();
    }
  }

  String? _historyAudio;
  (int, String, String)? _sessionSpeech;
  Future<void> _restoreSessionSpeech() async {
    final previous = _sessionSpeech;
    if (previous == null) return;
    _sessionSpeech = null;
    await _transcription.unloadModel();
    await _settings.setSttEngineIndex(previous.$1);
    await _settings.setGgufModel(previous.$2);
    await _settings.setLanguage(previous.$3);
  }

  Future<void> transcribeHistory(DictationEntry entry, String language) async {
    if (!isAvailable) throw StateError('Finish the current audio task first.');
    externalActivity = 'Transcribing history';
    final previous = _settings.language;
    try {
      final file = await HistoryService.instance.audioFile(entry);
      if (file == null) throw StateError('This entry has no retained audio.');
      await _settings.setLanguage(language);
      final error = await _transcription.ensureLoaded();
      if (error != null) throw StateError(error);
      final text = await _transcription.transcribe(file.path);
      await HistoryService.instance.replace(entry, text,
          model: _transcription.modelLabel, language: language);
    } finally {
      await _settings.setLanguage(previous);
      externalActivity = null;
    }
  }

  Future<void> _remember(String text) async {
    _lastTranscript = text;
    if (_settings.historyEnabled) {
      try {
        HistoryService.instance.retentionDays = _settings.historyRetentionDays;
        await HistoryService.instance.add(text, _transcription.modelLabel,
            language: _settings.language, audio: _historyAudio);
        _historyAudio = null;
      } catch (e) {
        debugPrint('[AuraScribe] History save failed: $e');
      }
    }
  }

  bool paused = false;
  Future<void> setPaused(bool value) async {
    if (value) await cancelDictation();
    paused = value;
    _tray.paused = value;
    await _tray.updateState(_state);
    notifyListeners();
  }

  Future<String?>? _batchPreparation;
  bool _terminalSession = false;
  Future<void> toggle({bool raw = false, bool terminal = false}) async {
    if (paused) return;
    if (_starting || _externalActivity != null) return;
    if (_state != DictationState.recording) _terminalSession = terminal;
    _starting = true;
    final startup = Stopwatch()..start();
    notifyListeners();
    try {
      await _toggle(raw: raw);
      if (_state == DictationState.recording) {
        debugPrint(
            '[AuraScribe] Hotkey to recording ready: ${startup.elapsedMilliseconds} ms');
      }
    } catch (e) {
      _vad.stop();
      _streamingTimer?.cancel();
      await _audioSubscription?.cancel();
      await _audio.cancel();
      await _pcmSpool?.dispose();
      _pcmSpool = null;
      _setError('Dictation could not start: $e');
    } finally {
      _preparing = false;
      if (_state != DictationState.recording) await _restoreSessionSpeech();
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> _toggle({required bool raw}) async {
    debugPrint('[AuraScribe] toggle() called — current state: $_state');
    if (_state == DictationState.recording) {
      debugPrint('[AuraScribe] → stopping recording (manual toggle)');
      await _stopAndProcess();
    } else if (_state == DictationState.idle ||
        _state == DictationState.error) {
      _historyAudio = null;
      _rawSession = raw;
      _cancelStarting = false;
      _audioLevel = 0;
      _liveTranscript = '';
      _liveInserter = LiveTextInserter(_accessibility.insertText);
      final target = await _accessibility.captureDictationTarget();
      if (_startingFromHold && !_held) return;
      _preparing = true;
      notifyListeners();
      await _showDictationIndicator();
      final profiles = await PipelineStore().read();
      _outputSteps =
          raw ? [] : PipelineStore.resolve(profiles, target['bundleId'] ?? '');
      _accessibility.returnToApp =
          _settings.option('returnToApp', fallback: true);
      _accessibility.smartSpacing = _settings.option('smartSpacing');
      _accessibility.terminalPaste =
          _terminalSession || _settings.terminalPaste;
      _accessibility.restoreClipboard = _settings.restoreClipboard;
      final keyboard = await const MethodChannel('com.aurascribe/accessibility')
          .invokeMethod<String>('currentKeyboardSource');
      final profile = profiles
              .where((p) => p.application == target['bundleId'])
              .firstOrNull ??
          profiles.where((p) => p.application == '*').firstOrNull;
      final mapped = profile?.speechModel ?? _settings.keyboardModels[keyboard];
      if (profile?.speechModel != null || profile?.language != null) {
        _sessionSpeech =
            (_settings.sttEngineIndex, _settings.ggufModel, _settings.language);
      }
      if (profile?.language != null) {
        await _settings.setLanguage(profile!.language!);
      }
      if (mapped != null) {
        _grammar.attachSttModel(null);
        if (mapped.startsWith('gguf:')) {
          final id = mapped.substring(5);
          if (id != _settings.ggufModel) await _transcription.unloadModel();
          await _settings.setGgufModel(id);
          await _transcription.switchEngine(SttEngine.gguf);
        } else {
          await _transcription.switchEngine(SttEngine.values.byName(mapped));
        }
      }
      // Streaming engines need their decoder before PCM arrives. GGUF uses
      // a complete WAV: prepare after capture starts, behind the same model
      // lease, and join preparation before final transcription.
      final batch = _transcription.activeEngine == SttEngine.gguf;
      _batchPreparation = null;
      if (!batch && !_transcription.isLoaded) {
        final error = await _transcription.ensureLoaded();
        if (error != null) {
          _setError(error);
          return;
        }
        debugPrint('[AuraScribe] ✅ STT ready (${_transcription.modelLabel})');
      }
      _grammar.attachSttModel(_transcription.sharedGemmaModelForGrammar);
      if (_cancelStarting || (_startingFromHold && !_held)) {
        _setState(DictationState.idle);
        return;
      }
      debugPrint('[AuraScribe] → starting recording');
      await _startRecording();
      if (batch &&
          _state == DictationState.recording &&
          !_transcription.isLoaded) {
        _batchPreparation = _transcription.ensureLoaded().then((error) => error,
            onError: (Object error) => error.toString());
      }
    } else {
      debugPrint('[AuraScribe] ⏭️ Ignoring toggle while busy ($_state)');
    }
  }

  Future<void> _windowTransition = Future.value();
  Future<void> _queueWindow(Future<void> Function() change) {
    _windowTransition = _windowTransition.catchError((Object e) {
      debugPrint('Window transition failed: $e');
    }).then((_) => change());
    return _windowTransition;
  }

  Map<String, Object> get _indicatorData => {
        'top': _settings.indicatorAtTop,
        'notch': _settings.notchIndicator,
        'phase': _preparing ? 'preparing' : _state.name,
        'accessibilityLabel': _preparing
            ? tr('Preparing')
            : _state == DictationState.recording
                ? '${tr('Listening')} · ${tr(recordingHint)}'
                : _state.label,
        'level': _audioLevel,
        'error': _errorMessage ?? '',
        'text': _settings.option('liveText') ? _liveTranscript : '',
      };
  Future<void> _showDictationIndicator() => _queueWindow(() async {
        if (!_settings.showIndicator || _cancelStarting) return;
        _indicatorVisible = true;
        await const MethodChannel('com.aurascribe/accessibility')
            .invokeMethod('showDictationIndicator', _indicatorData);
      });
  void _syncIndicator() {
    if (!_indicatorVisible) return;
    unawaited(const MethodChannel('com.aurascribe/accessibility')
        .invokeMethod<void>('updateDictationIndicator', _indicatorData)
        .catchError((Object e) {
      debugPrint('Indicator update failed: $e');
    }));
  }

  Future<void> _startRecording() async {
    await _audioOutput.begin(_settings.recordingAudio, _settings.duckLevel,
        speakersOnly: _settings.speakersOnly,
        pauseBrowser: _settings.option('pauseBrowser'));
    final axGranted = await _accessibility.hasPermission();
    debugPrint(
        '[AuraScribe] Accessibility permission at record start: $axGranted');

    final useStreaming = _transcription.activeEngine == SttEngine.whisper ||
        _transcription.activeEngine == SttEngine.nemotron ||
        _transcription.activeEngine == SttEngine.moonshine;
    if (useStreaming) {
      await _pcmSpool?.dispose();
      _pcmSpool = await PcmSpool.create(
          await ProjectStorage.instance.directory('tmp/pcm'),
          _settings.maxRecordingSeconds);
      _liveTranscript = '';
      try {
        final stream = await _audio.startStream();
        if (_transcription.supportsTrueStreaming) {
          _transcription.startStream();
        }

        _audioSubscription = stream.listen((chunk) {
          if (_state != DictationState.recording && !_preparing) return;
          var full = false;
          final before = _pcmSpool?.bytes ?? 0;
          try {
            full = _pcmSpool?.append(chunk) ?? false;
          } catch (error) {
            unawaited(_failAudioStream(error));
            return;
          }
          if (_transcription.supportsTrueStreaming) {
            final accepted = (_pcmSpool?.bytes ?? before) - before;
            if (accepted > 0) {
              _transcription
                  .addAudioChunk(Uint8List.sublistView(chunk, 0, accepted));
            }
            _liveTranscript = _transcription.getLiveTranscript();
            if (dictationMode == DictationMode.liveTyping) {
              _enqueueLiveTypingDelta(
                _liveTranscript,
                finalizedFallback: _transcription.getFinalizedTranscript(),
              );
            }
            notifyListeners();
          }
          if (full) unawaited(_stopAndProcess());
        }, onError: (Object error) => unawaited(_failAudioStream(error)));
        _vad.start();

        if (!_transcription.supportsTrueStreaming &&
            dictationMode == DictationMode.liveTyping) {
          _streamingTimer =
              Timer.periodic(const Duration(milliseconds: 800), (timer) async {
            if (_isStreamingTranscribing) return;
            if ((_pcmSpool?.bytes ?? 0) < 1000) return;

            _isStreamingTranscribing = true;
            _partialFinished = Completer<void>();
            try {
              final directory =
                  await ProjectStorage.instance.directory('tmp/pcm');
              final tempFile = await _pcmSpool!.snapshot(File(
                  '${directory.path}/partial-${DateTime.now().microsecondsSinceEpoch}.wav'));
              String text;
              try {
                text = await _transcription.transcribe(tempFile.path);
              } finally {
                if (await tempFile.exists()) await tempFile.delete();
              }

              if (text.isNotEmpty) {
                _liveTranscript = text;
                if (dictationMode == DictationMode.liveTyping) {
                  _enqueueLiveTypingDelta(_liveTranscript);
                }
                notifyListeners();
              }
            } catch (e) {
              debugPrint('[AuraScribe] Streaming transcription error: $e');
            } finally {
              _isStreamingTranscribing = false;
              _partialFinished?.complete();
              _partialFinished = null;
            }
          });
        }
      } catch (e) {
        _vad.stop();
        await _audio.cancel();
        await _pcmSpool?.dispose();
        _pcmSpool = null;
        _setError('Failed to start streaming recorder: $e');
        return;
      }
    } else {
      await _audio.start();
      _vad.start();
    }

    if (_cancelStarting || (_startingFromHold && !_held)) {
      _vad.stop();
      _streamingTimer?.cancel();
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      await _audio.cancel();
      await _audioOutput.end();
      await _pcmSpool?.dispose();
      _pcmSpool = null;
      _setState(DictationState.idle);
      return;
    }
    _preparing = false;
    // Mic icon + sound only after audio capture and STT stream are live so
    // speech at activation time is not lost to startup latency.
    _setState(DictationState.recording);
    unawaited(SoundService.playStart());
    debugPrint('[AuraScribe] Recording + VAD active');
  }

  void _onSilenceDetected() {
    if (!_settings.autoStop || _settings.holdShortcut) return;
    debugPrint('[AuraScribe] VAD silence detected — auto-stopping');
    _stopAndProcess();
  }

  Future<void> _failAudioStream(Object error) async {
    if (_state != DictationState.recording) return;
    _setState(DictationState.transcribing);
    _vad.stop();
    _streamingTimer?.cancel();
    await _audioSubscription?.cancel();
    await _partialFinished?.future;
    await _audio.cancel();
    await _pcmSpool?.dispose();
    _pcmSpool = null;
    _setError('Audio could not be buffered: $error');
  }

  Future<void> _stopAndProcess() async {
    if (_state != DictationState.recording) return;
    try {
      await _finishRecording();
    } catch (error) {
      _setError('Dictation failed: $error');
    } finally {
      await _pcmSpool?.dispose();
      _pcmSpool = null;
      await HistoryService.instance.discardAudio(_historyAudio);
      _historyAudio = null;
      await _restoreSessionSpeech();
    }
  }

  Future<void> _finishRecording() async {
    if (_state != DictationState.recording) {
      debugPrint(
          '[AuraScribe] _stopAndProcess skipped — state is $_state (not recording)');
      return;
    }
    debugPrint('[AuraScribe] _stopAndProcess started');
    _setState(DictationState.transcribing);
    _vad.stop();
    try {
      await _audioOutput.end();
    } catch (e) {
      debugPrint('Audio output restore failed: $e');
    }

    _streamingTimer?.cancel();
    _streamingTimer = null;
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _partialFinished?.future;

    final useStreaming = _transcription.activeEngine == SttEngine.whisper ||
        _transcription.activeEngine == SttEngine.nemotron ||
        _transcription.activeEngine == SttEngine.moonshine;
    String? wavPath;

    if (useStreaming) {
      final byteCount = _pcmSpool?.bytes ?? 0;
      await _audio.stop(); // Stops internal recorder state
      unawaited(SoundService.playStop());

      if (byteCount < 1000) {
        debugPrint('[AuraScribe] ❌ Stream too short, going idle');
        if (_transcription.supportsTrueStreaming) {
          await _transcription.endStream();
        }
        _setState(DictationState.idle);
        return;
      }

      if (!_transcription.supportsTrueStreaming ||
          (_settings.historyEnabled && _settings.keepHistoryAudio)) {
        final directory = await ProjectStorage.instance.directory('tmp/pcm');
        final finalWavFile = await _pcmSpool!.snapshot(File(
            '${directory.path}/final-${DateTime.now().microsecondsSinceEpoch}.wav'));
        wavPath = finalWavFile.path;
        debugPrint('[AuraScribe] WAV saved: $wavPath');
      }
    } else {
      wavPath = await _audio.stop();
      unawaited(SoundService.playStop());
      if (wavPath == null) {
        debugPrint(
            '[AuraScribe] ❌ No WAV file — recorder returned null, going idle');
        _setState(DictationState.idle);
        return;
      }
      debugPrint('[AuraScribe] WAV saved: $wavPath');
    }

    _setState(DictationState.transcribing);
    debugPrint(
      '[AuraScribe] Transcribing… model loaded=${_transcription.isLoaded}, '
      'loading=${_transcription.isLoading}',
    );
    String transcript;
    try {
      final preparationError = await _batchPreparation;
      _batchPreparation = null;
      if (preparationError != null) throw StateError(preparationError);
      if (_transcription.supportsTrueStreaming) {
        transcript = await _transcription.endStream();
      } else {
        if (_settings.option('skipPauses')) {
          final compacted = File(
              '${(await ProjectStorage.instance.directory('tmp')).path}/dictation-compact.wav');
          try {
            await compactPauses(wavPath!, compacted);
            transcript = await _transcription.transcribe(compacted.path);
          } finally {
            if (await compacted.exists()) await compacted.delete();
          }
        } else {
          transcript = await _transcription.transcribe(wavPath!);
        }
      }
    } catch (e, st) {
      debugPrint('[AuraScribe] ❌ Transcription exception: $e\n$st');
      _setError('Transcription failed: $e');
      return;
    } finally {
      if (wavPath != null) {
        if (_settings.historyEnabled &&
            _settings.keepHistoryAudio &&
            _transcriptDestination == null) {
          try {
            _historyAudio = await HistoryService.instance.retainAudio(wavPath);
          } catch (e) {
            debugPrint('History recording could not be retained: $e');
          }
        }
        final wav = File(wavPath);
        if (await wav.exists()) await wav.delete();
      }
    }

    debugPrint(
      '[AuraScribe] Transcript received (${transcript.length} chars)',
    );

    if (_transcriptDestination != null) {
      final destination = _transcriptDestination!;
      _transcriptDestination = null;
      try {
        if (transcript.trim().isNotEmpty) await destination(transcript);
        _setState(DictationState.idle);
      } catch (e) {
        _setError('Could not save the dictated note: $e');
      }
      return;
    }
    if (transcript.isEmpty) {
      debugPrint(
          '[AuraScribe] ⏭️ Empty transcript — skipping grammar & insert');
      _setState(DictationState.idle);
      return;
    }

    if (dictationMode == DictationMode.liveTyping) {
      _enqueueLiveTypingDelta(
        transcript.trim(),
        finalizedFallback: transcript.trim(),
      );
      await _remember(transcript);
      try {
        await _liveInserter.finish();
      } catch (e) {
        _setError('Text insertion failed: $e');
        return;
      }
      _setState(DictationState.idle);
      SoundService.playSuccess();
      return;
    }

    if (transcript.startsWith('[Model not loaded')) {
      debugPrint(
          '[AuraScribe] ⚠️ Placeholder transcript — model was not ready');
    }

    _setState(DictationState.grammarCleanup);
    String cleaned;
    try {
      cleaned = _rawSession ? transcript : await _grammar.clean(transcript);
      debugPrint(
        '[AuraScribe] Grammar done (${cleaned.length} chars)',
      );
    } catch (e, st) {
      debugPrint(
          '[AuraScribe] ⚠️ Grammar failed, using raw transcript: $e\n$st');
      cleaned = transcript;
    }
    if (!_rawSession) {
      cleaned = _settings.applyReplacements(cleaned);
      try {
        cleaned = await OutputProcessor(_grammar.transform)
            .process(cleaned, _outputSteps);
      } catch (e) {
        _setError('Output processing failed; nothing was pasted: $e');
        return;
      }
    }
    if (!_rawSession) {
      cleaned = SpokenText.apply(cleaned,
          language: _settings.language,
          symbols: _settings.option('spokenSymbols'),
          formatting: _settings.option('spokenFormatting'),
          fillers: _settings.option('fillers'),
          spacing: _settings.option('smartSpacing'));
    }
    await _remember(cleaned);
    if (_settings.copyOnly) {
      await Clipboard.setData(ClipboardData(text: cleaned));
      _setState(DictationState.idle);
      return;
    }
    _setState(DictationState.inserting);
    debugPrint(
        '[AuraScribe] Inserting ${cleaned.length} chars into focused app…');
    try {
      final usedAx = await _accessibility.insertText(cleaned);
      _usedFallback = !usedAx;
      if (usedAx) {
        debugPrint('[AuraScribe] ✅ Insert via Accessibility API (AX)');
      } else {
        debugPrint(
          '[AuraScribe] ⚠️ Insert used clipboard + ⌘V fallback '
          '(check Accessibility permission & focused text field)',
        );
      }
    } catch (e, st) {
      debugPrint('[AuraScribe] ❌ Insert exception: $e\n$st');
      _setError('Text insertion failed: $e');
      return;
    }

    debugPrint('[AuraScribe] ✅ Dictation pipeline complete');
    _setState(DictationState.idle);
    SoundService.playSuccess();
  }

  // ── Smart Commands (Phase 5) ───────────────────────────

  Future<void> triggerSmartCommand() async {
    if (_starting ||
        _externalActivity != null ||
        _smartCommandRunning ||
        _state != DictationState.idle) {
      return;
    }
    debugPrint('[AuraScribe] triggerSmartCommand() called');

    // 1. Grab selected text natively
    final text = await _accessibility.copySelectedText();
    if (text == null || text.trim().isEmpty) {
      debugPrint('[AuraScribe] Grabbed selected text is empty, skipping HUD');
      _setError('No text selected! Highlight text first.');
      Timer(const Duration(milliseconds: 2500), () {
        if (_state == DictationState.error) {
          _setState(DictationState.idle);
        }
      });
      return;
    }

    _selectedTextToProcess = text;
    _smartCommandError = null;
    debugPrint('[AuraScribe] Selected text captured');

    // 2. Change view
    _currentView = AppView.smartCommands;
    notifyListeners();

    // 3. Resize and display HUD
    await windowManager.setMinimumSize(Size.zero);
    await windowManager.setSize(const Size(420, 360));
    await windowManager.setResizable(false);
    await windowManager.setHasShadow(true);
    await windowManager.center();
    setSettingsVisible(true);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> closeSmartCommandHUD() async {
    debugPrint('[AuraScribe] closeSmartCommandHUD() called');
    await hideSettingsWindow();
    await windowManager.setSize(const Size(960, 720));
    await windowManager.setMinimumSize(const Size(680, 520));
    await windowManager.setResizable(true);
    _currentView = AppView.settings;
    _selectedTextToProcess = null;
    _smartCommandError = null;
    notifyListeners();
  }

  Future<void> executeSmartCommand(SmartCommandType type,
      {String? customPrompt}) async {
    debugPrint(
        '[AuraScribe][Orchestrator] executeSmartCommand entry: type = $type, customPrompt = $customPrompt');
    if (_selectedTextToProcess == null ||
        _selectedTextToProcess!.trim().isEmpty) {
      debugPrint(
          '[AuraScribe][Orchestrator] No selected text to process (is null or empty), closing');
      await closeSmartCommandHUD();
      return;
    }

    _smartCommandRunning = true;
    _smartCommandError = null;
    notifyListeners();

    final text = _selectedTextToProcess!;
    debugPrint(
        '[AuraScribe][Orchestrator] Executing Smart Command $type on target text length: ${text.length} chars.');

    String result;
    try {
      debugPrint('[AuraScribe][Orchestrator] Calling _smartCommand.execute...');
      result = await _smartCommand.execute(
        type: type,
        text: text,
        customPrompt: customPrompt,
      );
      debugPrint(
          '[AuraScribe][Orchestrator] _smartCommand.execute completed. Result length: ${result.length} chars.');
    } catch (e, stack) {
      debugPrint(
          '[AuraScribe][Orchestrator] Smart Command execution crashed: $e\n$stack');
      result = 'Error executing command: $e';
    }

    _smartCommandRunning = false;
    notifyListeners();

    if (result.startsWith('Error:') || result.startsWith('Error executing')) {
      debugPrint(
          '[AuraScribe][Orchestrator] Command resulted in error: $result');
      _smartCommandError = result;
      notifyListeners();
      SoundService.playError();
      return;
    }

    debugPrint(
        '[AuraScribe][Orchestrator] Closing Smart Command HUD to restore target app focus...');
    await closeSmartCommandHUD();

    debugPrint(
        '[AuraScribe][Orchestrator] Replacing selected text in target app...');
    final usedAx = await _accessibility.replaceSelectedText(result);
    debugPrint(
        '[AuraScribe][Orchestrator] replaceSelectedText outcome (usedAx) = $usedAx');
    if (usedAx) {
      debugPrint(
          '[AuraScribe][Orchestrator] Text replacement via accessibility succeeded.');
      SoundService.playSuccess();
    } else {
      debugPrint(
        '[AuraScribe][Orchestrator] Text replacement used clipboard paste fallback.',
      );
      SoundService.playSuccess();
    }
  }

  Future<void> showSettings() async {
    if (_indicatorVisible) await _hideHudOnlyWindow();
    _currentView = AppView.settings;
    _selectedTextToProcess = null;
    notifyListeners();

    await windowManager.setMinimumSize(const Size(680, 520));
    await windowManager.setSize(const Size(960, 720));
    await windowManager.setResizable(true);
    await windowManager.center();
    setSettingsVisible(true);
    await windowManager.show();
    await windowManager.focus();
  }

  void _setState(DictationState newState) {
    if (_state != newState) {
      debugPrint('[AuraScribe] State: $_state → $newState');
    }
    ActivityLog.instance.add('dictation state',
        model: _transcription.modelLabel, state: newState.name);
    _feedbackTimer?.cancel();
    if (newState == DictationState.idle) {
      _transcriptDestination = null;
      unawaited(_accessibility.releaseDictationTarget());
    }
    _state = newState;
    _errorMessage = null;
    _tray.updateState(newState);
    _syncIndicator();
    notifyListeners();

    if (newState == DictationState.idle && _indicatorVisible) {
      _hideHudOnlyWindow();
    }
  }

  Future<void> _hideHudOnlyWindow() => _queueWindow(() async {
        _indicatorVisible = false;
        await const MethodChannel('com.aurascribe/accessibility')
            .invokeMethod<void>('hideDictationIndicator');
      });

  void _enqueueLiveTypingDelta(String liveText, {String? finalizedFallback}) {
    _liveInserter.enqueue(liveText, finalizedFallback: finalizedFallback);
  }

  void _setError(String msg) {
    _transcriptDestination = null;
    unawaited(_audioOutput.end().catchError((Object e) {
      debugPrint('Audio restore failed: $e');
    }));
    debugPrint('[AuraScribe] ❌ Error state: $msg');
    ActivityLog.instance.add('dictation failed',
        model: _transcription.modelLabel, state: 'error');
    _preparing = false;
    _state = DictationState.error;
    _errorMessage = msg;
    _tray.updateState(DictationState.error);
    _syncIndicator();
    SoundService.playError();
    notifyListeners();

    if (_indicatorVisible) {
      _feedbackTimer?.cancel();
      _feedbackTimer = Timer(const Duration(seconds: 6), () {
        if (_state == DictationState.error) {
          _setState(DictationState.idle);
        }
      });
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _disposing = true;
    settingsTreeVisible.dispose();
    _transcription.memory?.setActive(this, false);
    unawaited(_pcmSpool?.dispose());
    _feedbackTimer?.cancel();
    unawaited(_audioOutput.end());
    unawaited(_hideHudOnlyWindow());
    _meetings?.dispose();
    _voiceFilter?.dispose();
    _updates?.dispose();
    unawaited(_control?.close());
    _streamingTimer?.cancel();
    _audioSubscription?.cancel();
    _audio.dispose();
    _vad.dispose();
    super.dispose();
  }
}
