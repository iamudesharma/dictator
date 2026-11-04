import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../settings/settings_service.dart';

class AudioService {
  final SettingsService settings;
  String? microphoneOverride;
  AudioService(this.settings);
  Future<InputDevice?> _device() async {
    final selected = microphoneOverride ?? settings.microphoneId;
    if (selected.isEmpty) return null;
    final devices = await _recorder.listInputDevices();
    return devices.firstWhere((d) => d.id == selected,
        orElse: () => throw StateError(
            'Selected microphone is disconnected. Choose another microphone in Settings.'));
  }

  final AudioRecorder _recorder = AudioRecorder();
  String? _currentPath;

  /// Returns the current amplitude in dBFS. Used by VAD.
  Future<Amplitude> getAmplitude() => _recorder.getAmplitude();

  bool get isRecording => _currentPath != null;

  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    final fileName = 'dictation_${DateTime.now().millisecondsSinceEpoch}';
    _currentPath = p.join(dir.path, fileName);

    debugPrint(
        '[AuraScribe][Audio] start → $_currentPath (16kHz mono, WAV encoder)');
    await _recorder.start(
      RecordConfig(
        device: await _device(),
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 256000,
      ),
      path: _currentPath!,
    );
    debugPrint('[AuraScribe][Audio] recording started');
  }

  /// Starts streaming raw PCM audio chunks.
  Future<Stream<Uint8List>> startStream() async {
    debugPrint('[AuraScribe][Audio] startStream → (16kHz mono, PCM 16-bit)');
    _currentPath = 'stream';
    return _recorder.startStream(
      RecordConfig(
        device: await _device(),
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
  }

  /// Stops recording and returns the path to the WAV file.
  /// Returns null if not recording.
  Future<String?> stop() async {
    if (!await _recorder.isRecording()) {
      debugPrint('[AuraScribe][Audio] stop → not recording, returning null');
      return null;
    }
    final path = await _recorder.stop();
    _currentPath = null;
    debugPrint('[AuraScribe][Audio] stop → saved: $path');
    return path;
  }

  Future<void> cancel() async {
    await _recorder.cancel();
    _currentPath = null;
  }

  void dispose() {
    _recorder.dispose();
  }
}
