import '../l10n/app_localizations.dart';
import '../l10n/status_message.dart';

import 'dart:io';
import 'dart:async';

import 'settings_features.dart';
import 'model_catalog_dialog.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:window_manager/window_manager.dart';

import '../app/dictation_orchestrator.dart';
import '../history/history_service.dart';
import '../storage/project_storage.dart';
import '../hotkeys/hotkey_service.dart';
import '../accessibility/accessibility_service.dart';
import '../shared/stt_engine.dart';
import '../shared/dictation_mode.dart';
import '../shared/dictation_state.dart';
import '../shared/sound_service.dart';
import '../grammar/grammar_service.dart';
import '../transcription/transcription_service.dart';
import '../transcription/gguf_catalog.dart';
import '../transcription/model_metadata.dart';
import '../transcription/custom_model_store.dart';
import '../benchmarks/model_benchmark.dart';
import '../meetings/meetings_screen.dart';
import '../audio/voice_filter_screen.dart';
import '../capture/annotation_screen.dart';
import '../diagnostics/playground_screen.dart';
import 'settings_service.dart';
import 'onboarding_card.dart';
import 'settings_search.dart';
import '../output/output_preview.dart';
import 'settings_shell.dart';
import '../output/output_pipeline.dart';
import '../output/personal_commands.dart';
import '../output/pipeline_editor.dart';
import '../hotkeys/shortcut_binding.dart';
import '../hotkeys/shortcut_recorder.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsService settings;
  final HotkeyService hotkeyService;
  final AccessibilityService accessibility;
  final TranscriptionService transcriptionService;
  final GrammarService grammarService;
  final DictationOrchestrator orchestrator;
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.hotkeyService,
    required this.accessibility,
    required this.transcriptionService,
    required this.grammarService,
    required this.orchestrator,
  });
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  static const channel = MethodChannel('com.aurascribe/accessibility');
  int _page = 0;
  final _sections = <String, ExpansibleController>{};
  final _sectionKeys = <String, GlobalKey>{};
  final _sectionStorage = <String, PageStorageBucket>{};
  String _settingsQuery = '';
  String _modelQuery = '';
  String _modelSort = 'name';
  bool _languageOnly = false;
  bool _downloadedOnly = false;
  bool _ax = false, _login = false, _busy = false;
  int _bytes = 0;
  String? _error;
  List<InputDevice> _microphones = [];
  List<OutputProfile> _profiles = [];
  List<PersonalCommand> _commands = [];
  List<CustomSpeechModel> _customModels = [];
  List<Map<String, String>> _keyboardSources = [];
  List<Map<String, dynamic>> _benchmarks = [];
  final _settingsSearch = TextEditingController();
  final _decoderWords = TextEditingController();
  final _token = TextEditingController();
  final _vocabulary = TextEditingController();
  final _search = TextEditingController();
  SettingsService get s => widget.settings;
  TranscriptionService get ts => widget.transcriptionService;
  bool get locked =>
      _busy ||
      ts.isLoading ||
      widget.orchestrator.externalActivity != null ||
      widget.orchestrator.isStarting ||
      widget.orchestrator.smartCommandRunning ||
      (widget.orchestrator.state != DictationState.idle &&
          widget.orchestrator.state != DictationState.error);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _page = widget.orchestrator.settingsPage;
    if (_page < 0 || _page >= settingsPages.length) _page = 0;
    if (!s.isSettingsPageVisible(_page)) {
      unawaited(s.setSettingsPageVisible(_page, true));
    }
    s.addListener(_refresh);
    widget.orchestrator.updates.addListener(_refresh);
    final drafts = widget.orchestrator.settingsDrafts;
    _decoderWords.text = drafts['decoder'] ?? s.decoderVocabulary;
    _token.text = drafts['token'] ?? s.hfToken;
    _vocabulary.text = drafts['vocabulary'] ?? s.vocabulary;
    _search.text = drafts['search'] ?? '';
    _settingsQuery = drafts['settingsSearch'] ?? '';
    _settingsSearch.text = _settingsQuery;
    ts.addListener(_refresh);
    widget.orchestrator.addListener(_refresh);
    HistoryService.instance.addListener(_refresh);
    _loadSystemState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadSystemState();
  }

  void _refresh() {
    if (mounted) {
      setState(() {
        if (widget.orchestrator.requestedStory != null) {
          _page = 11;
          if (!s.isSettingsPageVisible(11)) {
            unawaited(s.setSettingsPageVisible(11, true));
          }
        } else if (!s.isSettingsPageVisible(_page)) {
          _page = 6;
          widget.orchestrator.settingsPage = 6;
        }
      });
    }
  }

  Future<void>? _refreshing;
  bool _refreshAgain = false;
  Future<void> _loadSystemState() {
    _refreshAgain = true;
    return _refreshing ??= _refreshLoop().whenComplete(
      () => _refreshing = null,
    );
  }

  Future<void> _refreshLoop() async {
    while (_refreshAgain && mounted) {
      _refreshAgain = false;
      await _loadPageState();
    }
  }

  void _selectPage(int page) {
    if (page < 0 || page >= settingsPages.length) return;
    if (!s.isSettingsPageVisible(page)) {
      unawaited(s.setSettingsPageVisible(page, true));
    }
    widget.orchestrator.requestedStory = null;
    widget.orchestrator.settingsPage = page;
    setState(() {
      _page = page;
      if (page != 2) _profiles = [];
      if (page != 12) _commands = [];
      if (page != 1) {
        _customModels = [];
        _keyboardSources = [];
        _benchmarks = [];
      }
      if (page != 0 && page != 8) _microphones = [];
    });
    _loadSystemState();
  }

  Future<void> _loadPageState() async {
    final page = _page;
    try {
      if (page == 0 || page == 8) {
        final recorder = AudioRecorder();
        late List<InputDevice> devices;
        try {
          devices = await recorder.listInputDevices();
        } finally {
          await recorder.dispose();
        }
        final ax = page == 0 ? await widget.accessibility.hasPermission() : _ax;
        final login = page == 0
            ? await channel.invokeMethod<bool>('launchAtLogin') ?? false
            : _login;
        if (mounted && _page == page) {
          setState(() {
            _microphones = devices;
            _ax = ax;
            _login = login;
          });
        }
      }
      if (page == 1) {
        final custom = await CustomModelStore().read();
        final downloaded = <String>{};
        for (final model in ggufCatalog) {
          final file = File(
            '${ProjectStorage.instance.models.path}/gguf/${model.id}/${model.filename}',
          );
          if (await file.exists() && await file.length() == model.bytes) {
            downloaded.add(model.id);
          }
        }
        final sources =
            await channel.invokeListMethod<dynamic>('keyboardSources') ?? [];
        final benchmarks = await ModelBenchmark(ts).read();
        if (mounted && _page == page) {
          setState(() {
            _customModels = custom;

            _keyboardSources = sources
                .map((v) => Map<String, String>.from(v as Map))
                .toList();
            _benchmarks = benchmarks;
          });
        }
      }
      if (page == 1 || page == 5) {
        final bytes = await ProjectStorage.instance.modelBytes();
        if (mounted && _page == page) setState(() => _bytes = bytes);
      }
      if (page == 2) {
        final profiles = await PipelineStore().read();
        if (mounted && _page == page) setState(() => _profiles = profiles);
      }
      if (page == 12) {
        final commands = await PersonalCommandStore().read();
        if (mounted && _page == page) setState(() => _commands = commands);
      }
    } catch (e) {
      if (mounted && _page == page) {
        setState(() => _error = 'Could not refresh system settings: $e');
      }
    }
  }

  @override
  void dispose() {
    widget.orchestrator.settingsPage = _page;
    widget.orchestrator.settingsDrafts.addAll({
      'decoder': _decoderWords.text,
      'token': _token.text,
      'vocabulary': _vocabulary.text,
      'search': _search.text,
      'settingsSearch': _settingsQuery,
    });
    widget.orchestrator.updates.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    s.removeListener(_refresh);
    ts.removeListener(_refresh);
    widget.orchestrator.removeListener(_refresh);
    HistoryService.instance.removeListener(_refresh);
    for (final controller in _sections.values) {
      controller.dispose();
    }
    _sections.clear();
    _sectionKeys.clear();
    _sectionStorage.clear();
    _settingsSearch.dispose();
    _decoderWords.dispose();
    _token.dispose();
    _vocabulary.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<T?> _showSettingsDialog<T>({required WidgetBuilder builder}) =>
      widget.orchestrator.withSettingsDialog(
        () => showDialog<T>(context: context, builder: builder),
      );

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _change(Future<void> value) async {
    await value;
    _refresh();
  }

  Widget _note(String text, {bool expanded = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Tooltip(
      message: text,
      child: Text(
        text,
        maxLines: expanded ? null : 1,
        overflow: expanded ? null : TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          height: 1.4,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
  Widget _switch(
    IconData icon,
    String title,
    String subtitle,
    bool value,
    Future<void> Function(bool) onChanged,
  ) => PreferenceRow(
    icon: icon,
    title: title,
    subtitle: subtitle,
    trailing: SizedBox(
      width: 52,
      child: Switch.adaptive(
        value: value,
        onChanged: locked ? null : (v) => _run(() => onChanged(v)),
      ),
    ),
  );
  Widget _select<T>(
    T value,
    Map<T, String> options,
    Future<void> Function(T) change, {
    bool disabled = false,
  }) => DropdownButtonHideUnderline(
    child: DropdownButton<T>(
      value: options.containsKey(value) ? value : null,
      hint: Text(tr("Choose an available option")),
      isDense: true,
      isExpanded: true,
      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      items: options.entries
          .map(
            (e) => DropdownMenuItem(
              value: e.key,
              child: Text(tr(e.value), overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: disabled || _busy
          ? null
          : (v) {
              if (v != null) _run(() => change(v));
            },
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SettingsShell(
      selected: _page,
      query: _settingsQuery,
      searchController: _settingsSearch,
      visiblePages: s.visibleSettingsPages,
      onSearch: (value) => setState(() => _settingsQuery = value),
      onSelected: _selectPage,
      onDrag: () => windowManager.startDragging(),
      status: ts.isLoaded
          ? tr("{v0} ready", values: {"v0": ts.modelLabel})
          : tr("On-device dictation"),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Material(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: SelectableText(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          if (_busy || ts.isLoading)
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: LinearProgressIndicator(),
            ),
          if (ts.isLoading && ProjectStorage.instance.hasActiveDownloads)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: ProjectStorage.instance.cancelDownloads,
                child: Text(tr("Cancel model download")),
              ),
            ),
          if (_settingsQuery.isNotEmpty) ...[
            for (final match in searchSettings(_settingsQuery).take(8))
              ListTile(
                title: Text(
                  tr(match.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  tr(
                    s.isSettingsPageVisible(match.page)
                        ? settingsPages[match.page]
                        : 'Features',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, size: 16),
                onTap: () {
                  _settingsSearch.clear();
                  setState(() => _settingsQuery = '');
                  final target = s.isSettingsPageVisible(match.page)
                      ? match.page
                      : 6;
                  _selectPage(target);
                  if (target == match.page && match.section != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _page == target) {
                        unawaited(_revealSection(tr(match.section!)));
                      }
                    });
                  }
                },
              ),
            if (searchSettings(_settingsQuery).isEmpty)
              _note(tr('No matching settings')),
          ] else
            ...switch (_page) {
              0 => _general(),
              1 => _models(),
              2 => _output(),
              3 => _words(),
              4 => _history(),
              11 => [
                PlaygroundScreen(
                  orchestrator: widget.orchestrator,
                  transcription: ts,
                  settings: s,
                ),
              ],
              10 => _updates(),
              9 => [AnnotationScreen(orchestrator: widget.orchestrator)],
              8 => [
                VoiceFilterScreen(
                  orchestrator: widget.orchestrator,
                  settings: s,
                  microphones: _microphones,
                ),
              ],
              7 => [
                MeetingsScreen(
                  orchestrator: widget.orchestrator,
                  transcription: ts,
                  grammar: widget.grammarService,
                  settings: s,
                ),
              ],
              5 => _privacy(),
              12 => _commandsPage(),
              13 => _apiPage(),
              _ => _features(),
            },
        ],
      ),
    ),
  );

  Future<void> _changeGgufModel(String value) async {
    await ts.unloadModel();
    await s.setGgufModel(value);
    await ts.switchEngine(SttEngine.gguf);
    if (!ts.isLoaded) throw StateError(ts.statusMessage);
    await _loadSystemState();
  }

  Future<void> _browseModels() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => ModelCatalogDialog(
        selected: s.ggufModel,
        imported: {for (final model in _customModels) model.id: model.name},
      ),
    );
    if (!mounted || locked || selected == null || selected == s.ggufModel) {
      return;
    }
    await _run(() => _changeGgufModel(selected));
  }

  List<GgufModel> get _visibleModels {
    final values = ggufCatalog
        .where(
          (m) =>
              m.id == s.ggufModel ||
              (m.name.toLowerCase().contains(_modelQuery.toLowerCase()) &&
                  (!_languageOnly ||
                      speechModelMetadata[m.id]?.supports(s.language) ==
                          true) &&
                  (!_downloadedOnly ||
                      File(
                        '${ProjectStorage.instance.models.path}/gguf/${m.id}/${m.filename}',
                      ).existsSync())),
        )
        .toList();
    values.sort(
      (a, b) => _modelSort == 'size'
          ? a.bytes.compareTo(b.bytes)
          : _modelSort == 'active' &&
                (a.id == s.ggufModel || b.id == s.ggufModel)
          ? (a.id == s.ggufModel ? -1 : 1)
          : a.name.compareTo(b.name),
    );
    return values;
  }

  List<Widget> _general() => [
    if (!s.option('onboardingComplete'))
      OnboardingCard(orchestrator: widget.orchestrator, settings: s),
    if (widget.hotkeyService.configurationError != null)
      _note(widget.hotkeyService.configurationError!, expanded: true),
    PreferenceGroup(
      children: [
        PreferenceRow(
          icon: Icons.keyboard_outlined,
          title: tr("Dictation shortcut"),
          trailing: _select(
            s.hotkeyType,
            {
              0: tr("Double Control  ⌃⌃"),
              1: tr("Triple Control  ⌃⌃⌃"),
              2: tr("⌘ ⇧ Space"),
              3: tr("Custom shortcut"),
              4: '⌥ T',
              5: tr("Option ⌥ (default)"),
            },
            (v) async {
              await widget.hotkeyService.saveType(v);
              if (v < 2) await s.setHoldShortcut(false);
            },
            disabled: locked,
          ),
        ),
        PreferenceRow(
          icon: Icons.touch_app_outlined,
          title: tr("Shortcut mode"),
          subtitle: tr(
            s.holdShortcut ? 'Release to finish.' : 'Repeat to finish.',
          ),
          trailing: _select(
            s.holdShortcut,
            {
              false: tr("Toggle"),
              if (s.hotkeyType >= 2) true: 'Hold to dictate',
            },
            (v) async {
              await s.setHoldShortcut(v);
              await widget.hotkeyService.updateHotkey();
            },
            disabled: locked,
          ),
        ),
        PreferenceRow(
          icon: Icons.graphic_eq,
          title: tr("Speech model"),
          subtitle: ts.isLoading
              ? ts.statusMessage
              : ts.isLoaded
              ? tr("Ready on this Mac")
              : tr("Not loaded • choose a model to get started"),
          trailing: TextButton(
            onPressed: () => _selectPage(1),
            child: Text(ts.modelLabel),
          ),
        ),
        PreferenceRow(
          icon: Icons.mic_none_rounded,
          title: tr("Microphone"),
          trailing: _select(
            s.microphoneId,
            {
              '': tr("System default"),
              for (final mic in _microphones) mic.id: mic.label,
              if (s.microphoneId.isNotEmpty &&
                  !_microphones.any((m) => m.id == s.microphoneId))
                s.microphoneId: '${s.microphoneLabel} (disconnected)',
            },
            (v) async {
              await s.setMicrophone(
                v,
                v.isEmpty
                    ? 'System default'
                    : _microphones.firstWhere((m) => m.id == v).label,
              );
            },
            disabled: locked,
          ),
        ),
      ],
    ),
    _heading(tr("Preferences")),
    PreferenceGroup(
      children: [
        PreferenceRow(
          icon: Icons.language,
          title: tr("Interface language"),
          subtitle: tr("Speech language is in Dictation."),
          trailing: _select(
            s.interfaceLanguage,
            {...interfaceLanguages, 'system': tr('System')},
            (value) async {
              await s.setInterfaceLanguage(value);
              await AppLocalizations.instance.setPreference(value);
              widget.orchestrator.refreshPreferences();
            },
          ),
        ),
        PreferenceRow(
          icon: Icons.palette_outlined,
          title: tr("Appearance"),
          trailing: _select(
            s.appearance,
            {
              'system': tr("Follow system"),
              'light': tr("Light"),
              'dark': tr("Dark"),
            },
            (value) async {
              await s.setAppearance(value);
              widget.orchestrator.refreshPreferences();
            },
          ),
        ),
        _switch(
          Icons.content_copy,
          tr("Copy only"),
          tr("Copy instead of paste."),
          s.copyOnly,
          s.setCopyOnly,
        ),
      ],
    ),
    _heading(tr("Permissions")),
    PreferenceGroup(
      children: [
        PreferenceRow(
          icon: _ax ? Icons.verified_outlined : Icons.lock_outline,
          title: tr("Accessibility"),
          subtitle: _ax
              ? tr("Allowed • insert text into other apps")
              : tr("Required to insert text and listen for Control taps."),
          trailing: TextButton(
            onPressed: () => _run(() async {
              if (!_ax) {
                await widget.accessibility.requestPermission();
              }
              await _loadSystemState();
            }),
            child: Text(_ax ? tr("Refresh") : tr("Grant access")),
          ),
        ),
      ],
    ),
    _advanced(tr("Appearance"), [
      PreferenceGroup(
        children: [
          _switch(
            Icons.vertical_align_bottom,
            tr("Dictation indicator"),
            tr("Show recording status."),
            s.showIndicator,
            s.setShowIndicator,
          ),
          PreferenceRow(
            icon: Icons.vertical_align_center,
            title: tr("Indicator position"),
            trailing: _select(
              s.indicatorAtTop,
              {true: tr("Top of screen"), false: tr("Bottom of screen")},
              s.setIndicatorAtTop,
              disabled: locked || !s.showIndicator,
            ),
          ),
          _switch(
            Icons.vertical_align_top,
            tr("Notch indicator"),
            tr("Use the space below the notch."),
            s.notchIndicator,
            s.setNotchIndicator,
          ),
          _switch(
            Icons.power_settings_new,
            tr("Launch at login"),
            tr("Start when you sign in."),
            _login,
            (v) async {
              final enabled =
                  await channel.invokeMethod<bool>('setLaunchAtLogin', v) ??
                  false;
              if (mounted) setState(() => _login = enabled);
            },
          ),
        ],
      ),
      PreferenceGroup(
        children: [
          _switch(
            Icons.visibility_off_outlined,
            tr("Hide menu bar icon"),
            tr("Shortcuts stay active."),
            s.option('hideMenuBarIcon'),
            (v) async {
              await s.setOption('hideMenuBarIcon', v);
              widget.orchestrator.refreshPreferences();
            },
          ),
          _switch(
            Icons.close,
            tr("Command-Q closes Settings"),
            tr("Keep dictation running."),
            s.option('quitClosesWindow'),
            (v) async {
              await s.setOption('quitClosesWindow', v);
              await const MethodChannel('com.aurascribe/window')
                  .invokeMethod<void>('configure', v);
            },
          ),
        ],
      ),
    ]),
    _advanced(tr("Shortcuts"), [
      _heading(tr("Shortcut behavior")),
      PreferenceGroup(
        children: [
          for (final entry in const {
            'sidedChords': 'Record left and right modifiers separately',
            'tapOrHold': 'Hold a toggle shortcut to stop on release',
            'doubleTapModifier': 'Double-tap the main modifier shortcut',
            'shareShortcut': 'Share shortcuts with the focused app',
            'capsLock': 'Caps Lock starts and stops dictation',
          }.entries)
            _switch(
              Icons.keyboard,
              tr(entry.value),
              tr("Applies to configured global shortcuts."),
              s.option(entry.key),
              (v) async {
                await s.setOption(entry.key, v);
                await widget.hotkeyService.updateHotkey();
              },
            ),
          PreferenceRow(
            icon: Icons.mouse,
            title: tr("Mouse dictation shortcut"),
            trailing: _select(
              s.optionText('mouseButton', '-1'),
              {
                '-1': tr("Off"),
                '2': tr("Middle button"),
                '3': tr("Button 4"),
                '4': tr("Button 5"),
              },
              (v) async {
                await s.setOptionText('mouseButton', v);
                await widget.hotkeyService.updateHotkey();
              },
            ),
          ),
        ],
      ),
      _heading(tr("Global shortcuts")),
      PreferenceGroup(
        children: [
          for (final action in ShortcutAction.values)
            PreferenceRow(
              icon: Icons.keyboard_outlined,
              title: tr(action.label),
              trailing: TextButton(
                onPressed: locked
                    ? null
                    : () => _run(() async {
                        await widget.hotkeyService.suspendForRecorder();
                        ShortcutBinding? binding;
                        try {
                          if (!mounted) return;
                          binding = await _showSettingsDialog<ShortcutBinding>(
                            builder: (_) => ShortcutRecorder(
                              action: action,
                              sided: s.option('sidedChords'),
                            ),
                          );
                        } finally {
                          await widget.hotkeyService.updateHotkey();
                        }
                        if (binding != null && mounted) {
                          await widget.hotkeyService.saveBinding(
                            action,
                            binding,
                          );
                        }
                      }),
                child: Text(s.shortcuts[action]!.label),
              ),
            ),
        ],
      ),
      PreferenceGroup(
        children: [
          for (final action in ShortcutAction.values.where(
            (a) => a.isOptional,
          )) ...[
            _switch(
              Icons.keyboard,
              tr("Enable {v0}", values: {"v0": action.label}),
              tr("Register this additional shortcut."),
              s.extraShortcutEnabled(action),
              (v) async {
                await s.setExtraShortcutEnabled(action, v);
                await widget.hotkeyService.updateHotkey();
              },
            ),
            if (action.isAdditionalDictation)
              _switch(
                Icons.touch_app,
                tr("{v0}: hold to speak", values: {"v0": action.label}),
                tr("Off uses toggle activation."),
                s.extraShortcutHold(action),
                (v) async {
                  await s.setExtraShortcutHold(action, v);
                  await widget.hotkeyService.updateHotkey();
                },
              ),
          ],
        ],
      ),
      TextButton(
        onPressed: locked
            ? null
            : () => _run(
                () => widget.hotkeyService.saveBinding(
                  ShortcutAction.pasteLast,
                  ShortcutBinding.defaults[ShortcutAction.pasteLast]!,
                ),
              ),
        child: Text(tr("Restore paste-last shortcut")),
      ),
    ]),
    _advanced(tr("Sound"), [
      PreferenceGroup(
        children: [
          PreferenceRow(
            icon: Icons.volume_up_outlined,
            title: tr("Sound volume"),
            subtitle: s.soundVolume == 0
                ? tr("Silent")
                : '${(s.soundVolume * 100).round()}%',
            trailing: Slider(
              value: s.soundVolume,
              divisions: 10,
              onChanged: (v) {
                SoundService.volume = v;
                _change(s.setSoundVolume(v));
              },
            ),
          ),
          PreferenceRow(
            icon: Icons.music_note_outlined,
            title: tr("Start & stop sounds"),
            subtitle: tr(
              "A rising tone means ready; a falling tone means stopped.",
            ),
            trailing: TextButton(
              onPressed: locked || s.soundVolume == 0
                  ? null
                  : () => _run(() async {
                      await SoundService.playStart();
                      await SoundService.playStop();
                    }),
              child: Text(tr("Preview sounds")),
            ),
          ),
        ],
      ),
    ]),
    _advanced(tr("Memory"), [
      PreferenceGroup(
        children: [
          _switch(
            Icons.memory_outlined,
            tr("Preload speech model"),
            tr(
              "Prepare the selected model on next launch. Low-memory mode can still add processing time.",
            ),
            s.preloadModel,
            s.setPreloadModel,
          ),
        ],
      ),
      PreferenceGroup(
        children: [
          _switch(
            Icons.memory_outlined,
            tr("Release models when idle"),
            tr(
              "Moonshine releases model memory after each clip; other models unload after inactivity. Reloading adds processing time.",
            ),
            s.unloadIdleModels,
            (value) async {
              await s.setUnloadIdleModels(value);
              if (ts.activeEngine == SttEngine.moonshine) {
                await ts.unloadModel();
              }
              ts.memory?.configure(
                enabled: value,
                delay: Duration(seconds: s.modelIdleSeconds),
              );
            },
          ),
          if (s.unloadIdleModels)
            PreferenceRow(
              icon: Icons.timer_outlined,
              title: tr("Release after"),
              trailing: _select(
                s.modelIdleSeconds,
                {
                  15: tr("15 seconds"),
                  60: tr("1 minute"),
                  300: tr("5 minutes"),
                  if (![15, 60, 300].contains(s.modelIdleSeconds))
                    s.modelIdleSeconds: '${s.modelIdleSeconds} seconds',
                },
                (value) async {
                  await s.setModelIdleSeconds(value);
                  ts.memory?.configure(
                    enabled: true,
                    delay: Duration(seconds: value),
                  );
                },
                disabled: locked,
              ),
            ),
        ],
      ),
    ]),
    _advanced(tr("Other audio"), [
      PreferenceGroup(
        children: [
          _switch(
            Icons.speaker,
            tr("Audio changes only on built-in speakers"),
            tr("Keep headphones unchanged."),
            s.speakersOnly,
            s.setSpeakersOnly,
          ),
        ],
      ),
      PreferenceGroup(
        children: [
          PreferenceRow(
            icon: Icons.volume_down_outlined,
            title: tr("Recording audio"),
            trailing: _select(
              s.recordingAudio,
              {
                'unchanged': tr("Leave unchanged"),
                'duck': tr("Lower volume"),
                'mute': tr("Mute"),
              },
              (v) async {
                await s.setRecordingAudio(v);
              },
              disabled: locked,
            ),
          ),
          if (s.recordingAudio == 'duck')
            PreferenceRow(
              icon: Icons.tune,
              title: tr("Volume while recording"),
              subtitle: tr(
                "{v0}% of current output volume",
                values: {"v0": (s.duckLevel * 100).round()},
              ),
              trailing: Slider(
                value: s.duckLevel,
                divisions: 10,
                onChanged: locked ? null : (v) => _change(s.setDuckLevel(v)),
              ),
            ),
        ],
      ),
    ]),
    if (s.option('onboardingComplete')) _resetSetup(),
  ];

  List<Widget> _models() => [
    _note(tr("One model at a time. Sizes shown are downloads.")),
    PreferenceGroup(
      children: [
        PreferenceRow(
          icon: ts.isLoaded
              ? Icons.check_circle_outline
              : Icons.download_outlined,
          title: ts.modelLabel,
          subtitle: ts.isLoading
              ? ts.statusMessage
              : ts.statusMessage.isNotEmpty
              ? ts.statusMessage
              : ts.isLoaded
              ? tr("Loaded and ready")
              : tr("Load now or on first dictation."),
          trailing: TextButton(
            onPressed: locked
                ? null
                : () => _run(() async {
                    final error = await ts.ensureLoaded();
                    if (error != null) throw StateError(error);
                    widget.grammarService.attachSttModel(
                      ts.sharedGemmaModelForGrammar,
                    );
                    await _loadSystemState();
                  }),
            child: Text(ts.isLoaded ? tr("Ready") : tr("Download & load")),
          ),
        ),
      ],
    ),
    _advanced(tr("Engine"), [
      for (final engine in SttEngine.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: PreferenceGroup(
            children: [
              PreferenceRow(
                icon: engine == ts.activeEngine
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                title: switch (engine) {
                  SttEngine.apple => 'Apple Speech',
                  SttEngine.gguf => 'Full GGUF speech catalog',
                  SttEngine.whisper => 'Whisper',
                  SttEngine.gemma => 'Gemma 4 E2B',
                  SttEngine.nemotron => 'Nemotron 3.5',
                  SttEngine.moonshine => 'Moonshine Tiny INT8',
                },
                subtitle: switch (engine) {
                  SttEngine.apple => 'Uses installed macOS on-device speech assets. Server recognition is disabled.',
                  SttEngine.gguf => 'Parakeet, Orukeet, Granite, Qwen, SenseVoice, Cohere, GigaAM and custom GGUF models',
                  SttEngine.whisper =>
                    '75 MB–466 MB • CPU • English or multilingual',
                  SttEngine.gemma => 'GPU • 16 GB system memory recommended',
                  SttEngine.nemotron =>
                    '0.6B parameters • INT8 • true streaming • English',
                  SttEngine.moonshine =>
                    'About 120 MB of weights • CPU • English • clip-based',
                },
                trailing: TextButton(
                  onPressed: locked
                      ? null
                      : () => _run(() async {
                          await widget.grammarService.unloadModel();
                          await ts.switchEngine(engine);
                          widget.grammarService.attachSttModel(
                            ts.sharedGemmaModelForGrammar,
                          );
                          if (!ts.isLoaded) {
                            throw StateError(
                              ts.statusMessage.isEmpty
                                  ? 'Model could not load. Check connection and access token.'
                                  : ts.statusMessage,
                            );
                          }
                          await _loadSystemState();
                        }),
                  child: Text(
                    engine == ts.activeEngine
                        ? tr("Selected")
                        : tr("Use model"),
                  ),
                ),
              ),
            ],
          ),
        ),
    ]),
    if (ts.activeEngine == SttEngine.whisper)
      PreferenceGroup(
        children: [
          PreferenceRow(
            icon: Icons.data_usage,
            title: tr("Whisper size"),
            trailing: _select(
              s.whisperModelIndex,
              {
                0: tr("Tiny English • 75 MB"),
                3: tr("Tiny multilingual • 75 MB"),
                1: tr("Base • 142 MB"),
                2: tr("Small • 466 MB"),
              },
              (v) async {
                await s.setWhisperModelIndex(v);
                await ts.reloadModelIfNeeded();
                if (!ts.isLoaded) {
                  throw StateError('Could not load selected Whisper model.');
                }
              },
              disabled: locked,
            ),
          ),
        ],
      ),
    if (ts.activeEngine == SttEngine.gguf) ...[
      _heading(tr("GGUF speech catalog")),
      PreferenceGroup(
        children: [
          PreferenceRow(
            icon: Icons.library_music_outlined,
            title: tr("Catalog or imported model"),
            trailing: _select(
              s.ggufModel,
              {
                for (final model in _visibleModels)
                  model.id:
                      '${model.name} • ${(model.bytes / 1048576).round()} MB',
                for (final model in _customModels) model.id: model.name,
              },
              _changeGgufModel,
              disabled: locked,
            ),
          ),
        ],
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('browse-all-models'),
          icon: const Icon(Icons.view_list_outlined, size: 16),
          label: Text(
            tr(
              'Browse all models ({v0})',
              values: {'v0': ggufCatalog.length + _customModels.length},
            ),
          ),
          onPressed: locked || _busy ? null : _browseModels,
        ),
      ),
      _advanced(tr("Filters"), [
        TextField(
          decoration: InputDecoration(labelText: tr("Filter speech models")),
          onChanged: (value) => setState(() => _modelQuery = value),
        ),
        Row(
          children: [
            Expanded(
              child: _select(
                _modelSort,
                {
                  'name': tr("Sort by name"),
                  'size': tr("Smallest first"),
                  'active': tr("Active first"),
                },
                (value) async {
                  setState(() => _modelSort = value);
                },
              ),
            ),
            const SizedBox(width: 12),
            FilterChip(
              label: Text(tr("Downloaded")),
              selected: _downloadedOnly,
              onSelected: (value) => setState(() => _downloadedOnly = value),
            ),
          ],
        ),
        FilterChip(
          label: Text(tr("For language: {v0}", values: {"v0": s.language})),
          selected: _languageOnly,
          onSelected: (v) => setState(() => _languageOnly = v),
        ),
      ]),
      if (speechModelMetadata[s.ggufModel] case final metadata?) ...[
        _note(
          tr(
            "Languages: {v0}. {v1}",
            values: {
              "v0": metadata.languages
                  .map((code) => speechLanguages[code] ?? code)
                  .join(', '),
              "v1": metadata.acceptsHint ? 'Accepts a language hint.' : 'Recognizes its supported languages without a language hint.',
            },
          ),
        ),
        if (metadata.benchmark case final benchmark?)
          ExpansionTile(
            // Keep expansion state separate from the enclosing page's scroll
            // offset, which PageStorage restores as a double.
            key: const PageStorageKey('published-benchmark-details'),
            title: Text(tr("Published benchmark details")),
            children: [
              SelectableText(
                key: const PageStorageKey('published-benchmark-text'),
                tr(
                  "{v0}% {v1} • {v2}\nDataset: {v3}\nSource: {v4}\nRevision: {v5}\nHardware: {v6}\nUtterances: {v7}; batch: {v8}; timestamps: {v9}",
                  values: {
                    "v0": benchmark['value'],
                    "v1": benchmark['metric'],
                    "v2": benchmark['language'],
                    "v3": benchmark['dataset'] ?? 'Not recorded',
                    "v4": benchmark['source'] ?? 'Not recorded',
                    "v5": benchmark['source_revision'] ?? 'Not recorded',
                    "v6": benchmark['hardware'] ?? 'Not recorded',
                    "v7": benchmark['utterances'] ?? 'Not recorded',
                    "v8": benchmark['batch_size'] ?? 'Not recorded',
                    "v9": benchmark['timestamps'] ?? 'Not recorded',
                  },
                ),
              ),
              Text(
                tr(
                  "Published upstream; different languages and datasets are not comparable. These are not measurements on this Mac.",
                ),
              ),
            ],
          ),
      ],
    ],
    _advanced(tr("Custom models"), [
      TextButton.icon(
        onPressed: locked
            ? null
            : () => _run(() async {
                final path = await channel.invokeMethod<String>(
                  'chooseSpeechModel',
                );
                if (path == null) return;
                final model = await CustomModelStore().importFile(
                  path,
                  inPlace: s.option('modelInPlace'),
                );
                _customModels = await CustomModelStore().read();
                await ts.unloadModel();
                await s.setGgufModel(model.id);
              }),
        icon: const Icon(Icons.file_open_outlined),
        label: Text(tr("Import GGUF speech model")),
      ),
      _switch(
        Icons.link,
        tr("Reference an existing project model"),
        tr(
          "Imports keep the file in place inside this project’s .aurascribe/models folder.",
        ),
        s.option('modelInPlace'),
        (v) => s.setOption('modelInPlace', v),
      ),
    ]),
    _advanced(tr("Keyboard switching"), [
      _note(
        tr(
          "Select a speech model for an enabled keyboard input source. The mapping is applied when dictation starts.",
        ),
      ),
      PreferenceGroup(
        children: [
          for (final source in _keyboardSources)
            PreferenceRow(
              icon: Icons.language,
              title: source['name'] ?? source['id']!,
              trailing: _select(
                s.keyboardModels[source['id']] ?? '',
                {
                  '': tr("Keep current model"),
                  'whisper': tr("Whisper"),
                  'moonshine': tr("Moonshine Tiny"),
                  'gemma': tr("Gemma"),
                  'nemotron': tr("Nemotron"),
                  'apple': tr("Apple Speech (on device)"),
                  for (final model in ggufCatalog)
                    'gguf:${model.id}': model.name,
                  for (final model in _customModels)
                    'gguf:${model.id}': model.name,
                },
                (value) => s.setKeyboardModel(source['id']!, value),
                disabled: locked,
              ),
            ),
        ],
      ),
    ]),
    _advanced(tr("Benchmarks"), [
      _note(tr("Compare models with a short WAV.")),
      TextButton.icon(
        onPressed: locked
            ? null
            : () => _run(() async {
                final path = await channel.invokeMethod<String>(
                  'chooseBenchmarkAudio',
                );
                if (path == null) return;
                if (!widget.orchestrator.isAvailable) {
                  throw StateError('Finish the current audio task first.');
                }
                widget.orchestrator.externalActivity = 'Model benchmark';
                try {
                  await ModelBenchmark(ts).run(path);
                } finally {
                  widget.orchestrator.externalActivity = null;
                }
                _benchmarks = await ModelBenchmark(ts).read();
              }),
        icon: const Icon(Icons.speed),
        label: Text(tr("Benchmark selected model")),
      ),
      for (final result in _benchmarks)
        PreferenceGroup(
          children: [
            PreferenceRow(
              icon: Icons.timer_outlined,
              title: tr(
                "{v0} • {v1} ms",
                values: {"v0": result['model'], "v1": result['decodeMs']},
              ),
              subtitle: tr(
                "Load {v0} ms • {v1} bytes • {v2}",
                values: {
                  "v0": result['loadMs'],
                  "v1": result['sampleBytes'],
                  "v2": result['time'],
                },
              ),
            ),
          ],
        ),
    ]),
    _advanced(tr("Memory"), [
      PreferenceGroup(
        children: [
          PreferenceRow(
            icon: Icons.memory_outlined,
            title: tr("Unload models"),
            subtitle: tr(
              "Release speech and cleanup models. The files stay available for next time.",
            ),
            trailing: TextButton(
              onPressed: locked
                  ? null
                  : () => _run(() async {
                      await widget.grammarService.unloadModel();
                      await ts.unloadModel();
                    }),
              child: Text(tr("Unload")),
            ),
          ),
        ],
      ),
    ]),
  ];

  List<Widget> _output() => [
    PreferenceGroup(
      children: [
        PreferenceRow(
          icon: Icons.notes_outlined,
          title: tr("Dictation mode"),
          trailing: _select(
            s.dictationMode,
            {
              DictationMode.liveTyping: tr("Live typing"),
              DictationMode.enhancedAccuracy: tr("Finish, then insert"),
            },
            (v) async {
              await s.setDictationMode(v);
            },
            disabled: locked,
          ),
        ),
        _switch(
          Icons.auto_fix_high_outlined,
          tr("Grammar cleanup"),
          tr("Uses a separate cleanup model."),
          s.grammarEnabled,
          (v) async {
            await s.setGrammarEnabled(v);
            if (!v) await widget.grammarService.unloadModel();
          },
        ),
        PreferenceRow(
          icon: Icons.language,
          title: tr("Language"),
          subtitle: tr("For models with language support."),
          trailing: _select(
            s.language,
            {...speechLanguages, 'auto': tr("Detect automatically")},
            (v) async {
              await s.setLanguage(v);
            },
            disabled: locked,
          ),
        ),
        _switch(
          Icons.content_paste_outlined,
          tr("Clipboard fallback notice"),
          tr("Show paste fallback notices."),
          s.fallbackNotify,
          s.setFallbackNotify,
        ),
        PreferenceRow(
          icon: Icons.keyboard_outlined,
          title: tr("Paste last dictation"),
          subtitle: tr("Paste your last transcript."),
          trailing: const Text('⌘ ⌥ ⇧ V', style: TextStyle(fontSize: 12)),
        ),
      ],
    ),
    _advanced(tr("Paste behavior"), [
      PreferenceGroup(
        children: [
          _switch(
            Icons.terminal,
            tr("Terminal paste shortcut"),
            tr(
              "Use Control + Shift + V in recognized terminal apps. Otherwise use Command + V.",
            ),
            s.terminalPaste,
            s.setTerminalPaste,
          ),
          _switch(
            Icons.content_paste_go_outlined,
            tr("Restore clipboard after paste"),
            tr("Restore only if no other app has changed the clipboard."),
            s.restoreClipboard,
            s.setRestoreClipboard,
          ),
        ],
      ),
    ]),
    _advanced(tr("Pipelines"), [
      for (final profile in _profiles)
        PreferenceGroup(
          children: [
            PreferenceRow(
              icon: Icons.account_tree_outlined,
              title: profile.application == '*'
                  ? tr("Default • every app")
                  : profile.application,
              subtitle: profile.steps.map((step) => step.kind.name).join(' → '),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: tr("Edit pipeline"),
                    onPressed: locked ? null : () => _editPipeline(profile),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: tr("Delete pipeline"),
                    onPressed: locked
                        ? null
                        : () => _run(() async {
                            final next = [..._profiles]..remove(profile);
                            await PipelineStore().save(next);
                            _profiles = next;
                          }),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ],
        ),
      TextButton.icon(
        onPressed: locked ? null : () => _editPipeline(),
        icon: const Icon(Icons.add),
        label: Text(tr("Add application pipeline")),
      ),
      TextButton(
        onPressed: () => _run(() async {
          final file = await PipelineStore().file;
          if (!await file.exists()) await PipelineStore().save([]);
          await Process.run('open', ['-R', file.path]);
        }),
        child: Text(tr("Show pipeline file for editing")),
      ),
      OutputPreview(
        orchestrator: widget.orchestrator,
        settings: s,
        onVocabulary: () => _selectPage(3),
      ),
    ]),
    _advanced(tr("Recording limits"), [
      PreferenceGroup(
        children: [
          _switch(
            Icons.pause_circle_outline,
            tr("Stop after silence"),
            tr(
              "Finish a toggle recording after a quiet pause. Hold mode finishes on key release.",
            ),
            s.autoStop,
            s.setAutoStop,
          ),
          PreferenceRow(
            icon: Icons.timer_outlined,
            title: tr("Silence duration"),
            subtitle: tr("{v0} ms", values: {"v0": s.vadSilenceDuration}),
            trailing: Slider(
              value: s.vadSilenceDuration.toDouble().clamp(500, 3000),
              min: 500,
              max: 3000,
              divisions: 25,
              onChanged: (v) => _change(s.setVadSilenceDuration(v.round())),
            ),
          ),
          PreferenceRow(
            icon: Icons.multitrack_audio,
            title: tr("Silence threshold"),
            subtitle: tr("{v0} dBFS", values: {"v0": s.vadThreshold.round()}),
            trailing: Slider(
              value: s.vadThreshold.clamp(-60, -10),
              min: -60,
              max: -10,
              divisions: 50,
              onChanged: (v) => _change(s.setVadThreshold(v)),
            ),
          ),
          PreferenceRow(
            icon: Icons.timelapse,
            title: tr("Maximum recording"),
            subtitle: tr(
              "{v0} seconds • shorter clips use less memory",
              values: {"v0": s.maxRecordingSeconds},
            ),
            trailing: Slider(
              value: s.maxRecordingSeconds.toDouble().clamp(15, 90),
              min: 15,
              max: 90,
              divisions: 15,
              onChanged: (v) => _change(s.setMaxRecordingSeconds(v.round())),
            ),
          ),
        ],
      ),
    ]),
    _textTools(),
  ];

  Future<void> _editPipeline([OutputProfile? profile]) async {
    final result = await _showSettingsDialog<OutputProfile>(
      builder: (_) => PipelineEditor(profile: profile),
    );
    if (result == null || !mounted) return;
    await _run(() async {
      final next = [..._profiles];
      if (profile != null) next.remove(profile);
      next.add(result);
      await PipelineStore().save(next);
      _profiles = next;
    });
  }

  List<Widget> _words() => [
    _heading(tr("Decoder vocabulary")),
    _note(tr("One name or term per line.")),
    TextField(
      controller: _decoderWords,
      minLines: 3,
      maxLines: 7,
      decoration: InputDecoration(labelText: tr("Recognition vocabulary")),
    ),
    Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: () => _run(() => s.setDecoderVocabulary(_decoderWords.text)),
        child: Text(tr("Save recognition vocabulary")),
      ),
    ),
    _note(
      tr(
        "Correct recurring names and terms without loading another model. Replacements apply in Finish, then insert mode.",
      ),
    ),
    PreferenceGroup(
      children: [
        PreferenceRow(
          icon: Icons.spellcheck,
          title: tr("Vocabulary replacements"),
          subtitle: tr("One rule per line: heard = replacement."),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: TextField(
            controller: _vocabulary,
            minLines: 8,
            maxLines: 14,
            decoration: InputDecoration(
              labelText: tr("Replacements"),
              hintText: tr("aura scribe = AuraScribe"),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      await s.setVocabulary(_vocabulary.text);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(tr("Vocabulary saved"))),
                        );
                      }
                    }),
              child: Text(tr("Save vocabulary")),
            ),
          ),
        ),
      ],
    ),
    _note(tr("Replace words after recognition.")),
  ];

  Future<void> _editHistory(DictationEntry entry) async {
    final controller = TextEditingController(text: entry.text);
    final route = DialogRoute<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr("Edit transcript")),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 4,
            maxLines: 12,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr("Cancel")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(tr("Save")),
          ),
        ],
      ),
    );
    final text = await Navigator.of(context).push(route);
    await route.completed;
    controller.dispose();
    if (text != null && mounted) {
      await _run(() => HistoryService.instance.replace(entry, text));
    }
  }

  Future<void> _historyAction(DictationEntry entry, String action) async {
    if (action == 'stop') {
      await const MethodChannel('com.aurascribe/capture')
          .invokeMethod<void>('stopAudio');
      return;
    }
    if (action == 'play') {
      final file = await HistoryService.instance.audioFile(entry);
      if (file == null) throw StateError('Recording is missing.');
      await const MethodChannel('com.aurascribe/capture')
          .invokeMethod<void>('playAudio', file.path);
      return;
    }
    var language = s.language;
    final chosen = await _showSettingsDialog<String>(
      builder: (context) => AlertDialog(
        title: Text(tr("Transcribe again")),
        content: TextFormField(
          initialValue: language,
          decoration: InputDecoration(
            labelText: tr("Language code"),
            helperText: tr("Model: {v0}", values: {"v0": ts.modelLabel}),
          ),
          onChanged: (v) => language = v.trim(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr("Cancel")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, language),
            child: Text(tr("Transcribe")),
          ),
        ],
      ),
    );
    if (chosen != null) {
      await widget.orchestrator.transcribeHistory(entry, chosen);
    }
  }

  List<Widget> _history() {
    final entries = HistoryService.instance.entries
        .where((e) => e.text.toLowerCase().contains(_search.text.toLowerCase()))
        .toList();
    return [
      PreferenceGroup(
        children: [
          _switch(
            Icons.mic,
            tr("Keep recordings"),
            tr("Save audio for playback."),
            s.keepHistoryAudio,
            s.setKeepHistoryAudio,
          ),
          PreferenceRow(
            icon: Icons.analytics_outlined,
            title: tr("{v0} dictations", values: {"v0": entries.length}),
            subtitle: tr(
              "{v0} words in the current view",
              values: {
                "v0": entries.fold<int>(
                  0,
                  (n, e) =>
                      n +
                      e.text
                          .split(RegExp(r"\s+"))
                          .where((w) => w.isNotEmpty)
                          .length,
                ),
              },
            ),
          ),
        ],
      ),
      PreferenceGroup(
        children: [
          _switch(
            Icons.history,
            tr("Save dictation history"),
            tr("Save up to 100 transcripts."),
            s.historyEnabled,
            s.setHistoryEnabled,
          ),
          PreferenceRow(
            icon: Icons.schedule,
            title: tr("Keep history"),
            subtitle: tr("Remove older transcripts automatically."),
            trailing: SizedBox(
              width: 160,
              child: _select<int>(
                s.historyRetentionDays,
                {
                  0: tr("Until deleted"),
                  1: tr("1 day"),
                  7: tr("7 days"),
                  30: tr("30 days"),
                  90: tr("90 days"),
                },
                (days) async {
                  await s.setHistoryRetentionDays(days);
                  HistoryService.instance.retentionDays = days;
                  await HistoryService.instance.prune();
                },
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: tr("Search transcripts"),
          prefixIcon: const Icon(Icons.search),
        ),
      ),
      const SizedBox(height: 18),
      if (entries.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(
            children: [
              Icon(
                Icons.history,
                size: 36,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                _search.text.isEmpty
                    ? tr("Your dictations will appear here")
                    : tr("No matching transcripts"),
                style: const TextStyle(fontSize: 16),
              ),
              _note(
                tr(
                  "Enable history, then use your dictation shortcut to speak into another app.",
                ),
              ),
            ],
          ),
        ),
      for (final entry in entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: PreferenceGroup(
            children: [
              PreferenceRow(
                icon: Icons.notes,
                title:
                    '${entry.date.toLocal().toString().substring(0, 16)} • ${entry.model} • ${entry.language}',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (entry.audio != null)
                      PopupMenuButton<String>(
                        tooltip: tr("Recording actions"),
                        onSelected: (v) => _run(() => _historyAction(entry, v)),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'play',
                            child: Text(tr("Play recording")),
                          ),
                          PopupMenuItem(
                            value: 'stop',
                            child: Text(tr("Stop playback")),
                          ),
                          PopupMenuItem(
                            value: 'transcribe',
                            child: Text(tr("Transcribe again…")),
                          ),
                        ],
                      ),
                    IconButton(
                      tooltip: tr("Edit transcript"),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () => _editHistory(entry),
                    ),
                    if (entry.versions.isNotEmpty)
                      PopupMenuButton<String>(
                        tooltip: tr("Restore earlier version"),
                        icon: const Icon(Icons.restore, size: 18),
                        onSelected: (text) => _run(
                          () => HistoryService.instance.replace(entry, text),
                        ),
                        itemBuilder: (_) => [
                          for (final text in entry.versions)
                            PopupMenuItem(
                              value: text,
                              child: SizedBox(
                                width: 280,
                                child: Text(
                                  text,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                        ],
                      ),
                    IconButton(
                      tooltip: tr("Copy transcript"),
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: entry.text)),
                    ),
                    IconButton(
                      tooltip: tr("Delete transcript"),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () =>
                          _run(() => HistoryService.instance.remove(entry)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    entry.text,
                    style: const TextStyle(fontSize: 13, height: 1.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      if (HistoryService.instance.entries.isNotEmpty)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => _run(() => HistoryService.instance.clear()),
            child: Text(tr("Clear history")),
          ),
        ),
    ];
  }

  List<Widget> _privacy() => [
    _note(
      tr(
        "Recognition happens on your Mac. Network access is used to download the models you choose.",
      ),
    ),
    PreferenceGroup(
      children: [
        PreferenceRow(
          icon: Icons.folder_outlined,
          title: tr("Project model storage"),
          subtitle: tr(
            "{v0} MB on disk",
            values: {"v0": (_bytes / 1048576).toStringAsFixed(1)},
          ),
          trailing: TextButton(
            onPressed: () => _run(() async {
              await Process.run('open', [ProjectStorage.instance.models.path]);
            }),
            child: Text(tr("Show in Finder")),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: SelectableText(
            ProjectStorage.instance.models.path,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        PreferenceRow(
          icon: Icons.delete_outline,
          title: tr("Remove downloaded models & caches"),
          subtitle: tr(
            "Unloads models first. The next dictation will download the selected model again.",
          ),
          trailing: TextButton(
            onPressed: locked
                ? null
                : () => _run(() async {
                    await widget.grammarService.unloadModel();
                    await ts.unloadModel();
                    for (final name in ['models', 'runtime', 'cache']) {
                      final dir = await ProjectStorage.instance.directory(name);
                      await dir.delete(recursive: true);
                    }
                    await ProjectStorage.instance.directory('models');
                    await _loadSystemState();
                  }),
            child: Text(tr("Remove")),
          ),
        ),
      ],
    ),
    _note(
      tr(
        "No fallback to ~/Library or a global model cache. If this project moves, rebuild the app from the new location. Existing downloads from older versions are left untouched.",
      ),
    ),
    _heading(tr("Hugging Face access")),
    PreferenceGroup(
      children: [
        PreferenceRow(
          icon: Icons.key_outlined,
          title: tr("Access token"),
          subtitle: tr("For gated models. Saved in Keychain."),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: TextField(
            controller: _token,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(labelText: tr("Hugging Face token")),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => _run(() async {
                await s.setHfToken(_token.text);
              }),
              child: Text(tr("Save token")),
            ),
          ),
        ),
      ],
    ),
  ];

  Future<void> _editCommand([PersonalCommand? command]) async {
    final name = TextEditingController(text: command?.name ?? '');
    final instruction = TextEditingController(text: command?.instruction ?? '');
    final result = await _showSettingsDialog<PersonalCommand>(
      builder: (context) => AlertDialog(
        title: Text(tr("Personal command")),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(labelText: tr("Name")),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: instruction,
                minLines: 4,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: tr("What should happen to the selected text?"),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr("Cancel")),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty || instruction.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(
                context,
                PersonalCommand(
                  command?.id ??
                      DateTime.now().microsecondsSinceEpoch.toString(),
                  name.text.trim(),
                  instruction.text.trim(),
                ),
              );
            },
            child: Text(tr("Save command")),
          ),
        ],
      ),
    );
    name.dispose();
    instruction.dispose();
    if (result == null || !mounted) return;
    await _run(() async {
      final next = [..._commands];
      if (command != null) next.remove(command);
      next.add(result);
      await PersonalCommandStore().save(next);
      _commands = next;
    });
  }

  List<Widget> _updates() {
    final updates = widget.orchestrator.updates;
    return [
      _note(
        tr(
          "Installed version {v0}. Updates come from this project’s GitHub Releases. Installing requires a newer, notarized app signed by the same Developer ID team.",
          values: {"v0": updates.currentVersion},
        ),
      ),
      PreferenceGroup(
        children: [
          _switch(
            Icons.update,
            tr("Check for updates automatically"),
            tr("Check for a stable release every 12 hours."),
            s.automaticUpdates,
            (v) async {
              await s.setAutomaticUpdates(v);
              await updates.configure();
            },
          ),
          _switch(
            Icons.download_outlined,
            tr("Download updates automatically"),
            tr("Download only when GitHub publishes a SHA-256 asset digest."),
            s.downloadUpdates,
            (v) async {
              await s.setDownloadUpdates(v);
              await updates.configure();
            },
          ),
          _switch(
            Icons.install_desktop,
            tr("Install updates when idle"),
            tr(
              "Applies to signed builds in a writable app directory. An earlier app copy is kept for recovery.",
            ),
            s.installUpdates,
            (v) async {
              await s.setInstallUpdates(v);
              await updates.configure();
            },
          ),
        ],
      ),
      _note(localizedStatus(updates.status)),
      if (updates.error.isNotEmpty)
        Text(
          updates.error,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (updates.busy) const LinearProgressIndicator(),
      Wrap(
        spacing: 12,
        children: [
          TextButton(
            onPressed: updates.busy ? null : () => _run(updates.check),
            child: Text(tr("Check now")),
          ),
          if (updates.release != null)
            TextButton(
              onPressed: updates.busy ? null : () => _run(updates.download),
              child: Text(tr("Download verified update")),
            ),
          if (updates.downloaded != null)
            TextButton(
              onPressed: updates.busy || locked
                  ? null
                  : () => _run(updates.install),
              child: Text(tr("Install & restart")),
            ),
        ],
      ),
      if (updates.release != null) SelectableText(updates.release!.notes),
    ];
  }

  Future<void> _revealSection(String label) async {
    final scope = '$_page:$label';
    _sections[scope]?.expand();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final target = _sectionKeys[scope]?.currentContext;
    if (mounted && target != null && target.mounted) {
      await Scrollable.ensureVisible(
        target,
        alignment: .1,
        duration: const Duration(milliseconds: 180),
      );
    }
  }

  Widget _advanced(String label, List<Widget> children) => Padding(
    key: _sectionKeys.putIfAbsent('$_page:$label', GlobalKey.new),
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        controller: _sections.putIfAbsent(
          '$_page:$label',
          ExpansibleController.new,
        ),
        key: PageStorageKey('advanced-$label'),
        title: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        children: [
          // EditableText owns an internal scroll position. Its storage must
          // not inherit the ExpansionTile's boolean expansion-state slot.
          PageStorage(
            bucket: _sectionStorage.putIfAbsent(
              '$_page:$label',
              PageStorageBucket.new,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    ),
  );

  List<Widget> _features() => [
    PreferenceGroup(
      children: [
        for (final feature in optionalSettingsFeatures)
          _switch(
            settingsIcons[feature.page],
            tr(feature.label),
            tr(feature.description),
            s.isSettingsPageVisible(feature.page),
            (value) async {
              await s.setSettingsPageVisible(feature.page, value);
              widget.orchestrator.refreshPreferences();
            },
          ),
      ],
    ),
  ];

  Widget _resetSetup() => TextButton(
    onPressed: () => _run(() async {
      await s.setOption('onboardingComplete', false);
      setState(() => _page = 0);
    }),
    child: Text(tr("Run setup again")),
  );

  List<Widget> _commandsPage() => [
    _note(tr('Select text, then press ⌃ ⇧ C.')),
    for (final command in _commands)
      PreferenceGroup(
        children: [
          PreferenceRow(
            icon: Icons.bookmark_outline,
            title: command.name,
            subtitle: command.instruction,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: tr("Edit command"),
                  onPressed: () => _editCommand(command),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: tr("Delete command"),
                  onPressed: () => _run(() async {
                    final next = [..._commands]..remove(command);
                    await PersonalCommandStore().save(next);
                    _commands = next;
                  }),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ],
      ),
    TextButton.icon(
      onPressed: () => _editCommand(),
      icon: const Icon(Icons.add),
      label: Text(tr("Add personal command")),
    ),
    TextButton(
      onPressed: () => _run(() async {
        final file = await PersonalCommandStore().file;
        if (!await file.exists()) {
          await PersonalCommandStore().save([]);
        }
        await Process.run('open', ['-R', file.path]);
      }),
      child: Text(tr("Show command file for editing")),
    ),
  ];

  List<Widget> _apiPage() => [
    PreferenceGroup(
      children: [
        _switch(
          Icons.api,
          tr("Local API and CLI"),
          tr("Authenticated access for local tools."),
          s.controlApi,
          (value) async {
            await s.setControlApi(value);
            await widget.orchestrator.control.configure();
          },
        ),
      ],
    ),
  ];

  Widget _textTools() => _advanced(tr("Text tools"), [
    PreferenceGroup(
      children: [
        for (final entry in const <String, String>{
          'spokenSymbols': 'Punctuation',
          'spokenFormatting': 'Formatting',
          'fillers': 'Filler words',
          'skipPauses': 'Shorter pauses',
          'smartSpacing': 'Spacing',
          'liveText': 'Live transcript',
          'pauseBrowser': 'Pause media',
        }.entries)
          _switch(
            Icons.tune,
            tr(entry.value),
            tr(
              entry.key == 'fillers'
                  ? 'English only.'
                  : 'For your next dictation.',
            ),
            s.option(entry.key),
            (v) => s.setOption(entry.key, v),
          ),
      ],
    ),
    _switch(
      Icons.reply,
      tr("Return to the original app"),
      tr("Return before pasting."),
      s.option('returnToApp', fallback: true),
      (v) => s.setOption('returnToApp', v),
    ),
  ]);
}
