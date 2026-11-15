import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_to_text/accessibility/accessibility_service.dart';
import 'package:voice_to_text/app/dictation_orchestrator.dart';
import 'package:voice_to_text/audio/audio_service.dart';
import 'package:voice_to_text/grammar/grammar_model_service.dart';
import 'package:voice_to_text/grammar/grammar_service.dart';
import 'package:voice_to_text/grammar/smart_command_service.dart';
import 'package:voice_to_text/hotkeys/hotkey_service.dart';
import 'package:voice_to_text/settings/settings_screen.dart';
import 'package:voice_to_text/settings/model_catalog_dialog.dart';
import 'package:voice_to_text/transcription/gguf_catalog.dart';
import 'package:voice_to_text/settings/settings_features.dart';
import 'package:voice_to_text/settings/settings_service.dart';
import 'package:voice_to_text/settings/settings_shell.dart';
import 'package:voice_to_text/shared/app_theme.dart';
import 'package:voice_to_text/shared/dictation_state.dart';
import 'package:voice_to_text/storage/project_storage.dart';
import 'package:voice_to_text/transcription/transcription_service.dart';
import 'package:voice_to_text/tray/tray_service.dart';
import 'package:voice_to_text/vad/vad_service.dart';

class FakeRecord extends RecordPlatform {
  @override
  Future<void> create(String id) async {}
  @override
  Future<void> dispose(String id) async {}
  @override
  Future<List<InputDevice>> listInputDevices(String id) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTray extends TrayService {
  @override
  Future<void> updateState(DictationState state) async {}
  @override
  Future<void> updateActivity(String? value) async {}
  @override
  Future<void> updateVoiceActivity(String? value) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const snapshots = bool.fromEnvironment('AURA_UI_SNAPSHOTS');
  setUpAll(() async {
    if (!snapshots) return;
    for (final entry in {
      '.AppleSystemUIFont': '/System/Library/Fonts/SFNS.ttf',
      'MaterialIcons':
          '${Directory.current.path}/.aurascribe/tools/flutter-3.50.0/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(entry.key);
      loader.addFont(
        Future.value(
          ByteData.sublistView(await File(entry.value).readAsBytes()),
        ),
      );
      await loader.load();
    }
  });
  for (final scale in [1.0, 1.3]) {
    for (final width in [680.0, 960.0]) {
      testWidgets(
        'all feature pages render without overflow at $width and scale $scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 720);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          late Directory dir;
          late SettingsService settings;
          await tester.runAsync(() async {
            dir = await Directory.current.createTemp('.pages-test-');
            await File('${dir.path}/pubspec.yaml')
                .writeAsString('name: fixture');
            ProjectStorage.instance = ProjectStorage(dir);
            SharedPreferences.setMockInitialValues({
              'stt_engine': 4,
              'gguf_model': 'parakeet_unified_english',
              for (final feature in optionalSettingsFeatures)
                'sidebar_${feature.id}': true,
            });
            RecordPlatform.instance = FakeRecord();
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(
                  const MethodChannel('com.aurascribe/accessibility'),
                  (call) async => switch (call.method) {
                    'readHfToken' => '',
                    'launchAtLogin' => false,
                    'keyboardSources' => [],
                    'checkPermission' => false,
                    _ => null,
                  },
                );
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(
                  const MethodChannel('com.aurascribe/voice_filter'),
                  (call) async => {
                    'installed': false,
                    'running': false,
                    'levelDb': -90,
                    'error': '',
                  },
                );
            settings = SettingsService();
            await settings.init();
          });
          final audio = AudioService(settings),
              transcription = TranscriptionService(settings);
          final model = GrammarModelService(settings),
              grammar = GrammarService.simple(settings),
              accessibility = AccessibilityService();
          final orchestrator = DictationOrchestrator(
            audio: audio,
            vad: VadService(audio, settings),
            transcription: transcription,
            grammar: grammar,
            accessibility: accessibility,
            tray: FakeTray(),
            smartCommand: SmartCommandService(() => model, transcription),
            settings: settings,
          );
          final boundaryKey = GlobalKey();
          Widget render(Brightness brightness) => RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: auraTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: SettingsScreen(
                settings: settings,
                hotkeyService: HotkeyService(settings),
                accessibility: accessibility,
                transcriptionService: transcription,
                grammarService: grammar,
                orchestrator: orchestrator,
              ),
            ),
          );
          await tester.pumpWidget(render(Brightness.dark));
          if (snapshots && scale == 1.0) {
            for (final feature in optionalSettingsFeatures) {
              await settings.setSettingsPageVisible(feature.page, false);
            }
            for (final brightness in Brightness.values) {
              await tester.pumpWidget(render(brightness));
              for (final page in [0, 1, 6]) {
                tester
                    .widget<SettingsShell>(find.byType(SettingsShell))
                    .onSelected(page);
                await tester.pumpAndSettle();
                await tester.runAsync(() async {
                  final boundary =
                      boundaryKey.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary;
                  final image = await boundary.toImage();
                  try {
                    final bytes = await image.toByteData(
                      format: ui.ImageByteFormat.png,
                    );
                    final dir = await Directory('.aurascribe/ui-redesign')
                        .create(recursive: true);
                    await File(
                      '${dir.path}/${brightness.name}-${settingsPages[page].toLowerCase()}-${width.round()}.png',
                    ).writeAsBytes(bytes!.buffer.asUint8List());
                  } finally {
                    image.dispose();
                  }
                });
              }
            }
            for (final feature in optionalSettingsFeatures) {
              await settings.setSettingsPageVisible(feature.page, true);
            }
            await tester.pumpWidget(render(Brightness.dark));
          }
          for (var i = 0; i < settingsPages.length; i++) {
            final icon = find.byIcon(settingsIcons[i]).first;
            await tester.scrollUntilVisible(
              icon,
              70,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.tap(icon);
            await tester.pumpAndSettle();
            expect(find.text(settingsPages[i]), findsWidgets);
            expect(
              tester.takeException(),
              isNull,
              reason: 'Page ${settingsPages[i]} at $width',
            );
            // Exercise controls hidden behind every advanced disclosure too.
            // Opening a section must not corrupt scroll state or overflow.
            final tiles = tester
                .widgetList<ExpansionTile>(find.byType(ExpansionTile))
                .toList();
            for (final tile in tiles) {
              if (tile.controller?.isExpanded == true) continue;
              final header = find
                  .descendant(
                    of: find.byWidget(tile),
                    matching: find.byType(ListTile),
                  )
                  .first;
              await tester.ensureVisible(header);
              await tester.pumpAndSettle();
              await tester.tap(header);
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason:
                    'Expanded section on ${settingsPages[i]} at $width / $scale',
              );
              await tester.ensureVisible(header);
              await tester.pumpAndSettle();
              await tester.tap(header);
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
          }
          tester
              .widget<SettingsShell>(find.byType(SettingsShell))
              .onSelected(1);
          await tester.pumpAndSettle();
          final filters = find.widgetWithText(ExpansionTile, 'Filters');
          await tester.ensureVisible(filters);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Filters'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.enterText(
            find.widgetWithText(TextField, 'Filter speech models'),
            'parakeet',
          );
          await tester.pumpAndSettle();
          final browse = find.byKey(const ValueKey('browse-all-models'));
          await tester.ensureVisible(browse);
          await tester.pumpAndSettle();
          await tester.tap(browse);
          await tester.pumpAndSettle();
          // Page filters must never hide options in the full catalog browser.
          expect(find.byType(ModelCatalogDialog), findsOneWidget);
          for (final model in ggufCatalog) {
            expect(
              find.byKey(ValueKey('catalog-option-${model.id}')),
              findsOneWidget,
            );
          }
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.widgetWithText(TextField, 'Filter speech models'),
            '',
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Filters'));
          await tester.pumpAndSettle();
          // An unkeyed ExpansionTile would save a bool in the page scroll
          // offset slot, then crash when Models is mounted again.
          tester
              .widget<SettingsShell>(find.byType(SettingsShell))
              .onSelected(1);
          await tester.pumpAndSettle();
          final benchmark = find.widgetWithText(
            ExpansionTile,
            'Published benchmark details',
          );
          expect(benchmark, findsOneWidget);
          await tester.ensureVisible(benchmark);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Published benchmark details'));
          await tester.pumpAndSettle();
          tester
              .widget<SettingsShell>(find.byType(SettingsShell))
              .onSelected(0);
          await tester.pumpAndSettle();
          tester
              .widget<SettingsShell>(find.byType(SettingsShell))
              .onSelected(1);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          // The Features switch owns sidebar visibility, not the saved vocabulary.
          tester
              .widget<SettingsShell>(find.byType(SettingsShell))
              .onSelected(6);
          await tester.pumpAndSettle();
          await settings.setVocabulary('aura=Aura');
          final row = find.byWidgetPredicate(
            (w) => w is PreferenceRow && w.title == 'Vocabulary',
          );
          final toggle = find.descendant(
            of: row,
            matching: find.byType(Switch),
          );
          tester.widget<Switch>(toggle).onChanged!(false);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('settings-nav-3')), findsNothing);
          expect(settings.vocabulary, 'aura=Aura');
          tester.widget<Switch>(toggle).onChanged!(true);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('settings-nav-3')), findsOneWidget);
          await tester.enterText(
            find.byKey(const ValueKey('settings-search')),
            'Silence duration',
          );
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(ListTile, 'Silence duration'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<SettingsShell>(find.byType(SettingsShell)).selected,
            2,
          );
          expect(find.text('Silence duration'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          orchestrator.dispose();
          transcription.dispose();
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await dir.delete(recursive: true);
          });
        },
      );
    }
  }
}
