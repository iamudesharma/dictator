import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/dictation_orchestrator.dart';
import '../grammar/smart_command_service.dart';
import '../output/personal_commands.dart';

class SmartCommandHUD extends StatefulWidget {
  final DictationOrchestrator orchestrator;
  const SmartCommandHUD({super.key, required this.orchestrator});
  @override
  State<SmartCommandHUD> createState() => _SmartCommandHUDState();
}

class _SmartCommandHUDState extends State<SmartCommandHUD> {
  int _selected = 0;
  List<PersonalCommand> _personal = [];
  String? _personalError;
  int get _count => _commands.length + _personal.length;
  bool _custom = false;
  final _instruction = TextEditingController();
  final _keyboard = FocusNode();
  final _input = FocusNode();
  static const _commands = [
    SmartCommandType.rewriteProfessionally,
    SmartCommandType.translateToHindi,
    SmartCommandType.summarize,
    SmartCommandType.custom
  ];
  static const _icons = [
    Icons.work_outline,
    Icons.translate,
    Icons.short_text,
    Icons.edit_note
  ];

  @override
  void initState() {
    super.initState();
    PersonalCommandStore().read().then((values) {
      if (mounted) setState(() => _personal = values);
    }).catchError((Object error) {
      if (mounted) setState(() => _personalError = error.toString());
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _keyboard.requestFocus());
  }

  @override
  void dispose() {
    _instruction.dispose();
    _keyboard.dispose();
    _input.dispose();
    super.dispose();
  }

  void _choose() {
    if (_selected >= _commands.length) {
      widget.orchestrator.executeSmartCommand(SmartCommandType.custom,
          customPrompt: _personal[_selected - _commands.length].instruction);
      return;
    }
    if (_commands[_selected] == SmartCommandType.custom) {
      setState(() => _custom = true);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _input.requestFocus());
    } else {
      widget.orchestrator.executeSmartCommand(_commands[_selected]);
    }
  }

  void _executeCustom() {
    if (_instruction.text.trim().isNotEmpty) {
      widget.orchestrator.executeSmartCommand(SmartCommandType.custom,
          customPrompt: _instruction.text.trim());
    }
  }

  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || widget.orchestrator.smartCommandRunning) {
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_custom) {
        setState(() => _custom = false);
        _keyboard.requestFocus();
      } else {
        widget.orchestrator.closeSmartCommandHUD();
      }
    } else if (!_custom) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() => _selected = (_selected + 1) % _count);
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() => _selected = (_selected - 1 + _count) % _count);
      }
      if (event.logicalKey == LogicalKeyboardKey.enter) _choose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final running = widget.orchestrator.smartCommandRunning;
    final error = widget.orchestrator.smartCommandError ?? _personalError;
    return KeyboardListener(
        focusNode: _keyboard,
        onKeyEvent: _onKey,
        child: Material(
            color: colors.surface,
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        if (_custom)
                          IconButton(
                              tooltip: 'Back to commands',
                              onPressed: running
                                  ? null
                                  : () {
                                      setState(() => _custom = false);
                                      _keyboard.requestFocus();
                                    },
                              icon: const Icon(Icons.arrow_back, size: 18))
                        else
                          Icon(Icons.auto_awesome_outlined,
                              size: 18, color: colors.onSurfaceVariant),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(
                                _custom
                                    ? 'Custom instruction'
                                    : 'Smart Commands',
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600))),
                        IconButton(
                            tooltip: 'Close commands',
                            onPressed: running
                                ? null
                                : widget.orchestrator.closeSmartCommandHUD,
                            icon: const Icon(Icons.close, size: 18)),
                      ]),
                      const SizedBox(height: 8),
                      if (running)
                        const Expanded(
                            child: Center(
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                              CircularProgressIndicator(strokeWidth: 2),
                              SizedBox(height: 18),
                              Text('Processing selected text…')
                            ]))),
                      if (!running && error != null)
                        Expanded(
                            child: SingleChildScrollView(
                                child: Column(children: [
                          Icon(Icons.error_outline, color: colors.error),
                          const SizedBox(height: 12),
                          Text(error,
                              style: TextStyle(
                                  color: colors.error,
                                  fontSize: 13,
                                  height: 1.5)),
                          const SizedBox(height: 16),
                          const Text('Press Escape to close.'),
                        ]))),
                      if (!running && error == null && _custom) ...[
                        Expanded(
                            child: TextField(
                                controller: _instruction,
                                focusNode: _input,
                                expands: true,
                                minLines: null,
                                maxLines: null,
                                textAlignVertical: TextAlignVertical.top,
                                decoration: const InputDecoration(
                                    labelText: 'Instruction',
                                    hintText:
                                        'Turn this into concise bullet points'))),
                        const SizedBox(height: 12),
                        Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                                onPressed: _executeCustom,
                                child: const Text('Apply instruction'))),
                      ],
                      if (!running && error == null && !_custom) ...[
                        Expanded(
                            child: ListView(children: [
                          for (var i = 0; i < _count; i++)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Material(
                                    color: i == _selected
                                        ? colors.onSurface
                                            .withValues(alpha: 0.08)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    child: ListTile(
                                      dense: true,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      leading: Icon(
                                          i < _icons.length
                                              ? _icons[i]
                                              : Icons.bookmark_outline,
                                          size: 19),
                                      title: Text(
                                          i < _commands.length
                                              ? _commands[i].label
                                              : _personal[i - _commands.length]
                                                  .name,
                                          style: const TextStyle(fontSize: 13)),
                                      trailing: i == _selected
                                          ? const Icon(Icons.keyboard_return,
                                              size: 16)
                                          : null,
                                      onTap: () {
                                        setState(() => _selected = i);
                                        _choose();
                                      },
                                    ))),
                        ])),
                        const SizedBox(height: 8),
                        Text('↑ ↓ to choose    Return to apply    Esc to close',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 11, color: colors.onSurfaceVariant)),
                      ],
                    ]))));
  }
}
