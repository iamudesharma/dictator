import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_to_text/memory/model_memory_policy.dart';

void main() {
  testWidgets('idle unloading cannot interrupt held activity', (tester) async {
    var unloads = 0;
    final policy = ModelMemoryPolicy(
        unload: () async {
          unloads++;
        },
        delay: const Duration(seconds: 1));
    addTearDown(policy.dispose);
    final owner = Object();
    policy.setActive(owner, true);
    await tester.pump(const Duration(seconds: 2));
    expect(unloads, 0);
    policy.setActive(owner, false);
    await tester.pump(const Duration(milliseconds: 999));
    expect(unloads, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(unloads, 1);
    await tester.pump(const Duration(seconds: 5));
    expect(unloads, 1, reason: 'Do not repeatedly unload an empty model');
  });

  testWidgets('arrival during unloading waits and then holds its own lease',
      (tester) async {
    final barrier = Completer<void>();
    var started = false;
    final policy = ModelMemoryPolicy(
        unload: () => barrier.future, delay: const Duration(seconds: 1));
    addTearDown(policy.dispose);
    policy.configure(enabled: true, delay: const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    final operation = policy.run(() async {
      started = true;
    });
    await tester.pump();
    expect(policy.isUnloading, isTrue);
    expect(started, isFalse);
    barrier.complete();
    await tester.pump();
    await operation;
    expect(started, isTrue);
    expect(policy.activeCount, 0);
    policy.dispose();
  });

  testWidgets(
      'keep-warm cancels pending unload; failures do not poison future activity',
      (tester) async {
    var errors = 0, calls = 0;
    final policy = ModelMemoryPolicy(
        unload: () async {
          calls++;
          throw StateError('fixture');
        },
        delay: const Duration(seconds: 1),
        onError: (_, __) => errors++);
    addTearDown(policy.dispose);
    await policy.run(() async {});
    policy.configure(enabled: false, delay: const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 0);
    policy.configure(enabled: true, delay: const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(errors, 1);
    expect(await policy.run(() async => 42), 42);
    expect(policy.activeCount, 0);
    policy.dispose();
  });
  testWidgets(
      'memory pressure waits for active work and trims even in keep-warm mode',
      (tester) async {
    var releases = 0;
    final policy = ModelMemoryPolicy(
        unload: () async {
          releases++;
        },
        enabled: false);
    final owner = Object();
    policy.setActive(owner, true);
    await policy.releaseIfIdle();
    expect(releases, 0);
    policy.setActive(owner, false);
    await tester.pump();
    expect(releases, 1);
    policy.dispose();
  });
}
