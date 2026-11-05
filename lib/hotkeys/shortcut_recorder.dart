import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'shortcut_binding.dart';

class ShortcutRecorder extends StatefulWidget {
  final ShortcutAction action;
  const ShortcutRecorder({super.key, required this.action});
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
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.pop(context);
          return;
        }
        final standalone = ShortcutBinding.chord(event.physicalKey, {});
        if (standalone.isModifierOnly) {
          final count = HardwareKeyboard.instance.physicalKeysPressed
              .where((key) =>
                  ShortcutBinding.modifierKeyCodes.containsKey(key.usbHidUsage))
              .length;
          setState(() {
            _error = null;
            _modifier = modifierOnly && count == 1 ? standalone : null;
          });
          return;
        }
        _modifier = null;
        try {
          final binding = ShortcutBinding.fromEvent(event);
          binding.validate(allowModifierOnly: modifierOnly);
          Navigator.pop(context, binding);
        } catch (e) {
          setState(() =>
              _error = e.toString().replaceFirst('Invalid argument(s): ', ''));
        }
      },
      child: AlertDialog(
          title: Text(widget.action.label),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.action == ShortcutAction.dictation
                    ? 'Press and release Option, Control, Command, Shift or Fn to use it alone. Or hold a modifier and press another key.'
                    : 'Hold Option, Command or Control, then press another key.'),
                if (_modifier != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('Release ${_modifier!.label} to select it.')),
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
                child: const Text('Cancel'))
          ]));
}
