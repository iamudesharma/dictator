import 'package:flutter/material.dart';
import '../settings/settings_service.dart';
import '../hotkeys/hotkey_service.dart';
import '../accessibility/accessibility_service.dart';
import '../shared/stt_engine.dart';
import '../shared/dictation_mode.dart';
import '../grammar/grammar_service.dart';
import '../transcription/transcription_service.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsService settings;
  final HotkeyService hotkeyService;
  final AccessibilityService accessibility;
  final TranscriptionService transcriptionService;
  final GrammarService grammarService;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.hotkeyService,
    required this.accessibility,
    required this.transcriptionService,
    required this.grammarService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _hasAxPermission = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
    widget.transcriptionService.addListener(_onModelStatusChange);
  }

  void _onModelStatusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.transcriptionService.removeListener(_onModelStatusChange);
    super.dispose();
  }

  Future<void> _checkPermission() async {
    final perm = await widget.accessibility.hasPermission();
    if (mounted) setState(() => _hasAxPermission = perm);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final ts = widget.transcriptionService;

    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6E40C9), Color(0xFF9B59F5)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.mic, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  'AuraScribe Settings',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // ── Model Status ──────────────────────────────────
            _sectionHeader('AI Model'),
            const SizedBox(height: 8),
            _card(
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: ts.isLoaded
                          ? const Color(0xFF34C759).withValues(alpha: 0.15)
                          : ts.isLoading
                              ? const Color(0xFF9B59F5).withValues(alpha: 0.15)
                              : Colors.white10,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ts.isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Color(0xFF9B59F5)),
                            ),
                          )
                        : Icon(
                            ts.isLoaded
                                ? Icons.memory_rounded
                                : Icons.memory_outlined,
                            color: ts.isLoaded
                                ? const Color(0xFF34C759)
                                : Colors.white38,
                            size: 22,
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ts.modelLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ts.isLoaded
                              ? '✓ Ready — speech-to-text'
                              : ts.isLoading
                                  ? (ts.statusMessage.isNotEmpty
                                      ? ts.statusMessage
                                      : 'Downloading model (first run)…')
                                  : 'Loads on first launch',
                          style: TextStyle(
                            color: ts.isLoaded
                                ? const Color(0xFF34C759)
                                : Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.sttEngineIndex == 1
                              ? 'Gemma: GPU-accelerated · best on 16 GB RAM'
                              : s.sttEngineIndex == 2
                                  ? 'Nemotron: streaming · ultra-low latency offline ASR'
                                  : 'Whisper: lower RAM · use Release build for speed',
                          style: const TextStyle(color: Colors.white24, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── STT engine ────────────────────────────────────
            _sectionHeader('Speech Engine'),
            const SizedBox(height: 8),
            _card(
              child: StatefulBuilder(
                builder: (ctx, setSt) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Transcription backend'),
                    const SizedBox(height: 8),
                    _radioTile(
                      'Gemma 4 E2B — fast (16 GB RAM recommended)',
                      1,
                      s.sttEngineIndex,
                      (v) async {
                        if (v == null) return;
                        setSt(() {});
                        await ts.switchEngine(SttEngine.gemma);
                        widget.grammarService.attachSttModel(
                          ts.sharedGemmaModelForGrammar,
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                    _radioTile(
                      'Whisper — lighter RAM (8 GB friendly)',
                      0,
                      s.sttEngineIndex,
                      (v) async {
                        if (v == null) return;
                        setSt(() {});
                        await ts.switchEngine(SttEngine.whisper);
                        widget.grammarService.attachSttModel(null);
                        if (mounted) setState(() {});
                      },
                    ),
                    _radioTile(
                      'Nemotron-3.5 — streaming, ultra-low latency',
                      2,
                      s.sttEngineIndex,
                      (v) async {
                        if (v == null) return;
                        setSt(() {});
                        await ts.switchEngine(SttEngine.nemotron);
                        widget.grammarService.attachSttModel(null);
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (s.sttEngineIndex == 0) ...[
              _sectionHeader('Whisper Model Size'),
              const SizedBox(height: 8),
              _card(
                child: StatefulBuilder(
                  builder: (ctx, setSt) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Size (speed vs accuracy)'),
                      const SizedBox(height: 8),
                      _radioTile('tiny.en — fastest (~75 MB)', 0, s.whisperModelIndex,
                          (v) async {
                        if (v == null) return;
                        await s.setWhisperModelIndex(v);
                        await ts.reloadModelIfNeeded();
                        setSt(() {});
                        if (mounted) setState(() {});
                      }),
                      _radioTile('base — balanced (~142 MB)', 1, s.whisperModelIndex,
                          (v) async {
                        if (v == null) return;
                        await s.setWhisperModelIndex(v);
                        await ts.reloadModelIfNeeded();
                        setSt(() {});
                        if (mounted) setState(() {});
                      }),
                      _radioTile('small — slower, more accurate', 2,
                          s.whisperModelIndex, (v) async {
                        if (v == null) return;
                        await s.setWhisperModelIndex(v);
                        await ts.reloadModelIfNeeded();
                        setSt(() {});
                        if (mounted) setState(() {});
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Dictation Mode ────────────────────────────────
            _sectionHeader('Dictation Mode'),
            const SizedBox(height: 8),
            _card(
              child: StatefulBuilder(
                builder: (ctx, setSt) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _dictationModeRadioTile(
                      'Live Typing (recommended)',
                      'Text appears directly in the field.',
                      DictationMode.liveTyping,
                      s.dictationMode,
                      (v) async {
                        if (v == null) return;
                        await s.setDictationMode(v);
                        setSt(() {});
                      },
                    ),
                    _dictationModeRadioTile(
                      'Enhanced Accuracy',
                      'Uses Gemma cleanup before insertion.',
                      DictationMode.enhancedAccuracy,
                      s.dictationMode,
                      (v) async {
                        if (v == null) return;
                        await s.setDictationMode(v);
                        setSt(() {});
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Hotkey ────────────────────────────────────────
            _sectionHeader('Global Hotkey'),
            const SizedBox(height: 8),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Trigger'),
                  const SizedBox(height: 8),
                  StatefulBuilder(
                    builder: (ctx, setSt) => Column(
                      children: [
                        _radioTile('Double Control  (⌃⌃)', 0, s.hotkeyType, (v) async {
                          await s.setHotkeyType(v!);
                          await widget.hotkeyService.updateHotkey();
                          setSt(() {});
                        }),
                        _radioTile('Triple Control  (⌃⌃⌃)', 1, s.hotkeyType, (v) async {
                          await s.setHotkeyType(v!);
                          await widget.hotkeyService.updateHotkey();
                          setSt(() {});
                        }),
                        _radioTile('⌘⇧Space', 2, s.hotkeyType, (v) async {
                          await s.setHotkeyType(v!);
                          await widget.hotkeyService.updateHotkey();
                          setSt(() {});
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── VAD ───────────────────────────────────────────
            _sectionHeader('Voice Activity Detection'),
            const SizedBox(height: 8),
            _card(
              child: StatefulBuilder(
                builder: (ctx, setSt) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Silence Threshold: ${s.vadThreshold.toStringAsFixed(0)} dBFS'),
                    Slider(
                      value: s.vadThreshold,
                      min: -60.0,
                      max: -10.0,
                      divisions: 50,
                      activeColor: const Color(0xFF9B59F5),
                      inactiveColor: Colors.white24,
                      onChanged: (v) async {
                        await s.setVadThreshold(v);
                        setSt(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    _label('Silence Duration: ${s.vadSilenceDuration}ms'),
                    Slider(
                      value: s.vadSilenceDuration.toDouble(),
                      min: 500,
                      max: 3000,
                      divisions: 25,
                      activeColor: const Color(0xFF9B59F5),
                      inactiveColor: Colors.white24,
                      onChanged: (v) async {
                        await s.setVadSilenceDuration(v.round());
                        setSt(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    _label('Max Recording: ${s.maxRecordingSeconds}s'),
                    Slider(
                      value: s.maxRecordingSeconds.toDouble(),
                      min: 15,
                      max: 90,
                      divisions: 15,
                      activeColor: const Color(0xFF9B59F5),
                      inactiveColor: Colors.white24,
                      onChanged: (v) async {
                        await s.setMaxRecordingSeconds(v.round());
                        setSt(() {});
                      },
                    ),
                    const Text(
                      'Shorter clips use less RAM during transcription',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── AI ────────────────────────────────────────────
            _sectionHeader('AI Processing'),
            const SizedBox(height: 8),
            _card(
              child: StatefulBuilder(
                builder: (ctx, setSt) => Column(
                  children: [
                    _switchTile(
                      'Grammar Cleanup',
                      'Gemma 3 270M (Whisper/Nemotron) or shared Gemma STT model',
                      s.grammarEnabled,
                      (v) async {
                        await s.setGrammarEnabled(v);
                        setSt(() {});
                      },
                    ),
                    const Divider(color: Colors.white12),
                    _switchTile(
                      'Notify on Clipboard Fallback',
                      'Show alert when AX insertion fails and clipboard paste is used',
                      s.fallbackNotify,
                      (v) async {
                        await s.setFallbackNotify(v);
                        setSt(() {});
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Hugging Face token ────────────────────────────
            _sectionHeader('Hugging Face'),
            const SizedBox(height: 8),
            _card(
              child: _HfTokenField(
                settings: s,
                onChanged: () {
                  if (mounted) setState(() {});
                },
                transcriptionService: ts,
              ),
            ),
            const SizedBox(height: 16),

            // ── Permissions ───────────────────────────────────
            _sectionHeader('Permissions'),
            const SizedBox(height: 8),
            _card(
              child: Row(
                children: [
                  Icon(
                    _hasAxPermission
                        ? Icons.check_circle_rounded
                        : Icons.warning_amber_rounded,
                    color: _hasAxPermission
                        ? const Color(0xFF34C759)
                        : const Color(0xFFFF9F0A),
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Accessibility Access',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          _hasAxPermission
                              ? 'Granted — text insertion enabled'
                              : 'Not granted — required for text insertion',
                          style: TextStyle(
                            color: _hasAxPermission
                                ? Colors.white38
                                : const Color(0xFFFF9F0A),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_hasAxPermission)
                    TextButton(
                      onPressed: () async {
                        await widget.accessibility.requestPermission();
                        await Future.delayed(const Duration(seconds: 1));
                        await _checkPermission();
                      },
                      child: const Text(
                        'Grant',
                        style: TextStyle(color: Color(0xFF9B59F5)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // ── About ────────────────────────────────────────
            Center(
              child: Text(
                'AuraScribe v1.0  ·  Gemma or Whisper STT  ·  Optional grammar',
                style: const TextStyle(color: Colors.white24, fontSize: 11),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
        ),
      );

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: child,
      );

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      );

  Widget _radioTile(String title, int value, int groupValue, Function(int?) onChanged) =>
      InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Radio<int>(
                value: value,
                groupValue: groupValue,
                onChanged: onChanged,
                activeColor: const Color(0xFF9B59F5),
              ),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white70),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _switchTile(String title, String subtitle, bool value, Function(bool) onChanged) =>
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                Text(subtitle,
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF9B59F5),
          ),
        ],
      );

  Widget _dictationModeRadioTile(
    String title,
    String subtitle,
    DictationMode value,
    DictationMode groupValue,
    Function(DictationMode?) onChanged,
  ) =>
      InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Radio<DictationMode>(
                value: value,
                groupValue: groupValue,
                onChanged: onChanged,
                activeColor: const Color(0xFF9B59F5),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _HfTokenField extends StatefulWidget {
  final SettingsService settings;
  final VoidCallback onChanged;
  final TranscriptionService transcriptionService;

  const _HfTokenField({
    required this.settings,
    required this.onChanged,
    required this.transcriptionService,
  });

  @override
  State<_HfTokenField> createState() => _HfTokenFieldState();
}

class _HfTokenFieldState extends State<_HfTokenField> {
  late final TextEditingController _controller;
  bool _obscured = true;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.settings.hfToken);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.settings.setHfToken(_controller.text);
    widget.onChanged();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('HF token saved'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _testAndDownload() async {
    await _save();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      await widget.transcriptionService.reloadModelIfNeeded();
      setState(() {
        _testResult = widget.transcriptionService.isLoaded
            ? '✓ Download succeeded'
            : '⚠︎ Model status: ${widget.transcriptionService.statusMessage}';
      });
    } catch (e) {
      setState(() => _testResult = '✗ $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Access Token (read-only)',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Required to download the gated Gemma 3 270M model. '
          'Get one at huggingface.co/settings/tokens after accepting the '
          'Gemma license on the model page.',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                obscureText: _obscured,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                cursorColor: const Color(0xFF9B59F5),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'hf_xxxxxxxxxxxxxxxxxxxx',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscured ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white38,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscured = !_obscured),
                  ),
                ),
                onSubmitted: (_) => _save(),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _save,
              child: const Text(
                'Save',
                style: TextStyle(color: Color(0xFF9B59F5)),
              ),
            ),
            TextButton(
              onPressed: _testing ? null : _testAndDownload,
              child: _testing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation(Color(0xFF9B59F5)),
                      ),
                    )
                  : const Text(
                      'Test',
                      style: TextStyle(color: Color(0xFF9B59F5)),
                    ),
            ),
          ],
        ),
        if (_testResult != null) ...[
          const SizedBox(height: 8),
          Text(
            _testResult!,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
