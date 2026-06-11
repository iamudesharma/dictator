import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import '../shared/dictation_state.dart';
import '../shared/dictation_mode.dart';
import '../audio/audio_service.dart';
import '../vad/vad_service.dart';
import '../transcription/transcription_service.dart';
import '../grammar/grammar_service.dart';
import '../accessibility/accessibility_service.dart';
import '../tray/tray_service.dart';
import '../shared/sound_service.dart';
import '../shared/stt_engine.dart';
import '../shared/wav_header_helper.dart';
import '../grammar/smart_command_service.dart';
import '../settings/settings_service.dart';

enum AppView {
  settings,
  smartCommands,
}

/// Central state machine for the dictation loop.
/// Coordinates: recording → VAD → transcribe → grammar → insert
class DictationOrchestrator extends ChangeNotifier {
  final AudioService _audio;
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
  final List<int> _audioBuffer = [];
  Timer? _streamingTimer;
  bool _isStreamingTranscribing = false;
  String _liveTranscript = '';
  bool _isHudOnlyWindow = false;
  /// Exact text already inserted into the focused field during this session.
  String _insertedLiveText = '';
  Future<void> _insertChain = Future.value();

  bool get isHudOnly => _isHudOnlyWindow;
  DictationMode get dictationMode => _settings.dictationMode;
  DictationState get state => _state;
  String? get lastTranscript => _lastTranscript;
  String? get errorMessage => _errorMessage;
  bool get usedFallback => _usedFallback;

  AppView get currentView => _currentView;
  bool get smartCommandRunning => _smartCommandRunning;
  String? get smartCommandError => _smartCommandError;
  String get liveTranscript => _liveTranscript;

  DictationOrchestrator({
    required AudioService audio,
    required VadService vad,
    required TranscriptionService transcription,
    required GrammarService grammar,
    required AccessibilityService accessibility,
    required TrayService tray,
    required SmartCommandService smartCommand,
    required SettingsService settings,
  })  : _audio = audio,
        _vad = vad,
        _transcription = transcription,
        _grammar = grammar,
        _accessibility = accessibility,
        _tray = tray,
        _smartCommand = smartCommand,
        _settings = settings {
    _vad.onSilenceDetected = _onSilenceDetected;
  }

  /// Called by HotkeyService or tray menu tap.
  Future<void> toggle() async {
    debugPrint('[Dictator] toggle() called — current state: $_state');
    if (_state == DictationState.recording) {
      debugPrint('[Dictator] → stopping recording (manual toggle)');
      await _stopAndProcess();
    } else if (_state == DictationState.idle || _state == DictationState.error) {
      // Lazily load the STT model on first use so the app starts instantly
      // and stays at minimal idle RAM. Attach shared Gemma model to grammar
      // once STT is ready (saves a 270 MB download on Gemma path).
      if (!_transcription.isLoaded) {
        final error = await _transcription.ensureLoaded();
        if (error != null) {
          _setError(error);
          return;
        }
        _grammar.attachSttModel(_transcription.sharedGemmaModelForGrammar);
        debugPrint('[Dictator] ✅ STT ready (${_transcription.modelLabel})');
      }
      debugPrint('[Dictator] → starting recording');
      await _startRecording();
    } else {
      debugPrint('[Dictator] ⏭️ Ignoring toggle while busy ($_state)');
    }
  }

