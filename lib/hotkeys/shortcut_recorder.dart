import '../l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'shortcut_binding.dart';

class ShortcutRecorder extends StatefulWidget {
  final ShortcutAction action;
  final bool sided;
  const ShortcutRecorder({super.key, required this.action, this.sided = false});
  @override
  State<ShortcutRecorder> createState() => _ShortcutRecorderState();
}

class _ShortcutRecorderState extends State<ShortcutRecorder> {
  final _focus = FocusNode();
  String? _error;
  ShortcutBinding? _modifier;
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyboardListener(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (event) {
        final modifierOnly = widget.action == ShortcutAction.dictation;
        if (event is KeyUpEvent) {
          final candidate = _modifier;
          if (candidate == null ||
              candidate.usage != event.physicalKey.usbHidUsage) {
            return;
          }
          _modifier = null;
          candidate.validate(allowModifierOnly: modifierOnly);
          Navigator.pop(context, candidate);
          return;
        }
        if (event is! KeyDownEvent) return;
        if (event.logicalKey == LogicalKeyboardKey.escape &&
            widget.action != ShortcutAction.cancel) {
          Navigator.pop(context);
          return;
        }
        final standalone = ShortcutBinding.chord(event.physicalKey, {});
        if (standalone.isModifierOnly) {
          setState(() {
            _error = null;
            _modifier = modifierOnly
                ? ShortcutBinding.fromEvent(event, sided: widget.sided)
                : null;
          });
          return;
        }
        _modifier = null;
        try {
          final binding = ShortcutBinding.fromEvent(event, sided: widget.sided);
          binding.validate(allowModifierOnly: modifierOnly);
          Navigator.pop(context, binding);
        } catch (e) {
          setState(() =>
              _error = e.toString().replaceFirst('Invalid argument(s): ', ''));
        }
      },
      child: AlertDialog(
          title: Text(tr(widget.action.label)),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.action == ShortcutAction.dictation
                    ? tr(
                        "Press and release Option, Control, Command, Shift or Fn to use it alone. Or hold a modifier and press another key.")
                    : tr(
                        "Hold Option, Command or Control, then press another key.")),
                if (_modifier != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(tr("Release {v0} to select it.",
                          values: {"v0": _modifier!.label}))),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)))
              ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr("Cancel")))
          ]));
}
