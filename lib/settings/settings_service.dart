import 'package:shared_preferences/shared_preferences.dart';
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
    if (index < 0 || index >= DictationMode.values.length) return DictationMode.liveTyping;
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

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Hotkey: 0 = double ctrl, 1 = triple ctrl, 2 = cmd+shift+space
  int get hotkeyType => _prefs.getInt(_keyHotkeyType) ?? 0;
  Future<void> setHotkeyType(int type) => _prefs.setInt(_keyHotkeyType, type);

  // VAD threshold in dBFS (negative number, default -35)
  double get vadThreshold => _prefs.getDouble(_keyVadThreshold) ?? -35.0;
  Future<void> setVadThreshold(double v) => _prefs.setDouble(_keyVadThreshold, v);

  // VAD silence duration in ms (default 1500)
  int get vadSilenceDuration => _prefs.getInt(_keyVadSilenceDuration) ?? 1500;
  Future<void> setVadSilenceDuration(int ms) => _prefs.setInt(_keyVadSilenceDuration, ms);

  // Grammar cleanup enabled (second LLM pass — uses extra RAM)
  bool get grammarEnabled => _prefs.getBool(_keyGrammarEnabled) ?? false;
  Future<void> setGrammarEnabled(bool v) => _prefs.setBool(_keyGrammarEnabled, v);

  // Hard cap on recording length to limit audio tensor size (default 45s)
  int get maxRecordingSeconds => _prefs.getInt(_keyMaxRecordingSeconds) ?? 45;
  Future<void> setMaxRecordingSeconds(int seconds) =>
      _prefs.setInt(_keyMaxRecordingSeconds, seconds);

  // Notify when falling back to clipboard paste
  bool get fallbackNotify => _prefs.getBool(_keyFallbackNotify) ?? true;
  Future<void> setFallbackNotify(bool v) => _prefs.setBool(_keyFallbackNotify, v);

  int get whisperModelIndex => _prefs.getInt(_keyWhisperModel) ?? 0;
  Future<void> setWhisperModelIndex(int index) =>
      _prefs.setInt(_keyWhisperModel, index);

  String get hfToken => _prefs.getString(_keyHfToken) ?? '';
  Future<void> setHfToken(String token) =>
      _prefs.setString(_keyHfToken, token.trim());
}