  Future<void> _startRecording() async {
    final axGranted = await _accessibility.hasPermission();
    debugPrint('[Dictator] Accessibility permission at record start: $axGranted');

    final isVisible = await windowManager.isVisible();
    final showHudOverlay = _settings.dictationMode != DictationMode.liveTyping;
    if (!isVisible && showHudOverlay) {
      _isHudOnlyWindow = true;
      notifyListeners();
      await windowManager.setBackgroundColor(Colors.transparent);
      await windowManager.setHasShadow(false);
      await windowManager.setIgnoreMouseEvents(true);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSize(const Size(600, 250));
      await windowManager.center();
      await windowManager.show(inactive: true);
    } else {
      _isHudOnlyWindow = false;
    }

    final useStreaming = _transcription.activeEngine == SttEngine.whisper ||
        _transcription.activeEngine == SttEngine.nemotron;
    if (useStreaming) {
      _audioBuffer.clear();
      _liveTranscript = '';
      _insertedLiveText = '';
      _insertChain = Future.value();
      try {
        final stream = await _audio.startStream();
        if (_transcription.supportsTrueStreaming) {
          _transcription.startStream();
        }

        _audioSubscription = stream.listen((chunk) {
          _audioBuffer.addAll(chunk);
          if (_transcription.supportsTrueStreaming) {
            _transcription.addAudioChunk(chunk);
            _liveTranscript = _transcription.getLiveTranscript();
            if (_settings.dictationMode == DictationMode.liveTyping) {
              _enqueueLiveTypingDelta(
                _liveTranscript,
                finalizedFallback: _transcription.getFinalizedTranscript(),
              );
            }
            notifyListeners();
          }
        });
        _vad.start();

        if (!_transcription.supportsTrueStreaming) {
          _streamingTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) async {
            if (_isStreamingTranscribing) return;
            if (_audioBuffer.isEmpty) return;

            _isStreamingTranscribing = true;
            try {
              final pcmBytes = Uint8List.fromList(_audioBuffer);
              if (pcmBytes.length < 1000) {
                _isStreamingTranscribing = false;
                return;
              }

              final wavBytes = WavHeaderHelper.buildHeader(pcmBytes.length);
              final fullWav = Uint8List(wavBytes.length + pcmBytes.length);
              fullWav.setRange(0, wavBytes.length, wavBytes);
              fullWav.setRange(wavBytes.length, fullWav.length, pcmBytes);

              final tempDir = await getTemporaryDirectory();
              final tempFile = File(p.join(tempDir.path, 'dictation_stream_tmp.wav'));
              await tempFile.writeAsBytes(fullWav);

              final text = await _transcription.transcribe(tempFile.path);
              if (text.isNotEmpty) {
                _liveTranscript = text;
                if (_settings.dictationMode == DictationMode.liveTyping) {
                  _enqueueLiveTypingDelta(_liveTranscript);
                }
                notifyListeners();
              }
            } catch (e) {
              debugPrint('[Dictator] Streaming transcription error: $e');
            } finally {
              _isStreamingTranscribing = false;
            }
          });
        }
      } catch (e) {
        _setError('Failed to start streaming recorder: $e');
        return;
      }
    } else {
      await _audio.start();
      _vad.start();
    }

    // Mic icon + sound only after audio capture and STT stream are live so
    // speech at activation time is not lost to startup latency.
    _setState(DictationState.recording);
    unawaited(SoundService.playStart());
    debugPrint('[Dictator] Recording + VAD active');
  }

  void _onSilenceDetected() {
    debugPrint('[Dictator] VAD silence detected — auto-stopping');
    _stopAndProcess();
  }

  Future<void> _stopAndProcess() async {
    if (_state != DictationState.recording) {
      debugPrint('[Dictator] _stopAndProcess skipped — state is $_state (not recording)');
      return;
    }
    debugPrint('[Dictator] _stopAndProcess started');
    _vad.stop();

    _streamingTimer?.cancel();
    _streamingTimer = null;
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    final useStreaming = _transcription.activeEngine == SttEngine.whisper ||
        _transcription.activeEngine == SttEngine.nemotron;
    String? wavPath;

    if (useStreaming) {
      final pcmBytes = Uint8List.fromList(_audioBuffer);
      _audioBuffer.clear();
      await _audio.stop(); // Stops internal recorder state

      if (pcmBytes.length < 1000) {
        debugPrint('[Dictator] ❌ Stream too short, going idle');
        if (_transcription.supportsTrueStreaming) {
          await _transcription.endStream();
        }
        _setState(DictationState.idle);
        return;
      }
      await SoundService.playStop();

      if (!_transcription.supportsTrueStreaming) {
        final wavBytes = WavHeaderHelper.buildHeader(pcmBytes.length);
        final fullWav = Uint8List(wavBytes.length + pcmBytes.length);
        fullWav.setRange(0, wavBytes.length, wavBytes);
        fullWav.setRange(wavBytes.length, fullWav.length, pcmBytes);

        final tempDir = await getTemporaryDirectory();
        final finalWavFile = File(p.join(tempDir.path, 'dictation_final_${DateTime.now().millisecondsSinceEpoch}.wav'));
        await finalWavFile.writeAsBytes(fullWav);
        wavPath = finalWavFile.path;
        debugPrint('[Dictator] WAV saved: $wavPath');
      }
    } else {
      wavPath = await _audio.stop();
      if (wavPath == null) {
        debugPrint('[Dictator] ❌ No WAV file — recorder returned null, going idle');
        _setState(DictationState.idle);
        return;
      }
      await SoundService.playStop();
      debugPrint('[Dictator] WAV saved: $wavPath');
    }

    _setState(DictationState.transcribing);
    debugPrint(
      '[Dictator] Transcribing… model loaded=${_transcription.isLoaded}, '
      'loading=${_transcription.isLoading}',
    );
    String transcript;
    try {
      if (_transcription.supportsTrueStreaming) {
        transcript = await _transcription.endStream();
      } else {
        transcript = await _transcription.transcribe(wavPath!);
      }
    } catch (e, st) {
      debugPrint('[Dictator] ❌ Transcription exception: $e\n$st');
      _setError('Transcription failed: $e');
      return;
    }

    debugPrint(
      '[Dictator] Transcript received (${transcript.length} chars): '
      '"${transcript.length > 120 ? '${transcript.substring(0, 120)}…' : transcript}"',
    );

    if (transcript.isEmpty) {
      debugPrint('[Dictator] ⏭️ Empty transcript — skipping grammar & insert');
      _setState(DictationState.idle);
      return;
    }

    if (_settings.dictationMode == DictationMode.liveTyping) {
      _enqueueLiveTypingDelta(
        transcript.trim(),
        finalizedFallback: transcript.trim(),
      );
      await _insertChain;
      _lastTranscript = transcript;
      _setState(DictationState.idle);
      SoundService.playSuccess();
      return;
    }

    if (transcript.startsWith('[Model not loaded')) {
      debugPrint('[Dictator] ⚠️ Placeholder transcript — model was not ready');
    }

    _setState(DictationState.grammarCleanup);
    String cleaned;
    try {
      cleaned = await _grammar.clean(transcript);
      debugPrint(
        '[Dictator] Grammar done (${cleaned.length} chars): '
        '"${cleaned.length > 120 ? '${cleaned.substring(0, 120)}…' : cleaned}"',
      );
    } catch (e, st) {
      debugPrint('[Dictator] ⚠️ Grammar failed, using raw transcript: $e\n$st');
      cleaned = transcript;
    }
    _lastTranscript = cleaned;

    _setState(DictationState.inserting);
    debugPrint('[Dictator] Inserting ${cleaned.length} chars into focused app…');
    try {
      final usedAx = await _accessibility.insertText(cleaned);
      _usedFallback = !usedAx;
      if (usedAx) {
        debugPrint('[Dictator] ✅ Insert via Accessibility API (AX)');
      } else {
        debugPrint(
          '[Dictator] ⚠️ Insert used clipboard + ⌘V fallback '
          '(check Accessibility permission & focused text field)',
        );
      }
    } catch (e, st) {
      debugPrint('[Dictator] ❌ Insert exception: $e\n$st');
      _setError('Text insertion failed: $e');
      return;
    }

    debugPrint('[Dictator] ✅ Dictation pipeline complete');
    _setState(DictationState.idle);
    SoundService.playSuccess();
  }

  // ── Smart Commands (Phase 5) ───────────────────────────

  Future<void> triggerSmartCommand() async {
    debugPrint('[Dictator] triggerSmartCommand() called');

    // 1. Grab selected text natively
    final text = await _accessibility.copySelectedText();
    if (text == null || text.trim().isEmpty) {
      debugPrint('[Dictator] Grabbed selected text is empty, skipping HUD');
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
    debugPrint('[Dictator] Grabbed selected text: "$_selectedTextToProcess"');

    // 2. Change view
    _currentView = AppView.smartCommands;
    notifyListeners();

    // 3. Resize and display HUD
    await windowManager.setSize(const Size(380, 320));
    await windowManager.setResizable(false);
    await windowManager.setHasShadow(true);
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> closeSmartCommandHUD() async {
    debugPrint('[Dictator] closeSmartCommandHUD() called');
    await windowManager.hide();
    await windowManager.setSize(const Size(480, 640));
    await windowManager.setResizable(true);
    _currentView = AppView.settings;
    _selectedTextToProcess = null;
    _smartCommandError = null;
    notifyListeners();
  }

  Future<void> executeSmartCommand(SmartCommandType type, {String? customPrompt}) async {
    debugPrint('[Dictator][Orchestrator] executeSmartCommand entry: type = $type, customPrompt = $customPrompt');
    if (_selectedTextToProcess == null || _selectedTextToProcess!.trim().isEmpty) {
      debugPrint('[Dictator][Orchestrator] No selected text to process (is null or empty), closing');
      await closeSmartCommandHUD();
      return;
    }

    _smartCommandRunning = true;
    _smartCommandError = null;
    notifyListeners();

    final text = _selectedTextToProcess!;
    debugPrint('[Dictator][Orchestrator] Executing Smart Command $type on target text length: ${text.length} chars. Text content: "$text"');

    String result;
    try {
      debugPrint('[Dictator][Orchestrator] Calling _smartCommand.execute...');
      result = await _smartCommand.execute(
        type: type,
        text: text,
        customPrompt: customPrompt,
      );
      debugPrint('[Dictator][Orchestrator] _smartCommand.execute completed. Result length: ${result.length} chars. Result content: "$result"');
    } catch (e, stack) {
      debugPrint('[Dictator][Orchestrator] Smart Command execution crashed: $e\n$stack');
      result = 'Error executing command: $e';
    }

    _smartCommandRunning = false;
    notifyListeners();

    if (result.startsWith('Error:') || result.startsWith('Error executing')) {
      debugPrint('[Dictator][Orchestrator] Command resulted in error: $result');
      _smartCommandError = result;
      notifyListeners();
      SoundService.playError();
      return;
    }

    debugPrint('[Dictator][Orchestrator] Closing Smart Command HUD to restore target app focus...');
    await closeSmartCommandHUD();

    debugPrint('[Dictator][Orchestrator] Replacing selected text in target app...');
    final usedAx = await _accessibility.replaceSelectedText(result);
    debugPrint('[Dictator][Orchestrator] replaceSelectedText outcome (usedAx) = $usedAx');
    if (usedAx) {
      debugPrint('[Dictator][Orchestrator] Text replacement via accessibility succeeded.');
      SoundService.playSuccess();
    } else {
      debugPrint(
        '[Dictator][Orchestrator] Text replacement used clipboard paste fallback.',
      );
      SoundService.playSuccess();
    }
  }

  Future<void> showSettings() async {
    _currentView = AppView.settings;
    _selectedTextToProcess = null;
    notifyListeners();

    await windowManager.setSize(const Size(480, 640));
    await windowManager.setResizable(true);
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  }

  void _setState(DictationState newState) {
    if (_state != newState) {
      debugPrint('[Dictator] State: $_state → $newState');
    }
    _state = newState;
    _errorMessage = null;
    _tray.updateState(newState);
    notifyListeners();

    if (newState == DictationState.idle && _isHudOnlyWindow) {
      _hideHudOnlyWindow();
    }
  }

  Future<void> _hideHudOnlyWindow() async {
    _isHudOnlyWindow = false;
    notifyListeners();
    await windowManager.hide();
    
    // Restore default settings window properties
    await windowManager.setBackgroundColor(const Color(0xFF1C1C1E));
    await windowManager.setHasShadow(true);
    await windowManager.setIgnoreMouseEvents(false);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSize(const Size(480, 640));
    await windowManager.setResizable(true);
  }

  /// Queues prefix-delta inserts for live typing. Updates [_insertedLiveText]
  /// synchronously so rapid audio chunks cannot enqueue the same text twice.
  ///
  /// Sherpa-onnx partial [getResult] hypotheses can revise earlier tokens; only
  /// append when the transcript still starts with what we already inserted.
  /// When a partial revision breaks the prefix, fall back to stable finalized
  /// segments (after [isEndpoint] + [reset]) per the sherpa-onnx streaming pattern.
  void _enqueueLiveTypingDelta(
    String liveText, {
    String? finalizedFallback,
  }) {
    final candidate = liveText.trim();
    if (candidate.isEmpty) return;

    String? delta;
    String nextInserted = _insertedLiveText;

    if (candidate.startsWith(_insertedLiveText)) {
      delta = candidate.substring(_insertedLiveText.length);
      nextInserted = candidate;
    } else if (finalizedFallback != null) {
      final stable = finalizedFallback.trim();
      if (stable.isNotEmpty && stable.startsWith(_insertedLiveText)) {
        delta = stable.substring(_insertedLiveText.length);
        nextInserted = stable;
      }
    }

    if (delta == null || delta.isEmpty) return;

    _insertedLiveText = nextInserted;
    _insertChain = _insertChain.then((_) => _accessibility.insertText(delta!));
  }

  void _setError(String msg) {
    debugPrint('[Dictator] ❌ Error state: $msg');
    _state = DictationState.error;
    _errorMessage = msg;
    _tray.updateState(DictationState.error);
    SoundService.playError();
    notifyListeners();

    if (_isHudOnlyWindow) {
      Timer(const Duration(milliseconds: 3000), () {
        if (_state == DictationState.error) {
          _setState(DictationState.idle);
        }
      });
    }
  }

  @override
  void dispose() {
    _streamingTimer?.cancel();
    _audioSubscription?.cancel();
    _audio.dispose();
    _vad.dispose();
    super.dispose();
  }
}
