import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_to_text/accessibility/accessibility_service.dart';
import 'package:voice_to_text/accessibility/live_text_inserter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('queued live progress is committed only after native insertion succeeds',
      () async {
    final barrier = Completer<void>();
    final deltas = <String>[];
    final insert = LiveTextInserter((text) async {
      await barrier.future;
      deltas.add(text);
      return true;
    });
    insert.enqueue('Hello');
    insert.enqueue('Hello world');
    insert.enqueue('Hello world');
    expect(insert.inserted, isEmpty);
    barrier.complete();
    await insert.finish();
    expect(deltas, ['Hello', ' world']);
    expect(insert.inserted, 'Hello world');
  });
  test('failed insert never advances progress or dispatches later deltas',
      () async {
    var attempts = 0;
    final insert = LiveTextInserter((_) async {
      attempts++;
      throw PlatformException(code: 'ACCESSIBILITY_REQUIRED');
    });
    insert.enqueue('Hello');
    insert.enqueue('Hello world');
    await expectLater(insert.finish(), throwsA(isA<PlatformException>()));
    expect(insert.inserted, isEmpty);
    expect(attempts, 1);
  });
  test('destination capture and insertion failures cross the platform boundary',
      () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.aurascribe/accessibility'), (call) async {
      calls.add(call.method);
      if (call.method == 'beginDictationTarget') {
        return {'bundleId': 'fixture.editor', 'name': 'Fixture'};
      }
      if (call.method == 'insertText') {
        throw PlatformException(code: 'TARGET_FIELD_FOCUS');
      }
      return null;
    });
    final service = AccessibilityService();
    expect(
        (await service.captureDictationTarget())['bundleId'], 'fixture.editor');
    await expectLater(
        service.insertText('Fixture text'), throwsA(isA<PlatformException>()));
    await service.releaseDictationTarget();
    expect(calls, ['beginDictationTarget', 'insertText', 'endDictationTarget']);
  });
}
