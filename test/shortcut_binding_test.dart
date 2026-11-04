import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:voice_to_text/hotkeys/hotkey_service.dart';
import 'package:voice_to_text/hotkeys/shortcut_binding.dart';

void main() {
  test('rejects unmodified letters and conflicting active shortcuts', () {
    expect(() => ShortcutBinding.chord(PhysicalKeyboardKey.keyA, {}).validate(),
        throwsArgumentError);
    final bindings = ShortcutBinding.defaults;
    bindings[ShortcutAction.dictation] = ShortcutBinding.legacyDictation;
    bindings[ShortcutAction.rawDictation] = bindings[ShortcutAction.dictation]!;
    expect(() => HotkeyService.validateBindings(bindings, chordDictation: true),
        throwsArgumentError);
    expect(
        () => HotkeyService.validateBindings(bindings, chordDictation: false),
        returnsNormally);
  });
  test('serializes custom chords independent of modifier ordering', () {
    final first = ShortcutBinding.chord(
        PhysicalKeyboardKey.keyK, {HotKeyModifier.meta, HotKeyModifier.alt});
    final second = ShortcutBinding.chord(
        PhysicalKeyboardKey.keyK, {HotKeyModifier.alt, HotKeyModifier.meta});
    expect(first.signature, second.signature);
    expect(first.label, '⌥ ⌘ K');
    expect(
        ShortcutBinding.defaults[ShortcutAction.dictation]!.label, 'Option ⌥');
    expect(ShortcutBinding.fromJson(first.toJson()).signature, first.signature);
  });
}
