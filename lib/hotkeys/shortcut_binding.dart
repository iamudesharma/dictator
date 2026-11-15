import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

enum ShortcutAction {
  dictation,
  rawDictation,
  pasteLast,
  smartCommands,
  capture,
  cancel,
  extra1,
  extra2,
  extra3,
  extra4,
  secondDictation,
  terminalDictation,
  typedText,
  replay
}

extension ShortcutActionLabel on ShortcutAction {
  bool get isAdditionalDictation =>
      (index >= ShortcutAction.extra1.index &&
          index <= ShortcutAction.extra4.index) ||
      this == ShortcutAction.secondDictation;
  bool get isOptional => index >= ShortcutAction.extra1.index;
  String get label => switch (this) {
        ShortcutAction.dictation => 'Dictation',
        ShortcutAction.rawDictation => 'Dictate without processing',
        ShortcutAction.pasteLast => 'Paste last dictation',
        ShortcutAction.smartCommands => 'Smart Commands',
        ShortcutAction.capture => 'Annotate screen',
        ShortcutAction.cancel => 'Cancel dictation',
        ShortcutAction.extra1 => 'Additional dictation 1',
        ShortcutAction.extra2 => 'Additional dictation 2',
        ShortcutAction.extra3 => 'Additional dictation 3',
        ShortcutAction.extra4 => 'Additional dictation 4',
        ShortcutAction.secondDictation => 'Second dictation shortcut',
        ShortcutAction.terminalDictation => 'Dictate to terminal',
        ShortcutAction.typedText => 'Process focused text',
        ShortcutAction.replay => 'Save screen replay',
      };
}

class ShortcutBinding {
  final int usage;
  final Set<HotKeyModifier> modifiers;
  final Set<int> sides;
  const ShortcutBinding(this.usage, this.modifiers, {this.sides = const {}});
  factory ShortcutBinding.fromJson(Map<String, dynamic> json) =>
      ShortcutBinding(
          json['usage'] as int,
          (json['modifiers'] as List)
              .map((m) => HotKeyModifier.values.byName(m as String))
              .toSet(),
          sides: (json['sides'] as List? ?? []).cast<int>().toSet());
  Map<String, dynamic> toJson() => {
        'usage': usage,
        'modifiers': modifiers.map((m) => m.name).toList()..sort(),
        if (sides.isNotEmpty) 'sides': sides.toList()..sort()
      };
  static ShortcutBinding fromEvent(KeyDownEvent event, {bool sided = false}) =>
      ShortcutBinding(
          event.physicalKey.usbHidUsage,
          HotKeyModifier.values
              .where((m) =>
                  m.isModifierPressed &&
                  m != HotKeyModifier.capsLock &&
                  !m.physicalKeys.contains(event.physicalKey))
              .toSet(),
          sides: sided
              ? HardwareKeyboard.instance.physicalKeysPressed
                  .where((k) =>
                      modifierKeyCodes.containsKey(k.usbHidUsage) &&
                      k != event.physicalKey)
                  .map((k) => k.usbHidUsage)
                  .toSet()
              : {});
  static ShortcutBinding chord(
          PhysicalKeyboardKey key, Set<HotKeyModifier> mods) =>
      ShortcutBinding(key.usbHidUsage, mods);
  PhysicalKeyboardKey get key =>
      PhysicalKeyboardKey.findKeyByCode(usage) ??
      (throw ArgumentError('Unknown shortcut key'));
  static const modifierKeyCodes = <int, int>{
    0x700e0: 59, 0x700e4: 62, // Control
    0x700e1: 56, 0x700e5: 60, // Shift
    0x700e2: 58, 0x700e6: 61, // Option
    0x700e3: 55, 0x700e7: 54, // Command
    0x12: 63, // Fn / Globe
  };
  bool get isModifierOnly => modifierKeyCodes.containsKey(usage);
  int? get modifierKeyCode => isModifierOnly ? modifierKeyCodes[usage] : null;
  static ShortcutBinding get optionChord =>
      chord(PhysicalKeyboardKey.keyT, {HotKeyModifier.alt});
  String get signature =>
      '$usage:${(modifiers.map((m) => m.name).toList()..sort()).join(",")}:${(sides.toList()..sort()).join(",")}';
  // PhysicalKeyboardKey.debugName is stripped from release builds.
  String get keyLabel {
    final modifier = const {
      0x700e0: 'Left Control ⌃',
      0x700e4: 'Right Control ⌃',
      0x700e1: 'Left Shift ⇧',
      0x700e5: 'Right Shift ⇧',
      0x700e2: 'Option ⌥',
      0x700e6: 'Right Option ⌥',
      0x700e3: 'Left Command ⌘',
      0x700e7: 'Right Command ⌘',
      0x12: 'Fn / Globe',
    }[usage];
    if (modifier != null) return modifier;
    final code = usage - 0x70000;
    if (code >= 4 && code <= 29) return String.fromCharCode(65 + code - 4);
    if (code >= 30 && code <= 38) return '${code - 29}';
    if (code == 39) return '0';
    if (code >= 58 && code <= 69) return 'F${code - 57}';
    if (code >= 104 && code <= 115) return 'F${code - 91}';
    if (code >= 89 && code <= 97) return 'Keypad ${code - 88}';
    return const {
          40: 'Return',
          41: 'Esc',
          42: 'Delete',
          43: 'Tab',
          44: 'Space',
          45: '−',
          46: '=',
          47: '[',
          48: ']',
          49: '\\',
          51: ';',
          52: "'",
          53: '`',
          54: ',',
          55: '.',
          56: '/',
          70: 'Print Screen',
          71: 'Scroll Lock',
          72: 'Pause',
          73: 'Insert',
          74: 'Home',
          75: 'Page Up',
          76: 'Forward Delete',
          77: 'End',
          78: 'Page Down',
          79: '→',
          80: '←',
          81: '↓',
          82: '↑',
          84: 'Keypad /',
          85: 'Keypad ×',
          86: 'Keypad −',
          87: 'Keypad +',
          88: 'Keypad Enter',
          98: 'Keypad 0',
          99: 'Keypad .',
        }[code] ??
        'Key 0x${usage.toRadixString(16)}';
  }

