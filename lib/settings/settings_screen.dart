import 'dart:io';
import 'package:flutter/material.dart';
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
import '../transcription/custom_model_store.dart';
import '../benchmarks/model_benchmark.dart';
import '../meetings/meetings_screen.dart';
import '../audio/voice_filter_screen.dart';
import '../capture/annotation_screen.dart';
import '../diagnostics/playground_screen.dart';
import 'settings_service.dart';
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
  const SettingsScreen(
      {super.key,
      required this.settings,
      required this.hotkeyService,
      required this.accessibility,
      required this.transcriptionService,
      required this.grammarService,
      required this.orchestrator});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  static const channel = MethodChannel('com.aurascribe/accessibility');
  int _page = 0;
  bool _ax = false, _login = false, _busy = false;
  int _bytes = 0;
  String? _error;
  List<InputDevice> _microphones = [];
  List<OutputProfile> _profiles = [];
  List<PersonalCommand> _commands = [];
  List<CustomSpeechModel> _customModels = [];
  List<Map<String, String>> _keyboardSources = [];
  List<Map<String, dynamic>> _benchmarks = [];
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
    widget.orchestrator.updates.addListener(_refresh);
    _decoderWords.text = s.decoderVocabulary;
    _token.text = s.hfToken;
    _vocabulary.text = s.vocabulary;
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
    if (mounted) setState(() {});
  }

  Future<void> _loadSystemState() async {
    try {
      final profiles = await PipelineStore().read();
      final commands = await PersonalCommandStore().read();
      final customModels = await CustomModelStore().read();
      final keyboardSources =
          await channel.invokeListMethod<dynamic>('keyboardSources') ?? [];
      final benchmarks = await ModelBenchmark(ts).read();
      final ax = await widget.accessibility.hasPermission();
      final login = await channel.invokeMethod<bool>('launchAtLogin') ?? false;
      final recorder = AudioRecorder();
      List<InputDevice> devices;
      try {
        devices = await recorder.listInputDevices();
      } finally {
        await recorder.dispose();
      }
      final bytes = await ProjectStorage.instance.modelBytes();
      if (mounted) {
        setState(() {
          _profiles = profiles;
          _commands = commands;
          _customModels = customModels;
          _keyboardSources = keyboardSources
              .map((v) => Map<String, String>.from(v as Map))
              .toList();
          _benchmarks = benchmarks;
          _ax = ax;
          _login = login;
          _microphones = devices;
          _bytes = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not refresh system settings: $e');
      }
    }
  }

  @override
  void dispose() {
    widget.orchestrator.settingsPage = _page;
    widget.orchestrator.updates.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    ts.removeListener(_refresh);
    widget.orchestrator.removeListener(_refresh);
    HistoryService.instance.removeListener(_refresh);
    _decoderWords.dispose();
    _token.dispose();
    _vocabulary.dispose();
    _search.dispose();
    super.dispose();
  }

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

  Widget _note(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(text,
          style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: Theme.of(context).colorScheme.onSurfaceVariant)));
  Widget _heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)));
  Widget _switch(IconData icon, String title, String subtitle, bool value,
          Future<void> Function(bool) onChanged) =>
      PreferenceRow(
          icon: icon,
          title: title,
          subtitle: subtitle,
          trailing: SizedBox(
              width: 52,
              child: Switch.adaptive(
                  value: value,
                  onChanged: _busy ? null : (v) => _run(() => onChanged(v)))));
  Widget _select<T>(
          T value, Map<T, String> options, Future<void> Function(T) change,
          {bool disabled = false}) =>
      DropdownButtonHideUnderline(
          child: DropdownButton<T>(
              value: options.containsKey(value) ? value : null,
              hint: const Text('Choose an available option'),
              isDense: true,
              isExpanded: true,
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
              items: options.entries
                  .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: disabled || _busy
                  ? null
                  : (v) {
                      if (v != null) _run(() => change(v));
                    }));

  @override
  Widget build(BuildContext context) => Scaffold(
      body: SettingsShell(
          selected: _page,
          onSelected: (page) => setState(() => _page = page),
          onDrag: () => windowManager.startDragging(),
          status:
              ts.isLoaded ? '${ts.modelLabel} ready' : 'On-device dictation',
          content:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Material(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: SelectableText(_error!,
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer,
                                  fontSize: 12))))),
            if (_busy || ts.isLoading)
              const Padding(
                  padding: EdgeInsets.only(bottom: 14),
                  child: LinearProgressIndicator()),
            if (ts.isLoading && ProjectStorage.instance.hasActiveDownloads)
              Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                      onPressed: ProjectStorage.instance.cancelDownloads,
                      child: const Text('Cancel model download'))),
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
                      settings: s)
                ],
              10 => _updates(),
              9 => [AnnotationScreen(orchestrator: widget.orchestrator)],
              8 => [
                  VoiceFilterScreen(
                      orchestrator: widget.orchestrator,
                      settings: s,
                      microphones: _microphones)
                ],
              7 => [
                  MeetingsScreen(
                      orchestrator: widget.orchestrator,
                      transcription: ts,
                      grammar: widget.grammarService,
                      settings: s)
                ],
              5 => _privacy(),
              _ => _labs(),
            },
          ])));

  List<Widget> _general() => [
        _note(
            'Speak naturally. Your words stay on your Mac and appear in the app you’re using.'),
        PreferenceGroup(children: [
          PreferenceRow(
              icon: Icons.keyboard_outlined,
              title: 'Dictation shortcut',
              trailing: _select(s.hotkeyType, {
                0: 'Double Control  ⌃⌃',
                1: 'Triple Control  ⌃⌃⌃',
                2: '⌘ ⇧ Space',
                3: 'Custom shortcut',
                4: '⌥ T',
                5: 'Option ⌥ (default)'
              }, (v) async {
                await widget.hotkeyService.saveType(v);
                if (v < 2) await s.setHoldShortcut(false);
              }, disabled: locked)),
          PreferenceRow(
              icon: Icons.touch_app_outlined,
              title: 'Shortcut mode',
              subtitle: s.hotkeyType >= 2
                  ? 'Hold ${s.shortcuts[ShortcutAction.dictation]!.label} to listen; release to stop. Toggle is also available.'
                  : 'Control tap shortcuts start and stop recording.',
              trailing: _select(s.holdShortcut, {
                false: 'Toggle',
                if (s.hotkeyType >= 2) true: 'Hold to dictate'
              }, (v) async {
                await s.setHoldShortcut(v);
                await widget.hotkeyService.updateHotkey();
              }, disabled: locked)),
          PreferenceRow(
              icon: Icons.graphic_eq,
              title: 'Speech model',
              subtitle: ts.isLoading
                  ? ts.statusMessage
                  : ts.isLoaded
                      ? 'Ready on this Mac'
                      : 'Not loaded • choose a model to get started',
              trailing: TextButton(
                  onPressed: () => setState(() => _page = 1),
                  child: Text(ts.modelLabel))),
          PreferenceRow(
              icon: Icons.mic_none_rounded,
              title: 'Microphone',
              trailing: _select(s.microphoneId, {
                '': 'System default',
                for (final mic in _microphones) mic.id: mic.label,
                if (s.microphoneId.isNotEmpty &&
                    !_microphones.any((m) => m.id == s.microphoneId))
                  s.microphoneId: '${s.microphoneLabel} (disconnected)'
              }, (v) async {
                await s.setMicrophone(
                    v,
                    v.isEmpty
                        ? 'System default'
                        : _microphones.firstWhere((m) => m.id == v).label);
              }, disabled: locked)),
          _switch(
              Icons.vertical_align_bottom,
              'Dictation indicator',
              'Show preparation, listening and processing feedback without taking focus.',
              s.showIndicator,
              s.setShowIndicator),
          PreferenceRow(
              icon: Icons.vertical_align_center,
              title: 'Indicator position',
              trailing: _select(
                  s.indicatorAtTop,
                  {true: 'Top of screen', false: 'Bottom of screen'},
                  s.setIndicatorAtTop,
                  disabled: locked || !s.showIndicator)),
          _switch(
              Icons.power_settings_new,
              'Launch at login',
              'Start AuraScribe in the menu bar when you sign in.',
              _login, (v) async {
            final enabled =
                await channel.invokeMethod<bool>('setLaunchAtLogin', v) ??
                    false;
            if (mounted) setState(() => _login = enabled);
          }),
        ]),
        _heading('Global shortcuts'),
        PreferenceGroup(children: [
          for (final action in ShortcutAction.values)
            PreferenceRow(
                icon: Icons.keyboard_outlined,
                title: action.label,
                trailing: TextButton(
                    onPressed: locked
                        ? null
                        : () => _run(() async {
                              await widget.hotkeyService.suspendForRecorder();
                              ShortcutBinding? binding;
                              try {
                                if (!mounted) return;
                                binding = await showDialog<ShortcutBinding>(
                                    context: context,
                                    builder: (_) =>
                                        ShortcutRecorder(action: action));
                              } finally {
                                await widget.hotkeyService.updateHotkey();
                              }
                              if (binding != null && mounted) {
                                await widget.hotkeyService
                                    .saveBinding(action, binding);
                              }
                            }),
                    child: Text(s.shortcuts[action]!.label)))
        ]),
        _heading('Sound & readiness'),
        PreferenceGroup(children: [
          PreferenceRow(
              icon: Icons.volume_up_outlined,
              title: 'Sound volume',
              subtitle: s.soundVolume == 0
                  ? 'Silent'
                  : '${(s.soundVolume * 100).round()}%',
              trailing: Slider(
                  value: s.soundVolume,
                  divisions: 10,
                  onChanged: (v) {
                    SoundService.volume = v;
                    _change(s.setSoundVolume(v));
                  })),
          PreferenceRow(
              icon: Icons.music_note_outlined,
              title: 'Start & stop sounds',
              subtitle:
                  'A rising tone means ready; a falling tone means stopped.',
              trailing: TextButton(
                  onPressed: locked || s.soundVolume == 0
                      ? null
                      : () => _run(() async {
                            await SoundService.playStart();
                            await SoundService.playStop();
                          }),
                  child: const Text('Preview sounds'))),
          _switch(
              Icons.memory_outlined,
              'Preload speech model',
              'Load the selected model on next launch. Off keeps startup memory lower.',
              s.preloadModel,
              s.setPreloadModel),
        ]),
        _heading('Other audio while dictating'),
        PreferenceGroup(children: [
          PreferenceRow(
              icon: Icons.volume_down_outlined,
              title: 'Recording audio',
              trailing: _select(s.recordingAudio, {
                'unchanged': 'Leave unchanged',
                'duck': 'Lower volume',
                'mute': 'Mute'
              }, (v) async {
                await s.setRecordingAudio(v);
              }, disabled: locked)),
          if (s.recordingAudio == 'duck')
            PreferenceRow(
                icon: Icons.tune,
                title: 'Volume while recording',
                subtitle:
                    '${(s.duckLevel * 100).round()}% of current output volume',
                trailing: Slider(
                    value: s.duckLevel,
                    divisions: 10,
                    onChanged:
                        locked ? null : (v) => _change(s.setDuckLevel(v))))
        ]),
        _heading('Permissions'),
        PreferenceGroup(children: [
          PreferenceRow(
              icon: _ax ? Icons.verified_outlined : Icons.lock_outline,
              title: 'Accessibility',
              subtitle: _ax
                  ? 'Allowed • insert text into other apps'
                  : 'Required to insert text and listen for Control taps.',
              trailing: TextButton(
                  onPressed: () => _run(() async {
                        if (!_ax) {
                          await widget.accessibility.requestPermission();
                        }
                        await _loadSystemState();
                      }),
                  child: Text(_ax ? 'Refresh' : 'Grant access')))
        ]),
        _note(
            'Microphone permission is requested when you first dictate. Use ⌃ ⇧ C to rewrite selected text with Smart Commands.'),
      ];

  List<Widget> _models() => [
        _note(
            'One speech engine at a time. Downloads and inference caches stay in this project. Model sizes below are disk sizes, not measured RAM.'),
        PreferenceGroup(children: [
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
                          ? 'Loaded and ready'
                          : 'Loads when you dictate or select Download & load.',
              trailing: TextButton(
                  onPressed: locked
                      ? null
                      : () => _run(() async {
                            final error = await ts.ensureLoaded();
                            if (error != null) throw StateError(error);
                            widget.grammarService
                                .attachSttModel(ts.sharedGemmaModelForGrammar);
                            await _loadSystemState();
                          }),
                  child: Text(ts.isLoaded ? 'Ready' : 'Download & load'))),
        ]),
        const SizedBox(height: 18),
        for (final engine in SttEngine.values)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PreferenceGroup(children: [
                PreferenceRow(
                    icon: engine == ts.activeEngine
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    title: switch (engine) {
                      SttEngine.gguf => 'Full GGUF speech catalog',
                      SttEngine.whisper => 'Whisper',
                      SttEngine.gemma => 'Gemma 4 E2B',
                      SttEngine.nemotron => 'Nemotron 3.5',
                      SttEngine.moonshine => 'Moonshine Tiny INT8'
                    },
                    subtitle: switch (engine) {
                      SttEngine.gguf =>
                        'Parakeet, Qwen, SenseVoice, Cohere, GigaAM and custom GGUF models',
                      SttEngine.whisper =>
                        '75 MB–466 MB • CPU • English or multilingual',
                      SttEngine.gemma =>
                        'GPU • 16 GB system memory recommended',
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
                                      ts.sharedGemmaModelForGrammar);
                                  if (!ts.isLoaded) {
                                    throw StateError(ts.statusMessage.isEmpty
                                        ? 'Model could not load. Check connection and access token.'
                                        : ts.statusMessage);
                                  }
                                  await _loadSystemState();
                                }),
                        child: Text(engine == ts.activeEngine
                            ? 'Selected'
                            : 'Use model')))
              ])),
        if (ts.activeEngine == SttEngine.whisper)
          PreferenceGroup(children: [
            PreferenceRow(
                icon: Icons.data_usage,
                title: 'Whisper size',
                trailing: _select(s.whisperModelIndex, {
                  0: 'Tiny English • 75 MB',
                  3: 'Tiny multilingual • 75 MB',
                  1: 'Base • 142 MB',
                  2: 'Small • 466 MB'
                }, (v) async {
                  await s.setWhisperModelIndex(v);
                  await ts.reloadModelIfNeeded();
                  if (!ts.isLoaded) {
                    throw StateError('Could not load selected Whisper model.');
                  }
                }, disabled: locked))
          ]),
        _heading('GGUF speech catalog'),
        PreferenceGroup(children: [
          PreferenceRow(
              icon: Icons.library_music_outlined,
              title: 'Catalog or imported model',
              trailing: _select(s.ggufModel, {
                for (final model in ggufCatalog)
                  model.id:
                      '${model.name} • ${(model.bytes / 1048576).round()} MB',
                for (final model in _customModels) model.id: model.name
              }, (value) async {
                await ts.unloadModel();
                await s.setGgufModel(value);
                await ts.switchEngine(SttEngine.gguf);
                if (!ts.isLoaded) throw StateError(ts.statusMessage);
                await _loadSystemState();
              }, disabled: locked))
        ]),
        _note(
            'Catalog downloads are pinned and checksum-verified. Only the selected model downloads. This CPU runtime releases model memory after each clip.'),
        TextButton.icon(
            onPressed: locked
                ? null
                : () => _run(() async {
                      final path = await channel
                          .invokeMethod<String>('chooseSpeechModel');
                      if (path == null) return;
                      final model = await CustomModelStore().importFile(path);
                      _customModels = await CustomModelStore().read();
                      await ts.unloadModel();
                      await s.setGgufModel(model.id);
                    }),
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Import GGUF speech model')),
        _heading('Keyboard input switching'),
        _note(
            'Select a speech model for an enabled keyboard input source. The mapping is applied when dictation starts.'),
        PreferenceGroup(children: [
          for (final source in _keyboardSources)
            PreferenceRow(
                icon: Icons.language,
                title: source['name'] ?? source['id']!,
                trailing: _select(
                    s.keyboardModels[source['id']] ?? '',
                    {
                      '': 'Keep current model',
                      'whisper': 'Whisper',
                      'moonshine': 'Moonshine Tiny',
                      'gemma': 'Gemma',
                      'nemotron': 'Nemotron',
                      for (final model in ggufCatalog)
                        'gguf:${model.id}': model.name,
                      for (final model in _customModels)
                        'gguf:${model.id}': model.name,
                    },
                    (value) => s.setKeyboardModel(source['id']!, value),
                    disabled: locked))
        ]),
        _heading('Your model benchmarks'),
        _note(
            'Use the same short PCM WAV file to compare models on this Mac. No reference transcript means no accuracy score. Process memory excludes the separate GGUF runtime.'),
        TextButton.icon(
            onPressed: locked
                ? null
                : () => _run(() async {
                      final path = await channel
                          .invokeMethod<String>('chooseBenchmarkAudio');
                      if (path == null) return;
                      if (!widget.orchestrator.isAvailable) {
                        throw StateError(
                            'Finish the current audio task first.');
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
            label: const Text('Benchmark selected model')),
        for (final result in _benchmarks)
          PreferenceGroup(children: [
            PreferenceRow(
                icon: Icons.timer_outlined,
                title: '${result['model']} • ${result['decodeMs']} ms',
                subtitle:
                    'Load ${result['loadMs']} ms • ${result['sampleBytes']} bytes • ${result['time']}')
          ]),
        _heading('Memory'),
        PreferenceGroup(children: [
          PreferenceRow(
              icon: Icons.memory_outlined,
              title: 'Unload models',
              subtitle:
                  'Release speech and cleanup models. The files stay available for next time.',
              trailing: TextButton(
                  onPressed: locked
                      ? null
                      : () => _run(() async {
                            await widget.grammarService.unloadModel();
                            await ts.unloadModel();
                          }),
                  child: const Text('Unload')))
        ]),
        _note(
            'Moonshine Streaming Tiny Q8 is also available in the GGUF catalog at about 50 MB. The original Moonshine Tiny INT8 backend remains available. Benchmark your microphone and accent before choosing.'),
      ];

  List<Widget> _output() => [
        _note(
            'Choose when text appears and how much processing happens before insertion.'),
        PreferenceGroup(children: [
          PreferenceRow(
              icon: Icons.notes_outlined,
              title: 'Dictation mode',
              trailing: _select(s.dictationMode, {
                DictationMode.liveTyping: 'Live typing',
                DictationMode.enhancedAccuracy: 'Finish, then insert'
              }, (v) async {
                await s.setDictationMode(v);
              }, disabled: locked)),
          _switch(
              Icons.auto_fix_high_outlined,
              'Grammar cleanup',
              'Used in Finish, then insert mode. Downloads a separate Gemma 270M model only when needed.',
              s.grammarEnabled, (v) async {
            await s.setGrammarEnabled(v);
            if (!v) await widget.grammarService.unloadModel();
          }),
          PreferenceRow(
              icon: Icons.language,
              title: 'Language',
              subtitle:
                  'Applies to multilingual Whisper. English-only models always use English.',
              trailing: _select(s.language, {
                'en': 'English',
                'hi': 'Hindi',
                'es': 'Spanish',
                'fr': 'French',
                'de': 'German',
                'ja': 'Japanese',
                'auto': 'Detect automatically'
              }, (v) async {
                await s.setLanguage(v);
              }, disabled: locked)),
          _switch(
              Icons.content_paste_outlined,
              'Clipboard fallback notice',
              'Notify when direct Accessibility insertion uses clipboard paste.',
              s.fallbackNotify,
              s.setFallbackNotify),
          const PreferenceRow(
              icon: Icons.keyboard_outlined,
              title: 'Paste last dictation',
              subtitle: 'Insert the last transcript into the focused app.',
              trailing: Text('⌘ ⌥ ⇧ V', style: TextStyle(fontSize: 12))),
        ]),
        _heading('Paste behavior'),
        PreferenceGroup(children: [
          _switch(
              Icons.terminal,
              'Terminal paste shortcut',
              'Use Control + Shift + V in recognized terminal apps. Otherwise use Command + V.',
              s.terminalPaste,
              s.setTerminalPaste),
          _switch(
              Icons.content_paste_go_outlined,
              'Restore clipboard after paste',
              'Restore only if no other app has changed the clipboard.',
              s.restoreClipboard,
              s.setRestoreClipboard),
        ]),
        _heading('Per-application processing'),
        _note(
            'Steps run in order after recognition. A pipeline buffers the dictation until you finish so processed text is pasted once. The target app is captured when dictation starts.'),
        for (final profile in _profiles)
          PreferenceGroup(children: [
            PreferenceRow(
                icon: Icons.account_tree_outlined,
                title: profile.application == '*'
                    ? 'Default • every app'
                    : profile.application,
                subtitle:
                    profile.steps.map((step) => step.kind.name).join(' → '),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      tooltip: 'Edit pipeline',
                      onPressed: locked ? null : () => _editPipeline(profile),
                      icon: const Icon(Icons.edit_outlined)),
                  IconButton(
                      tooltip: 'Delete pipeline',
                      onPressed: locked
                          ? null
                          : () => _run(() async {
                                final next = [..._profiles]..remove(profile);
                                await PipelineStore().save(next);
                                _profiles = next;
                              }),
                      icon: const Icon(Icons.delete_outline)),
                ]))
          ]),
        TextButton.icon(
            onPressed: locked ? null : () => _editPipeline(),
            icon: const Icon(Icons.add),
            label: const Text('Add application pipeline')),
        TextButton(
            onPressed: () => _run(() async {
                  final file = await PipelineStore().file;
                  if (!await file.exists()) await PipelineStore().save([]);
                  await Process.run('open', ['-R', file.path]);
                }),
            child: const Text('Show pipeline file for editing')),
        _heading('Recording limits'),
        PreferenceGroup(children: [
          _switch(
              Icons.pause_circle_outline,
              'Stop after silence',
              'Finish a toggle recording after a quiet pause. Hold mode finishes on key release.',
              s.autoStop,
              s.setAutoStop),
          PreferenceRow(
              icon: Icons.timer_outlined,
              title: 'Silence duration',
              subtitle: '${s.vadSilenceDuration} ms',
              trailing: Slider(
                  value: s.vadSilenceDuration.toDouble().clamp(500, 3000),
                  min: 500,
                  max: 3000,
                  divisions: 25,
                  onChanged: (v) =>
                      _change(s.setVadSilenceDuration(v.round())))),
          PreferenceRow(
              icon: Icons.multitrack_audio,
              title: 'Silence threshold',
              subtitle: '${s.vadThreshold.round()} dBFS',
              trailing: Slider(
                  value: s.vadThreshold.clamp(-60, -10),
                  min: -60,
                  max: -10,
                  divisions: 50,
                  onChanged: (v) => _change(s.setVadThreshold(v)))),
          PreferenceRow(
              icon: Icons.timelapse,
              title: 'Maximum recording',
              subtitle:
                  '${s.maxRecordingSeconds} seconds • shorter clips use less memory',
              trailing: Slider(
                  value: s.maxRecordingSeconds.toDouble().clamp(15, 90),
                  min: 15,
                  max: 90,
                  divisions: 15,
                  onChanged: (v) =>
                      _change(s.setMaxRecordingSeconds(v.round())))),
        ]),
      ];

  Future<void> _editPipeline([OutputProfile? profile]) async {
    final result = await showDialog<OutputProfile>(
        context: context, builder: (_) => PipelineEditor(profile: profile));
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
        _heading('Decoder vocabulary'),
        _note(
            'One name or technical term per line. Used by Parakeet GGUF vocabulary biasing and Whisper GGUF context prompts; other backends do not claim decoder biasing.'),
        TextField(
            controller: _decoderWords,
            minLines: 3,
            maxLines: 7,
            decoration:
                const InputDecoration(labelText: 'Recognition vocabulary')),
        Align(
            alignment: Alignment.centerRight,
            child: TextButton(
                onPressed: () =>
                    _run(() => s.setDecoderVocabulary(_decoderWords.text)),
                child: const Text('Save recognition vocabulary'))),
        _note(
            'Correct recurring names and terms without loading another model. Replacements apply in Finish, then insert mode.'),
        PreferenceGroup(children: [
          const PreferenceRow(
              icon: Icons.spellcheck,
              title: 'Vocabulary replacements',
              subtitle:
                  'One replacement per line: what was heard = what should be inserted. Matches whole words, ignoring case.'),
          Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: TextField(
                  controller: _vocabulary,
                  minLines: 8,
                  maxLines: 14,
                  decoration: const InputDecoration(
                      labelText: 'Replacements',
                      hintText: 'aura scribe = AuraScribe'))),
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
                                      const SnackBar(
                                          content: Text('Vocabulary saved')));
                                }
                              }),
                      child: const Text('Save vocabulary')))),
        ]),
        _note(
            'This is text replacement after recognition. It does not bias the speech decoder or change words already inserted during live typing.'),
      ];

  List<Widget> _history() {
    final entries = HistoryService.instance.entries
        .where((e) => e.text.toLowerCase().contains(_search.text.toLowerCase()))
        .toList();
    return [
      PreferenceGroup(children: [
        _switch(
            Icons.history,
            'Save dictation history',
            'Opt in to keep the latest 100 transcripts in this project. Audio is never saved in history.',
            s.historyEnabled,
            s.setHistoryEnabled)
      ]),
      const SizedBox(height: 18),
      TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              labelText: 'Search transcripts', prefixIcon: Icon(Icons.search))),
      const SizedBox(height: 18),
      if (entries.isEmpty)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(children: [
              Icon(Icons.history,
                  size: 36,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                  _search.text.isEmpty
                      ? 'Your dictations will appear here'
                      : 'No matching transcripts',
                  style: const TextStyle(fontSize: 16)),
              _note(
                  'Enable history, then use your dictation shortcut to speak into another app.'),
            ])),
      for (final entry in entries)
        Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PreferenceGroup(children: [
              PreferenceRow(
                  icon: Icons.notes,
                  title:
                      '${entry.date.toLocal().toString().substring(0, 16)} • ${entry.model}',
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        tooltip: 'Copy transcript',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: entry.text))),
                    IconButton(
                        tooltip: 'Delete transcript',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () =>
                            _run(() => HistoryService.instance.remove(entry))),
                  ])),
              Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(entry.text,
                          style: const TextStyle(fontSize: 13, height: 1.6)))),
            ])),
      if (HistoryService.instance.entries.isNotEmpty)
        Align(
            alignment: Alignment.centerRight,
            child: TextButton(
                onPressed: () => _run(() => HistoryService.instance.clear()),
                child: const Text('Clear history'))),
    ];
  }

  List<Widget> _privacy() => [
        _note(
            'Recognition happens on your Mac. Network access is used to download the models you choose.'),
        PreferenceGroup(children: [
          PreferenceRow(
              icon: Icons.folder_outlined,
              title: 'Project model storage',
              subtitle: '${(_bytes / 1048576).toStringAsFixed(1)} MB on disk',
              trailing: TextButton(
                  onPressed: () => _run(() async {
                        await Process.run(
                            'open', [ProjectStorage.instance.models.path]);
                      }),
                  child: const Text('Show in Finder'))),
          Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: SelectableText(ProjectStorage.instance.models.path,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant))),
          PreferenceRow(
              icon: Icons.delete_outline,
              title: 'Remove downloaded models & caches',
              subtitle:
                  'Unloads models first. The next dictation will download the selected model again.',
              trailing: TextButton(
                  onPressed: locked
                      ? null
                      : () => _run(() async {
                            await widget.grammarService.unloadModel();
                            await ts.unloadModel();
                            for (final name in ['models', 'runtime', 'cache']) {
                              final dir =
                                  await ProjectStorage.instance.directory(name);
                              await dir.delete(recursive: true);
                            }
                            await ProjectStorage.instance.directory('models');
                            await _loadSystemState();
                          }),
                  child: const Text('Remove'))),
        ]),
        _note(
            'No fallback to ~/Library or a global model cache. If this project moves, rebuild the app from the new location. Existing downloads from older versions are left untouched.'),
        _heading('Hugging Face access'),
        PreferenceGroup(children: [
          const PreferenceRow(
              icon: Icons.key_outlined,
              title: 'Access token',
              subtitle:
                  'Only needed for gated models. Stored in macOS Keychain; sent only to Hugging Face model downloads.'),
          Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: TextField(
                  controller: _token,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration:
                      const InputDecoration(labelText: 'Hugging Face token'))),
          Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                      onPressed: () => _run(() async {
                            await s.setHfToken(_token.text);
                          }),
                      child: const Text('Save token')))),
        ]),
      ];

  Future<void> _editCommand([PersonalCommand? command]) async {
    final name = TextEditingController(text: command?.name ?? '');
    final instruction = TextEditingController(text: command?.instruction ?? '');
    final result = await showDialog<PersonalCommand>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Personal command'),
                content: SizedBox(
                    width: 480,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: name,
                          decoration: const InputDecoration(labelText: 'Name')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: instruction,
                          minLines: 4,
                          maxLines: 8,
                          decoration: const InputDecoration(
                              labelText:
                                  'What should happen to the selected text?')),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () {
                        if (name.text.trim().isEmpty ||
                            instruction.text.trim().isEmpty) {
                          return;
                        }
                        Navigator.pop(
                            context,
                            PersonalCommand(
                                command?.id ??
                                    DateTime.now()
                                        .microsecondsSinceEpoch
                                        .toString(),
                                name.text.trim(),
                                instruction.text.trim()));
                      },
                      child: const Text('Save command'))
                ]));
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
          'Installed version ${updates.currentVersion}. Updates come from this project’s GitHub Releases. Installing requires a newer, notarized app signed by the same Developer ID team.'),
      PreferenceGroup(children: [
        _switch(
            Icons.update,
            'Check for updates automatically',
            'Check for a stable release every 12 hours.',
            s.automaticUpdates, (v) async {
          await s.setAutomaticUpdates(v);
          await updates.configure();
        }),
        _switch(
            Icons.download_outlined,
            'Download updates automatically',
            'Download only when GitHub publishes a SHA-256 asset digest.',
            s.downloadUpdates, (v) async {
          await s.setDownloadUpdates(v);
          await updates.configure();
        }),
        _switch(
            Icons.install_desktop,
            'Install updates when idle',
            'Applies to signed builds in a writable app directory. An earlier app copy is kept for recovery.',
            s.installUpdates, (v) async {
          await s.setInstallUpdates(v);
          await updates.configure();
        }),
      ]),
      _note(updates.status),
      if (updates.error.isNotEmpty)
        Text(updates.error,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (updates.busy) const LinearProgressIndicator(),
      Wrap(spacing: 12, children: [
        TextButton(
            onPressed: updates.busy ? null : () => _run(updates.check),
            child: const Text('Check now')),
        if (updates.release != null)
          TextButton(
              onPressed: updates.busy ? null : () => _run(updates.download),
              child: const Text('Download verified update')),
        if (updates.downloaded != null)
          TextButton(
              onPressed:
                  updates.busy || locked ? null : () => _run(updates.install),
              child: const Text('Install & restart')),
      ]),
      if (updates.release != null) SelectableText(updates.release!.notes),
    ];
  }

  List<Widget> _labs() => [
        _note(
            'Optional local tools. Smart Commands load the cleanup model only when you use them.'),
        const PreferenceGroup(children: [
          PreferenceRow(
              icon: Icons.auto_awesome_outlined,
              title: 'Smart Commands',
              subtitle:
                  'Select text in any app, then press ⌃ ⇧ C. Rewrite professionally, summarize, translate to Hindi, or enter your own instruction.'),
          PreferenceRow(
              icon: Icons.keyboard_outlined,
              title: 'Keyboard navigation',
              subtitle:
                  'Use arrow keys to choose a command, Return to run it, and Escape to close.')
        ]),
        _heading('Personal commands'),
        for (final command in _commands)
          PreferenceGroup(children: [
            PreferenceRow(
                icon: Icons.bookmark_outline,
                title: command.name,
                subtitle: command.instruction,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      tooltip: 'Edit command',
                      onPressed: () => _editCommand(command),
                      icon: const Icon(Icons.edit_outlined)),
                  IconButton(
                      tooltip: 'Delete command',
                      onPressed: () => _run(() async {
                            final next = [..._commands]..remove(command);
                            await PersonalCommandStore().save(next);
                            _commands = next;
                          }),
                      icon: const Icon(Icons.delete_outline)),
                ]))
          ]),
        TextButton.icon(
            onPressed: () => _editCommand(),
            icon: const Icon(Icons.add),
            label: const Text('Add personal command')),
        TextButton(
            onPressed: () => _run(() async {
                  final file = await PersonalCommandStore().file;
                  if (!await file.exists()) {
                    await PersonalCommandStore().save([]);
                  }
                  await Process.run('open', ['-R', file.path]);
                }),
            child: const Text('Show command file for editing')),
        _heading('Model research'),
        const PreferenceGroup(children: [
          PreferenceRow(
              icon: Icons.science_outlined,
              title: 'Moonshine Tiny INT8',
              subtitle:
                  'Available under Speech models. An English CPU option with a small download. Compare accuracy with Whisper on your own microphone.'),
          PreferenceRow(
              icon: Icons.biotech_outlined,
              title: 'Newer candidates',
              subtitle:
                  'The full GGUF catalog includes Parakeet variants, Qwen, SenseVoice, Cohere and Moonshine Streaming Tiny. All selected-model downloads remain inside this project.')
        ]),
      ];
}
