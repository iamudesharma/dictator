import 'dart:convert';
import '../hotkeys/shortcut_binding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../shared/dictation_mode.dart';

class SettingsService {
  static const _keyHotkeyType = 'hotkey_type';
  static const _keyVadThreshold = 'vad_threshold_dbfs';
  static const _keyVadSilenceDuration = 'vad_silence_duration_ms';
  static const _keyGrammarEnabled = 'grammar_enabled';
  static const _keyFallbackNotify = 'fallback_notify';
  static const _keyMaxRecordingSeconds = 'max_recording_seconds';
  static const _keyWhisperModel = 'whisper_model';
  static const _keySttEngine = 'stt_engine';
  static const _keyDictationMode = 'dictation_mode';
  static const _keyHfToken = 'hf_token';

  DictationMode get dictationMode {
    final index = _prefs.getInt(_keyDictationMode) ?? 0;
    if (index < 0 || index >= DictationMode.values.length) {
      return DictationMode.liveTyping;
    }
    return DictationMode.values[index];
  }

  Future<void> setDictationMode(DictationMode mode) =>
      _prefs.setInt(_keyDictationMode, mode.index);

  /// 0 = Whisper (default — low RAM, ~75-500 MB), 1 = Gemma 4 E2B (16 GB+ Macs)
  int get sttEngineIndex => _prefs.getInt(_keySttEngine) ?? 0;
  Future<void> setSttEngineIndex(int index) =>
      _prefs.setInt(_keySttEngine, index);

  /// 0 = tiny.en (fast), 1 = base, 2 = small (accurate, slower)

