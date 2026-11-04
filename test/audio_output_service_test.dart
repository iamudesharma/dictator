import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_to_text/audio/audio_output_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('serializes audio lease operations and allows recovery after failure',
      () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.aurascribe/accessibility'), (call) async {
      calls.add(call.method);
      if (call.method == 'beginAudioOutput' && calls.length == 1) {
        throw PlatformException(code: 'fixture-device');
      }
      return null;
    });
    final output = AudioOutputService();
    await expectLater(
        output.begin('duck', 0.2), throwsA(isA<PlatformException>()));
    await Future.wait([output.end(), output.begin('mute', 0)]);
    expect(
        calls, ['beginAudioOutput', 'restoreAudioOutput', 'beginAudioOutput']);
  });
}
