import 'dart:io';

class SoundService {
  /// Play a sound when recording starts (light ping).
  static Future<void> playStart() async {
    await _play('/System/Library/Sounds/Tink.aiff');
  }

  /// Play a sound when recording stops (soft pop).
  static Future<void> playStop() async {
    await _play('/System/Library/Sounds/Pop.aiff');
  }

  /// Play a sound when transcription completes successfully (pleasant chime).
  static Future<void> playSuccess() async {
    await _play('/System/Library/Sounds/Glass.aiff');
  }

  /// Play a sound when an error occurs (warning beep).
  static Future<void> playError() async {
    await _play('/System/Library/Sounds/Basso.aiff');
  }

  static Future<void> _play(String path) async {
    if (Platform.isMacOS) {
      try {
        await Process.run('afplay', [path]);
      } catch (_) {
        // Silently catch errors if afplay is unavailable or fails
      }
    }
  }
}
