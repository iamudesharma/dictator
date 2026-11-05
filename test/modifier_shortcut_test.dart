import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_to_text/hotkeys/hotkey_service.dart';
import 'package:voice_to_text/hotkeys/shortcut_binding.dart';
import 'package:voice_to_text/hotkeys/shortcut_recorder.dart';
import 'package:voice_to_text/settings/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('standalone modifiers are accepted only for dictation', () {
    final binding = ShortcutBinding.chord(PhysicalKeyboardKey.altRight, {});
    expect(binding.isModifierOnly, isTrue);
    expect(binding.modifierKeyCode, 61);
    expect(() => binding.validate(allowModifierOnly: true), returnsNormally);
    expect(binding.validate, throwsArgumentError);
    final values = ShortcutBinding.defaults;
    values[ShortcutAction.dictation] = binding;
    expect(() => HotkeyService.validateBindings(values, chordDictation: true),
        returnsNormally);
    values[ShortcutAction.pasteLast] = binding;
    expect(() => HotkeyService.validateBindings(values, chordDictation: true),
        throwsArgumentError);
  });

  testWidgets('picker accepts modifier release and still records chords',
      (tester) async {
    ShortcutBinding? picked;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      picked = await showDialog<ShortcutBinding>(
                          context: context,
                          builder: (_) => const ShortcutRecorder(
                              action: ShortcutAction.dictation));
                    },
                    child: const Text('Choose'))))));
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(find.text('Release Option ⌥ to select it.'), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(picked!.isModifierOnly, isTrue);
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(picked!.label, '⌥ T');
  });

  test('native modifier registration routes hold down/up and preserves toggle',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final native = <MethodCall>[], carbon = <MethodCall>[];
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.aurascribe/accessibility'),
        (call) async => call.method == 'readHfToken' ? '' : null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.aurascribe/hotkey'), (call) async {
      native.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(
        const MethodChannel('dev.leanflutter.plugins/hotkey_manager'),
        (call) async {
      carbon.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(
        const MethodChannel('dev.leanflutter.plugins/hotkey_manager_event'),
        (call) async => null);
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.init();
    final service = HotkeyService(settings);
    var starts = 0, stops = 0, toggles = 0;
    service.onHoldStarted = () => starts++;
    service.onHoldEnded = () => stops++;
    service.onTriggered = () => toggles++;
    await service.init();
    final config =
        native.singleWhere((call) => call.method == 'startModifierListening');
    expect(config.arguments, {'keyCode': 58, 'anyOption': true, 'hold': true});
    expect(carbon.where((call) => call.method == 'register').length, 4,
        reason:
            'modifier-only dictation must bypass Carbon chord registration');
    Future<void> emit(String method) async {
      final completed = Completer<void>();
      ServicesBinding.instance.channelBuffers.push(
          'com.aurascribe/hotkey',
          const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
          (_) => completed.complete());
      await completed.future;
    }

    await emit('onModifierPressed');
    await emit('onModifierReleased');
    expect([starts, stops, toggles], [1, 1, 0]);
    await settings.setHoldShortcut(false);
    await service.updateHotkey();
    await emit('onModifierPressed');
    await emit('onModifierReleased');
    expect([starts, stops, toggles], [1, 1, 1]);
    service.dispose();
    await Future<void>.delayed(Duration.zero);
  });
}