  late SharedPreferences _prefs;
  static const _channel = MethodChannel('com.aurascribe/accessibility');
  String _hfToken = '';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _hfToken = await _channel.invokeMethod<String>('readHfToken') ?? '';
    final legacy = _prefs.getString(_keyHfToken) ?? '';
    if (_hfToken.isEmpty && legacy.isNotEmpty) await setHfToken(legacy);
    if (legacy.isNotEmpty) await _prefs.remove(_keyHfToken);
  }

  // 0 = double ctrl, 1 = triple ctrl, 2 = legacy chord, 3 = custom, 4 = Option+T, 5 = Option hold.
  int get hotkeyType => _prefs.getInt(_keyHotkeyType) ?? 5;
  Future<void> setHotkeyType(int type) => _prefs.setInt(_keyHotkeyType, type);

  // VAD threshold in dBFS (negative number, default -35)
  double get vadThreshold => _prefs.getDouble(_keyVadThreshold) ?? -35.0;
  Future<void> setVadThreshold(double v) =>
      _prefs.setDouble(_keyVadThreshold, v);

  // VAD silence duration in ms (default 1500)
  int get vadSilenceDuration => _prefs.getInt(_keyVadSilenceDuration) ?? 1500;
  Future<void> setVadSilenceDuration(int ms) =>
      _prefs.setInt(_keyVadSilenceDuration, ms);

  // Grammar cleanup enabled (second LLM pass — uses extra RAM)
  bool get grammarEnabled => _prefs.getBool(_keyGrammarEnabled) ?? false;
  Future<void> setGrammarEnabled(bool v) =>
      _prefs.setBool(_keyGrammarEnabled, v);

  // Hard cap on recording length to limit audio tensor size (default 45s)
  int get maxRecordingSeconds => _prefs.getInt(_keyMaxRecordingSeconds) ?? 45;
  Future<void> setMaxRecordingSeconds(int seconds) =>
      _prefs.setInt(_keyMaxRecordingSeconds, seconds);

  // Notify when falling back to clipboard paste
  bool get fallbackNotify => _prefs.getBool(_keyFallbackNotify) ?? true;
  Future<void> setFallbackNotify(bool v) =>
      _prefs.setBool(_keyFallbackNotify, v);

  int get whisperModelIndex => _prefs.getInt(_keyWhisperModel) ?? 0;
  Future<void> setWhisperModelIndex(int index) =>
      _prefs.setInt(_keyWhisperModel, index);

  String get hfToken => _hfToken;
  Future<void> setHfToken(String token) async {
    await _channel.invokeMethod<void>('writeHfToken', token.trim());
    _hfToken = token.trim();
  }

  bool get unloadIdleModels => _prefs.getBool('unload_idle_models') ?? true;
  int get modelIdleSeconds =>
      (_prefs.getInt('model_idle_seconds') ?? 60).clamp(15, 3600);
  Future<void> setUnloadIdleModels(bool value) =>
      _prefs.setBool('unload_idle_models', value);
  Future<void> setModelIdleSeconds(int value) =>
      _prefs.setInt('model_idle_seconds', value.clamp(15, 3600));

  bool get preloadModel => _prefs.getBool('preload_model') ?? false;
  Future<void> setPreloadModel(bool value) =>
      _prefs.setBool('preload_model', value);
  bool get showIndicator => _prefs.getBool('show_indicator') ?? true;
  Future<void> setShowIndicator(bool value) =>
      _prefs.setBool('show_indicator', value);
  bool get indicatorAtTop => _prefs.getBool('indicator_at_top') ?? true;
  Future<void> setIndicatorAtTop(bool value) =>
      _prefs.setBool('indicator_at_top', value);
  bool get holdShortcut => _prefs.getBool('hold_shortcut') ?? (hotkeyType >= 2);
  Future<void> setHoldShortcut(bool value) =>
      _prefs.setBool('hold_shortcut', value);
  bool get autoStop => _prefs.getBool('auto_stop') ?? true;
  Future<void> setAutoStop(bool value) => _prefs.setBool('auto_stop', value);
  bool get historyEnabled => _prefs.getBool('history_enabled') ?? false;
  Future<void> setHistoryEnabled(bool value) =>
      _prefs.setBool('history_enabled', value);
  double get soundVolume =>
      (_prefs.getDouble('sound_volume') ?? 0.5).clamp(0, 1);
  Future<void> setSoundVolume(double value) =>
      _prefs.setDouble('sound_volume', value);
  String get microphoneId => _prefs.getString('microphone_id') ?? '';
  String get microphoneLabel =>
      _prefs.getString('microphone_label') ?? 'System default';
  Future<void> setMicrophone(String id, String label) async {
    await _prefs.setString('microphone_id', id);
    await _prefs.setString('microphone_label', label);
  }

  String get language => _prefs.getString('language') ?? 'en';
  Future<void> setLanguage(String value) => _prefs.setString('language', value);
  String get vocabulary => _prefs.getString('vocabulary') ?? '';
  Future<void> setVocabulary(String value) =>
      _prefs.setString('vocabulary', value);
  String applyReplacements(String text) {
    for (final line in vocabulary.split('\n')) {
      final split = line.indexOf('=');
      if (split <= 0) continue;
      final from = line.substring(0, split).trim();
      final to = line.substring(split + 1).trim();
      if (from.isEmpty || to.isEmpty) continue;
      text = text.replaceAllMapped(
          RegExp('(?<![a-zA-Z0-9_])${RegExp.escape(from)}(?![a-zA-Z0-9_])',
              caseSensitive: false),
          (_) => to);
    }
    return text;
  }

  Map<ShortcutAction, ShortcutBinding> get shortcuts {
    final values = ShortcutBinding.defaults;
    try {
      final data = jsonDecode(_prefs.getString('shortcuts') ?? '{}')
          as Map<String, dynamic>;
      for (final entry in data.entries) {
        final action = ShortcutAction.values.byName(entry.key);
        final binding = ShortcutBinding.fromJson(
            Map<String, dynamic>.from(entry.value as Map));
        binding.validate(allowModifierOnly: action == ShortcutAction.dictation);
        values[action] = binding;
      }
    } catch (_) {/* Retain known defaults for invalid persisted values. */}
    if (hotkeyType == 2) {
      values[ShortcutAction.dictation] = ShortcutBinding.legacyDictation;
    }
    if (hotkeyType == 4) {
      values[ShortcutAction.dictation] = ShortcutBinding.optionChord;
    }
    if (hotkeyType == 5) {
      values[ShortcutAction.dictation] =
          ShortcutBinding.defaults[ShortcutAction.dictation]!;
    }
    return values;
  }

  Future<void> setShortcuts(Map<ShortcutAction, ShortcutBinding> values) =>
      _prefs.setString(
          'shortcuts',
          jsonEncode(values
              .map((action, value) => MapEntry(action.name, value.toJson()))));

  String get recordingAudio =>
      _prefs.getString('recording_audio') ?? 'unchanged';
  Future<void> setRecordingAudio(String value) =>
      _prefs.setString('recording_audio', value);
  double get duckLevel => (_prefs.getDouble('duck_level') ?? 0.2).clamp(0, 1);
  Future<void> setDuckLevel(double value) =>
      _prefs.setDouble('duck_level', value);
  bool get terminalPaste => _prefs.getBool('terminal_paste') ?? false;
  Future<void> setTerminalPaste(bool value) =>
      _prefs.setBool('terminal_paste', value);
  bool get restoreClipboard => _prefs.getBool('restore_clipboard') ?? true;
  Future<void> setRestoreClipboard(bool value) =>
      _prefs.setBool('restore_clipboard', value);

  String get ggufModel => _prefs.getString('gguf_model') ?? 'parakeet_v3';
  Future<void> setGgufModel(String value) =>
      _prefs.setString('gguf_model', value);
  String get decoderVocabulary => _prefs.getString('decoder_vocabulary') ?? '';
  Future<void> setDecoderVocabulary(String value) =>
      _prefs.setString('decoder_vocabulary', value);

  Map<String, String> get keyboardModels {
    try {
      return Map<String, String>.from(
          jsonDecode(_prefs.getString('keyboard_models') ?? '{}') as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> setKeyboardModel(String source, String model) async {
    final values = keyboardModels;
    if (model.isEmpty) {
      values.remove(source);
    } else {
      values[source] = model;
    }
    await _prefs.setString('keyboard_models', jsonEncode(values));
  }

  int get meetingRetentionDays => _prefs.getInt('meeting_retention_days') ?? 0;
  Future<void> setMeetingRetentionDays(int value) =>
      _prefs.setInt('meeting_retention_days', value);

  String get voiceMicrophoneId => _prefs.getString('voice_microphone') ?? '';
  Future<void> setVoiceMicrophoneId(String v) =>
      _prefs.setString('voice_microphone', v);
  bool get voiceProcessing => _prefs.getBool('voice_processing') ?? true;
  Future<void> setVoiceProcessing(bool v) =>
      _prefs.setBool('voice_processing', v);
  bool get voiceAutomaticGain => _prefs.getBool('voice_agc') ?? true;
  Future<void> setVoiceAutomaticGain(bool v) => _prefs.setBool('voice_agc', v);
  double get voiceGain => (_prefs.getDouble('voice_gain') ?? 1).clamp(0.2, 3);
  Future<void> setVoiceGain(double v) => _prefs.setDouble('voice_gain', v);
  double get voiceGateDb =>
      (_prefs.getDouble('voice_gate') ?? -55).clamp(-90, -20);
  Future<void> setVoiceGateDb(double v) => _prefs.setDouble('voice_gate', v);
  bool get voiceMonitor => _prefs.getBool('voice_monitor') ?? false;
  Future<void> setVoiceMonitor(bool v) => _prefs.setBool('voice_monitor', v);

  bool get automaticUpdates => _prefs.getBool('automatic_updates') ?? false;
  Future<void> setAutomaticUpdates(bool v) =>
      _prefs.setBool('automatic_updates', v);
  bool get downloadUpdates => _prefs.getBool('download_updates') ?? false;
  Future<void> setDownloadUpdates(bool v) =>
      _prefs.setBool('download_updates', v);
  bool get installUpdates => _prefs.getBool('install_updates') ?? false;
  Future<void> setInstallUpdates(bool v) =>
      _prefs.setBool('install_updates', v);
}
