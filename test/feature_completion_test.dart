import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_to_text/diagnostics/story_browser.dart';
import 'package:voice_to_text/diagnostics/story_catalog.dart';
import 'package:voice_to_text/diagnostics/story_fixture.dart';
import 'package:voice_to_text/l10n/app_localizations.dart';
import 'package:voice_to_text/meetings/browser_call.dart';
import 'package:voice_to_text/meetings/meeting_service.dart';
import 'package:voice_to_text/settings/settings_search.dart';
import 'package:voice_to_text/settings/settings_service.dart';
import 'package:voice_to_text/settings/settings_shell.dart';
import 'package:voice_to_text/shared/app_theme.dart';

class _CatalogBundle extends CachingAssetBundle {
  final requested = <String>[];
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    requested.add(key);
    return File(key).readAsStringSync();
  }

  @override
  Future<ByteData> load(String key) async {
    requested.add(key);
    return ByteData.sublistView(File(key).readAsBytesSync());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = AppLocalizations.instance;
  tearDown(() async {
    await l10n.setPreference('en');
    l10n.releasePreviewLocales();
  });

  test('system locale selection handles scripts, regions and unsupported languages', () {
    for (final (tag, expected) in [
      ('zh_TW.UTF-8', 'zh-Hant'),
      ('zh-HK', 'zh-Hant'),
      ('zh-Hans-TW', 'zh'),
      ('zh-Hant-CN', 'zh-Hant'),
      ('pt-BR', 'pt'),
      ('fr_CA', 'fr'),
      ('ru-RU', 'ru'),
      ('xx', 'en'),
    ]) {
      expect(AppLocalizations.resolveCode(tag), expected);
    }
    expect(
      AppLocalizations.resolve('system', [
        const Locale('xx'),
        const Locale('ja'),
      ]),
      const Locale('ja'),
    );
    expect(
      AppLocalizations.resolve('de', [const Locale('fr')]),
      const Locale('de'),
    );
  });

  test(
    'all language catalogs cover application labels and preserve placeholders',
    () {
      final keys = (jsonDecode(
        File('tool/l10n/ui_keys.json').readAsStringSync(),
      ) as List).cast<String>();
      final neutral = (jsonDecode(
        File('tool/l10n/neutral.json').readAsStringSync(),
      ) as List).cast<String>().toSet();
      final tokens = RegExp(r'\{[^{}]*\}');
      for (final language in interfaceLanguages.keys.where(
        (v) => !['en', 'system'].contains(v),
      )) {
        final table = (jsonDecode(
          File('assets/l10n/$language.json').readAsStringSync(),
        ) as Map).cast<String, String>();
        for (final key in keys.where((k) => !neutral.contains(k))) {
          expect(
            table.containsKey(key),
            isTrue,
            reason: '$language missing $key',
          );
          expect(
            tokens.allMatches(table[key]!).map((m) => m[0]).toList()..sort(),
            tokens.allMatches(key).map((m) => m[0]).toList()..sort(),
            reason: '$language: $key',
          );
        }
      }
    },
  );

  test(
    'language catalogs load on demand, search localizes, and values are opaque',
    () async {
      final bundle = _CatalogBundle();
      await l10n.initialize(preference: 'en', bundle: bundle);
      expect(bundle.requested, isEmpty);
      await l10n.setPreference('fr');
      expect(bundle.requested, ['assets/l10n/fr.json']);
      expect(tr('Interface language'), 'Langue de l’interface');
      expect(
        searchSettings('langue').any((e) => e.label == 'Interface language'),
        isTrue,
      );
      expect(
        searchSettings('Interface language').any((e) => e.page == 0),
        isTrue,
      );
      expect(
        tr(
          'Speech model: {v0}',
          values: {'v0': 'Custom {v1}', 'v1': 'do not substitute'},
        ),
        'Modèle vocal : Custom {v1}',
      );
      expect(
        tr('unregistered technical message'),
        'unregistered technical message',
      );
      await l10n.setPreference('zh-Hant');
      expect(tr('Find settings'), '尋找設定');
      l10n.didChangeLocales([const Locale('de')]);
      expect(
        l10n.locale.scriptCode,
        'Hant',
      ); // explicit selection ignores OS changes
      await l10n.setPreference('system', systemLocales: [const Locale('de')]);
      expect(l10n.locale.languageCode, 'de');
    },
  );

  test(
    'interface preference persists independently of speech language',
    () async {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.aurascribe/accessibility'),
            (call) async => call.method == 'readHfToken' ? '' : null,
          );
      final settings = SettingsService();
      await settings.init();
      await settings.setLanguage('ja');
      await settings.setInterfaceLanguage('fr');
      final restored = SettingsService();
      await restored.init();
      expect(restored.interfaceLanguage, 'fr');
      expect(restored.language, 'ja');
      settings.dispose();
      restored.dispose();
    },
  );

  test(
    'browser names accept supported call sites and do not persist URL tokens',
    () {
      final call = BrowserCall.fromPage('com.apple.Safari', {
        'url': 'https://meet.google.com/abc-defg-hij?token=secret#private',
        'title': 'Meet - Product review - Safari',
      })!;
      expect(call.title, 'Product review');
      expect(call.service, 'Google Meet');
      expect(jsonEncode(call.toMetadata()), isNot(contains('secret')));
      expect(call.host, 'meet.google.com');
      expect(
        BrowserCall.fromPage('org.mozilla.firefox', {
          'title': 'Meet – Design sync — Mozilla Firefox',
        })!.title,
        'Design sync',
      );
      for (final host in BrowserCall.sites.keys) {
        expect(
          BrowserCall.fromPage('com.google.Chrome', {
            'url': 'https://$host/call',
            'title': 'Planning',
          }),
          isNotNull,
          reason: host,
        );
      }
      expect(
        BrowserCall.fromPage('com.google.Chrome', {
          'url': 'https://www.messenger.com/call',
          'title': 'Planning',
        })?.service,
        'Messenger',
      );
      for (final url in [
        'https://meet.google.com/',
        'https://meet.google.com/landing/',
        'https://meet.google.com/new',
        'https://meet.google.com.evil.test/call',
        'file://meet.google.com/call',
        'https://example.com',
      ]) {
        expect(
          BrowserCall.fromPage('com.google.Chrome', {
            'url': url,
            'title': 'Meet - Other',
          }),
          isNull,
          reason: url,
        );
      }
      expect(
        BrowserCall.fromPage('com.apple.TextEdit', {
          'title': 'Meet - Planning',
        }),
        isNull,
      );
      expect(
        BrowserCall.fromPage('com.apple.Safari', {
          'url': 'https://meet.google.com/abc-defg-hij',
          'title': 'Meet - abc-defg-hij',
        })!.title,
        'Google Meet meeting',
      );
    },
  );

  test(
    'browser context expiry isolates apps and clears on navigation or call end',
    () {
      final cache = BrowserCallCache();
      final now = DateTime.utc(2026, 11, 13);
      const id = 'com.apple.Safari';
      expect(
        cache.update(id, {
          'url': 'https://meet.google.com/abc',
          'title': 'Planning',
        }, now)?.title,
        'Planning',
      );
      expect(
        cache.update(id, {}, now.add(const Duration(seconds: 30)))?.title,
        'Planning',
      );
      expect(cache.update('com.google.Chrome', {}, now), isNull);
      expect(
        cache.update(id, {}, now.add(const Duration(seconds: 61))),
        isNull,
      );
      cache.update(id, {
        'url': 'https://meet.google.com/abc',
        'title': 'Planning',
      }, now);
      expect(
        cache.update(id, {
          'url': 'https://example.com',
          'title': 'Private browsing',
        }, now),
        isNull,
      );
      cache.update(id, {'title': 'Meet - New call'}, now);
      cache.retainApplications({});
      expect(cache.update(id, {}, now), isNull);
    },
  );

  test('international meeting names remain valid UTF-8 export filenames', () {
    final title = MeetingService.exportTitle(List.filled(100, '会議🎙️').join());
    expect(utf8.encode(title).length, lessThanOrEqualTo(180));
    expect(title, startsWith('会議'));
    expect(title, isNot(contains('�')));
    expect(MeetingService.exportTitle(''), 'Meeting');
    expect(MeetingService.exportTitle('a/b:c'), 'a-b-c');
  });

  test('story links are stable and reject unrelated or malformed URLs', () {
    expect(appStories.map((s) => s.id).toSet().length, appStories.length);
    for (final story in appStories) {
      expect(AppStory.fromLink(story.link.toString()), same(story));
    }
    for (final link in [
      'https://story/hud-ready',
      'aurascribe://story/unknown',
      'aurascribe://story/hud-ready?run=1',
      'aurascribe://story/hud-ready/other',
      'aurascribe://story/../hud-ready',
    ]) {
      expect(AppStory.fromLink(link), isNull);
    }
  });

  testWidgets(
    'all stories render in compact French at enlarged text without native services',
    (tester) async {
      await l10n.initialize(preference: 'fr', bundle: _CatalogBundle());
      tester.view.physicalSize = const Size(390, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final story in appStories) {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('fr'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: auraTheme(Brightness.dark),
            home: Scaffold(
              body: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.3)),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: StoryFixture(
                        key: ValueKey(story.id),
                        story: story,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: story.id);
      }
    },
  );

  testWidgets(
    'story reset discards fixture edits and language selection is isolated',
    (tester) async {
      await l10n.initialize(preference: 'en', bundle: _CatalogBundle());
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: StoryBrowser(initialStory: 'meetings-rename'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Design review'),
        'Private title',
      );
      await tester.tap(find.text('Reset preview'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Design review'), findsOneWidget);
      expect(find.text('Private title'), findsNothing);
      expect(l10n.preference, 'en');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('settings labels update when the interface locale changes', (
    tester,
  ) async {
    await l10n.initialize(preference: 'en', bundle: _CatalogBundle());
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: l10n,
        builder: (_, __) => MaterialApp(
          locale: l10n.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: SettingsShell(
              selected: 0,
              onSelected: (_) {},
              status: '',
              content: const Text('User document: Output'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('General'), findsWidgets);
    await l10n.setPreference('fr');
    await tester.pumpAndSettle();
    expect(find.text('Général'), findsWidgets);
    expect(find.text('User document: Output'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
