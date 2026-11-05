import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_to_text/memory/model_memory_policy.dart';
import 'package:voice_to_text/settings/settings_service.dart';
import 'package:voice_to_text/shared/stt_engine.dart';
import 'package:voice_to_text/transcription/stt_backend.dart';
import 'package:voice_to_text/transcription/transcription_service.dart';

class FixtureBackend implements SttBackend {
  bool loaded = false, freed = false;
  Completer<void>? decode, disposal;
  @override
  bool get isLoaded => loaded;
  @override
  bool get isLoading => false;
  @override
  String get modelLabel => 'Fixture';
  @override
  String get statusMessage => '';
  @override
  Future<String?> load() async {
    loaded = true;
    return null;
  }

  @override
  Future<String> transcribe(String path) async {
    await decode?.future;
    expect(freed, false);
    return 'fixture';
  }

  @override
  Future<void> dispose() async {
    await disposal?.future;
    freed = true;
    loaded = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('model switches wait for inference and idle getters create no engines',
      () async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.aurascribe/accessibility'),
            (_) async => '');
    final settings = SettingsService();
    await settings.init();
    final engines = <FixtureBackend>[];
    final service = TranscriptionService(settings, backendFactory: (_) {
      final backend = FixtureBackend();
      engines.add(backend);
      return backend;
    });
    addTearDown(service.dispose);
    expect(service.isLoaded, false);
    expect(service.modelLabel, 'Whisper');
    expect(engines, isEmpty);
    await service.ensureLoaded();
    final barrier = Completer<void>();
    engines.single.decode = barrier;
    final inference = service.transcribe('fixture.wav');
    final switching = service.switchEngine(SttEngine.moonshine);
    await Future<void>.delayed(Duration.zero);
    expect(engines.single.freed, false);
    barrier.complete();
    expect(await inference, 'fixture');
    await switching;
    expect(engines.first.freed, true);
    expect(engines.length, 2);
    await service.unloadModel();
    expect(service.isLoaded, false);
    expect(engines.length, 2, reason: 'Reading unloaded state must stay lazy');
  });

  testWidgets(
      'idle policy releases a loaded engine and later inference reloads once',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.aurascribe/accessibility'),
            (_) async => '');
    final settings = SettingsService();
    await settings.init();
    late TranscriptionService service;
    final engines = <FixtureBackend>[];
    final policy = ModelMemoryPolicy(
        unload: () => service.releaseIdleResources(),
        delay: const Duration(seconds: 1));
    service =
        TranscriptionService(settings, memory: policy, backendFactory: (_) {
      final backend = FixtureBackend();
      engines.add(backend);
      return backend;
    });
    await service.ensureLoaded();
    await tester.pump(const Duration(seconds: 1));
    expect(engines.single.freed, true);
    expect(service.isLoaded, false);
    expect(await service.transcribe('fixture.wav'), 'fixture');
    expect(engines.length, 2);
    policy.dispose();
    service.dispose();
  });
  testWidgets(
      'ensureLoaded waits when idle cleanup still exposes the old loaded flag',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.aurascribe/accessibility'),
            (_) async => '');
    final settings = SettingsService();
    await settings.init();
    late TranscriptionService service;
    final engines = <FixtureBackend>[];
    final policy = ModelMemoryPolicy(
        unload: () => service.releaseIdleResources(),
        delay: const Duration(seconds: 1));
    service =
        TranscriptionService(settings, memory: policy, backendFactory: (_) {
      final backend = FixtureBackend();
      engines.add(backend);
      return backend;
    });
    await service.ensureLoaded();
    final barrier = Completer<void>();
    engines.single.disposal = barrier;
    await tester.pump(const Duration(seconds: 1));
    var ready = false;
    final loading = service.ensureLoaded().then((_) {
      ready = true;
    });
    await tester.pump();
    expect(ready, false);
    barrier.complete();
    await tester.pump();
    await loading;
    expect(service.isLoaded, true);
    expect(engines.length, 2);
    policy.dispose();
    service.dispose();
  });
}
