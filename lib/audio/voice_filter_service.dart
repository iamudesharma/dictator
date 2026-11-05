import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../app/dictation_orchestrator.dart';
import '../settings/settings_service.dart';

class VoiceFilterService extends ChangeNotifier {
  static const channel = MethodChannel('com.aurascribe/voice_filter');
  final DictationOrchestrator orchestrator;
  VoiceFilterService(this.orchestrator);
  bool running = false, installed = false, previewOnly = false, busy = false;
  double levelDb = -90;
  String error = '';
  Timer? _timer;
  bool _polling = false;
  Future<void> refresh() async {
    if (_polling) return;
    _polling = true;
    try {
      final data =
          await channel.invokeMapMethod<String, dynamic>('status') ?? {};
      running = data['running'] as bool? ?? false;
      installed = data['installed'] as bool? ?? false;
      levelDb = (data['levelDb'] as num?)?.toDouble() ?? -90;
      error = data['error'] as String? ?? '';
      if (!running) orchestrator.audioInputOverride = null;
      orchestrator.updateVoiceActivity(running
          ? (previewOnly ? 'Audio preview active' : 'Virtual microphone active')
          : null);
      notifyListeners();
    } finally {
      _polling = false;
    }
  }

  Future<void> start(SettingsService settings, {bool preview = false}) async {
    if (!orchestrator.isAvailable) {
      throw StateError('Finish the current audio task first.');
    }
    busy = true;
    orchestrator.externalActivity = 'Voice filter setup';
    notifyListeners();
    try {
      await channel.invokeMethod<void>('start', {
        'previewOnly': preview,
        'microphoneId': settings.voiceMicrophoneId,
        'voiceProcessing': settings.voiceProcessing,
        'automaticGain': settings.voiceAutomaticGain,
        'gain': settings.voiceGain,
        'gateDb': settings.voiceGateDb,
        'monitor': settings.voiceMonitor
      });
      previewOnly = preview;
      orchestrator.audioInputOverride =
          preview ? null : 'com.aurascribe.microphone';
      await refresh();
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
        refresh().catchError((Object e) {
          error = e.toString();
          notifyListeners();
        });
      });
    } finally {
      busy = false;
      orchestrator.externalActivity = null;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    await channel.invokeMethod<void>('stop');
    orchestrator.audioInputOverride = null;
    await refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
