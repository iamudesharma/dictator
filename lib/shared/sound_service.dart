import 'dart:io';
import 'package:flutter/services.dart';
import '../storage/project_storage.dart';

/// Short bundled earcons, independent of the user's macOS alert sound choice.
class SoundService {
  static double volume = 0.5;
  static Future<void> playStart() => _play('ready');
  static Future<void> playStop() => _play('stop');
  static Future<void> playSuccess() => _play('success');
  static Future<void> playError() => _play('error');

  static Future<void> _play(String name) async {
    if (!Platform.isMacOS || volume <= 0) return;
    try {
      final bytes = await rootBundle.load('assets/sounds/$name.wav');
      final dir = await ProjectStorage.instance.directory('cache/sounds');
      final file = File('${dir.path}/$name.wav');
      if (!await file.exists()) {
        await file.writeAsBytes(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
      }
      await Process.run(
          '/usr/bin/afplay', ['-v', volume.clamp(0, 1).toString(), file.path]);
    } catch (_) {
      // Audio feedback must never interrupt dictation.
    }
  }
}