  String get label => isModifierOnly && modifiers.isEmpty
      ? keyLabel
      : '${[
          if (modifiers.contains(HotKeyModifier.control)) "⌃",
          if (modifiers.contains(HotKeyModifier.alt)) "⌥",
          if (modifiers.contains(HotKeyModifier.shift)) "⇧",
          if (modifiers.contains(HotKeyModifier.meta)) "⌘"
        ].join(" ")} $keyLabel${sides.isEmpty ? '' : ' (${sides.map((u) => ShortcutBinding(u, {}).keyLabel).join(' + ')})'}';
  void validate({bool allowModifierOnly = false}) {
    final k = key;
    if (allowModifierOnly && isModifierOnly) return;
    if (modifiers.isEmpty &&
        (usage == PhysicalKeyboardKey.escape.usbHidUsage ||
            (usage >= 0x7003a && usage <= 0x70052) ||
            usage == 0x70064 ||
            usage == 0x70065)) {
      return;
    }
    if (isModifierOnly ||
        HotKeyModifier.values.any((m) => m.physicalKeys.contains(k))) {
      throw ArgumentError('Press a key as well as a modifier.');
    }
    if (!modifiers.any({
      HotKeyModifier.meta,
      HotKeyModifier.control,
      HotKeyModifier.alt
    }.contains)) {
      throw ArgumentError('Include Command, Control or Option.');
    }
    if (modifiers.contains(HotKeyModifier.fn) ||
        modifiers.contains(HotKeyModifier.capsLock)) {
      throw ArgumentError('Fn and Caps Lock shortcuts are not supported.');
    }
  }

  HotKey toHotKey(ShortcutAction action) => HotKey(
      identifier: 'aurascribe.${action.name}',
      key: key,
      modifiers: modifiers.toList(),
      scope: HotKeyScope.system);
  static ShortcutBinding get legacyDictation => chord(
      PhysicalKeyboardKey.space, {HotKeyModifier.meta, HotKeyModifier.shift});
  static Map<ShortcutAction, ShortcutBinding> get defaults => {
        ShortcutAction.secondDictation: chord(PhysicalKeyboardKey.digit5,
            {HotKeyModifier.meta, HotKeyModifier.alt, HotKeyModifier.control}),
        ShortcutAction.terminalDictation: chord(PhysicalKeyboardKey.keyT,
            {HotKeyModifier.meta, HotKeyModifier.alt, HotKeyModifier.shift}),
        ShortcutAction.typedText: chord(PhysicalKeyboardKey.keyR,
            {HotKeyModifier.meta, HotKeyModifier.alt, HotKeyModifier.shift}),
        ShortcutAction.replay: chord(PhysicalKeyboardKey.keyS,
            {HotKeyModifier.meta, HotKeyModifier.alt, HotKeyModifier.shift}),
        ShortcutAction.cancel: chord(PhysicalKeyboardKey.escape, {}),
        for (var i = 0; i < 4; i++)
          ShortcutAction.values[ShortcutAction.extra1.index + i]:
              ShortcutBinding(0x7001e + i, {
            HotKeyModifier.meta,
            HotKeyModifier.alt,
            HotKeyModifier.control
          }),
        ShortcutAction.dictation: chord(PhysicalKeyboardKey.altLeft, {}),
        ShortcutAction.rawDictation: chord(PhysicalKeyboardKey.keyD,
            {HotKeyModifier.meta, HotKeyModifier.alt, HotKeyModifier.shift}),
        ShortcutAction.pasteLast: chord(PhysicalKeyboardKey.keyV,
            {HotKeyModifier.meta, HotKeyModifier.alt, HotKeyModifier.shift}),
        ShortcutAction.smartCommands: chord(PhysicalKeyboardKey.keyC,
            {HotKeyModifier.control, HotKeyModifier.shift}),
        ShortcutAction.capture: chord(PhysicalKeyboardKey.keyA,
            {HotKeyModifier.meta, HotKeyModifier.alt, HotKeyModifier.shift}),
      };
}
