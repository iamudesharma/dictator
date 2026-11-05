import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_to_text/settings/settings_service.dart';
import 'package:voice_to_text/settings/settings_shell.dart';
import 'package:voice_to_text/shared/app_theme.dart';
import 'package:voice_to_text/shared/dictation_indicator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.aurascribe/accessibility');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel, (call) async => call.method == 'readHfToken' ? '' : null);
  });
  test('low-memory defaults and vocabulary whole-word replacements persist',
      () async {
    final settings = SettingsService();
    await settings.init();
    expect(settings.hotkeyType, 5);
    expect(settings.holdShortcut, isTrue);
    expect(settings.preloadModel, isFalse);
    expect(settings.grammarEnabled, isFalse);
    expect(settings.historyEnabled, isFalse);
    await settings
        .setVocabulary('aura scribe = AuraScribe\nram = RAM\ninvalid line');
    expect(settings.applyReplacements('Aura Scribe has ram, not programs.'),
        'AuraScribe has RAM, not programs.');
    final restored = SettingsService();
    await restored.init();
    expect(restored.vocabulary, settings.vocabulary);
  });
  test('migrates legacy HF token to native secure storage', () async {
    SharedPreferences.setMockInitialValues({'hf_token': 'hf_legacy_test'});
    final saved = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'readHfToken') return '';
      if (call.method == 'writeHfToken') saved.add(call.arguments as String);
      return null;
    });
    final settings = SettingsService();
    await settings.init();
    expect(saved, ['hf_legacy_test']);
    expect(settings.hfToken, 'hf_legacy_test');
    expect((await SharedPreferences.getInstance()).containsKey('hf_token'),
        isFalse);
  });
  for (final width in [680.0, 960.0]) {
    testWidgets('navigation works without overflow at $width', (tester) async {
      tester.view.physicalSize = Size(width, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      int selected = 0;
      await tester.pumpWidget(MaterialApp(
          theme: auraTheme(Brightness.dark),
          home: Scaffold(
              body: StatefulBuilder(
                  builder: (context, setState) => SettingsShell(
                      selected: selected,
                      onSelected: (index) => setState(() => selected = index),
                      status: 'On-device dictation',
                      content: PreferenceGroup(children: [
                        PreferenceRow(
                            icon: Icons.mic,
                            title: 'Microphone',
                            subtitle:
                                'Choose the microphone to use for dictation.',
                            trailing: Switch(value: true, onChanged: (_) {}))
                      ]))))));
      await tester.tap(find.byIcon(Icons.history_rounded));
      await tester.pumpAndSettle();
      expect(selected, 4);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('compact indicator has no focusable controls', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: DictationIndicator(
                label: 'Listening', recording: true, level: 0.5))));
    final pill = find.byKey(const ValueKey('dictation-pill'));
    expect(tester.getSize(pill), const Size(104, 30));
    expect(tester.getCenter(pill).dy, lessThan(50));
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });
}
