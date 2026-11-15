import 'package:flutter/services.dart';
import '../settings/settings_service.dart';
import 'stt_backend.dart';
import 'timed_transcript.dart';

/// Uses only Apple's installed on-device recognizer. Never permits server recognition.
class AppleTranscriptionBackend implements SttBackend, TimedSttBackend {
  static const channel = MethodChannel('com.aurascribe/apple_speech');
  final SettingsService settings;
  AppleTranscriptionBackend(this.settings);
  bool _loaded = false;
  @override
  bool get isLoaded => _loaded;
  @override
  bool get isLoading => false;
  @override
  String get modelLabel => 'Apple Speech (on device)';
  @override
  String get statusMessage => _loaded
      ? 'On-device recognition ready'
      : 'Uses installed macOS speech assets';
  @override
  Future<String?> load() async {
    try {
      await channel
          .invokeMethod<void>('prepare', {'language': settings.language});
      _loaded = true;
      return null;
    } catch (e) {
      _loaded = false;
      return e.toString();
    }
  }

  @override
  Future<String> transcribe(String audioPath) async =>
      await channel.invokeMethod<String>(
          'transcribe', {'path': audioPath, 'language': settings.language}) ??
      '';
  @override
  Future<TimedTranscript> transcribeTimed(String path,
      {required String timestamps}) async {
    final data = await channel.invokeMapMethod<String, dynamic>('transcribe',
        {'path': path, 'language': settings.language, 'timed': true});
    final words = (data?['words'] as List? ?? [])
        .map((v) => TranscriptSpan((v['start'] as num).toDouble(),
            (v['end'] as num).toDouble(), v['text'] as String))
        .toList();
    return TimedTranscript(data?['text'] as String? ?? '',
        segments: words, words: words);
  }

  @override
  Future<void> dispose() async {
    await channel.invokeMethod<void>('cancel');
    _loaded = false;
  }
}
