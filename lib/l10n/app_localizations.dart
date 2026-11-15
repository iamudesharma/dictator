import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

const interfaceLanguages = <String, String>{
  'system': 'System',
  'en': 'English',
  'pl': 'Polski',
  'zh': '简体中文',
  'zh-Hant': '繁體中文',
  'ja': '日本語',
  'de': 'Deutsch',
  'es': 'Español',
  'uk': 'Українська',
  'pt': 'Português (Brasil)',
  'fr': 'Français',
  'ru': 'Русский',
};

/// English-keyed UI catalogs, with explicit placeholders. Model identifiers,
/// transcripts, user titles, paths, and provider responses are never translated.
class AppLocalizations extends ChangeNotifier with WidgetsBindingObserver {
  AppLocalizations._();
  static final instance = AppLocalizations._();
  final Map<String, Map<String, String>> _catalogs = {};
  String _preference = 'system';
  Locale _locale = const Locale('en');
  Locale get locale => _locale;
  String get preference => _preference;
  bool _observing = false;
  AssetBundle? _assets;
  int _change = 0;
  String? _previewCode;
  final _loading = <String, Future<void>>{};
  static List<Locale> get supportedLocales => [
        for (final code
            in interfaceLanguages.keys.where((code) => code != 'system'))
          localeFor(code)
      ];
  static Locale localeFor(String code) => code == 'zh-Hant'
      ? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')
      : Locale(code == 'system' ? 'en' : code);
  static String resolveCode(String tag) {
    final parts = tag
        .split(RegExp(r'[.@]'))
        .first
        .replaceAll('_', '-')
        .toLowerCase()
        .split('-');
    if (parts.first == 'zh') {
      if (parts.contains('hans')) return 'zh';
      if (parts.contains('hant') ||
          parts.any(const ['tw', 'hk', 'mo'].contains)) {
        return 'zh-Hant';
      }
      return 'zh';
    }
    return interfaceLanguages.containsKey(parts.first) &&
            parts.first != 'system'
        ? parts.first
        : 'en';
  }

  static Locale resolve(String preference, Iterable<Locale> system) {
    if (preference != 'system') return localeFor(resolveCode(preference));
    // Match the first supported preferred language; English is the final fallback.
    for (final locale in system) {
      if (interfaceLanguages.containsKey(locale.languageCode)) {
        return localeFor(resolveCode(locale.toLanguageTag()));
      }
    }
    return const Locale('en');
  }

  Future<void> initialize(
      {String preference = 'system', AssetBundle? bundle}) async {
    _assets = bundle ?? rootBundle;
    _catalogs.clear();
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    await setPreference(preference);
  }

  Future<void> ensureLocale(String code) async {
    code = resolveCode(code);
    if (code == 'en' || _catalogs.containsKey(code)) return;
    await (_loading[code] ??= _loadLocale(code).whenComplete(() {
      _loading.remove(code);
    }));
  }

  Future<void> _loadLocale(String code) async {
    final data = await (_assets ?? rootBundle)
        .loadString('assets/l10n/$code.json', cache: false);
    _catalogs[code] = (jsonDecode(data) as Map).cast<String, String>();
  }

  void retainPreviewLocale(String code) {
    _previewCode = resolveCode(code);
    _trimCatalogs();
  }

  void releasePreviewLocales() {
    _previewCode = null;
    _trimCatalogs();
  }

  void _trimCatalogs() {
    final active = resolveCode(_locale.toLanguageTag());
    _catalogs.removeWhere((key, _) => key != active && key != _previewCode);
  }

  Future<void> setPreference(String preference,
      {List<Locale>? systemLocales}) async {
    final generation = ++_change;
    _preference =
        interfaceLanguages.containsKey(preference) ? preference : 'system';
    final next = resolve(_preference,
        systemLocales ?? WidgetsBinding.instance.platformDispatcher.locales);
    await ensureLocale(next.toLanguageTag());
    if (generation != _change) return;
    _locale = next;
    _trimCatalogs();
    notifyListeners();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_preference == 'system') {
      setPreference('system', systemLocales: locales);
    }
  }

  String translate(String english,
      {Locale? locale, Map<String, Object?> values = const {}}) {
    final code = resolveCode((locale ?? _locale).toLanguageTag());
    final table = _catalogs[code];
    var translated = code == 'en' ? english : table?[english] ?? english;
    // Replace tokens in one pass: user text containing braces is never rescanned.
    translated = translated.replaceAllMapped(RegExp(r'\{([^{}]*)\}'),
        (m) => values.containsKey(m[1]) ? '${values[m[1]] ?? ''}' : m[0]!);
    return translated;
  }
}

String tr(String english, {Map<String, Object?> values = const {}}) =>
    AppLocalizations.instance.translate(english, values: values);

extension LocalizedContext on BuildContext {
  String tr(String english, {Map<String, Object?> values = const {}}) =>
      AppLocalizations.instance.translate(english,
          locale: Localizations.maybeLocaleOf(this), values: values);
}
