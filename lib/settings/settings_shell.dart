import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import '../shared/app_theme.dart';

const settingsPages = [
  'General',
  'Speech models',
  'Output',
  'Vocabulary',
  'History',
  'Privacy & storage',
  'Labs',
  'Meetings',
  'Voice filter',
  'Capture & annotate',
  'Updates',
  'Playground'
];
const settingsIcons = [
  Icons.tune_rounded,
  Icons.graphic_eq,
  Icons.notes_rounded,
  Icons.spellcheck_rounded,
  Icons.history_rounded,
  Icons.folder_outlined,
  Icons.science_outlined,
  Icons.groups_outlined,
  Icons.noise_aware,
  Icons.draw_outlined,
  Icons.update,
  Icons.developer_mode
];

class SettingsShell extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;
  final Widget content;
  final String status;
  final VoidCallback? onDrag;
  const SettingsShell(
      {super.key,
      required this.selected,
      required this.onSelected,
      required this.content,
      required this.status,
      this.onDrag});
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 760;
      return Row(children: [
        Container(
            width: narrow ? 68 : 204,
            color: colors.brightness == Brightness.dark
                ? const Color(0xFF101012)
                : const Color(0xFFEEEEF1),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) => onDrag?.call(),
                      child: SizedBox(
                          height: 88,
                          child: narrow
                              ? const SizedBox()
                              : Padding(
                                  padding:
                                      const EdgeInsets.only(left: 20, top: 44),
                                  child: Text('AuraScribe',
                                      style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w600,
                                          color: colors.onSurface))))),
                  Expanded(
                      child: ListView(children: [
                    for (var i = 0; i < settingsPages.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 2),
                        child: Tooltip(
                            message: settingsPages[i],
                            child: Material(
                                color: selected == i
                                    ? colors.onSurface.withValues(alpha: 0.09)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(7),
                                child: InkWell(
                                    borderRadius: BorderRadius.circular(7),
                                    onTap: () => onSelected(i),
                                    child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 13),
                                        child: Row(children: [
                                          Icon(settingsIcons[i],
                                              size: 19,
                                              color: selected == i
                                                  ? colors.onSurface
                                                  : colors.onSurfaceVariant),
                                          if (!narrow) ...[
                                            const SizedBox(width: 11),
                                            Expanded(
                                                child: Text(settingsPages[i],
                                                    style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight: selected ==
                                                                i
                                                            ? FontWeight.w600
                                                            : FontWeight.w400)))
                                          ],
                                        ]))))),
                      ),
                  ])),
                  if (!narrow)
                    Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(status,
                                  style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                      fontSize: 12)),
                              const SizedBox(height: 6),
                              Text('AuraScribe 1.0',
                                  style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                      fontSize: 11)),
                            ])),
                ])),
        VerticalDivider(
            width: 1,
            thickness: 1,
            color: colors.outlineVariant.withValues(alpha: 0.5)),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => onDrag?.call(),
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(30, 32, 30, 20),
                      child: Text(settingsPages[selected],
                          style: const TextStyle(
                              fontSize: 21, fontWeight: FontWeight.w600)))),
              Expanded(
                  child: SingleChildScrollView(
                      key: PageStorageKey(selected),
                      padding: const EdgeInsets.fromLTRB(30, 0, 30, 32),
                      child: Align(
                          alignment: Alignment.topLeft,
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 820),
                              child: content)))),
            ])),
      ]);
    });
  }
}

class PreferenceGroup extends StatelessWidget {
  final List<Widget> children;
  const PreferenceGroup({super.key, required this.children});
  @override
  Widget build(BuildContext context) => Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).dividerColor)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: Divider(height: 1)),
          children[i],
        ]
      ]));
}

class PreferenceRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const PreferenceRow(
      {super.key,
      required this.icon,
      required this.title,
      this.subtitle,
      this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        child: LayoutBuilder(
            builder: (context, constraints) => Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(icon,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 14),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(title,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500)),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(subtitle!,
                                style: TextStyle(
                                    fontSize: 12,
                                    height: 1.5,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant))
                          ],
                        ])),
                    if (trailing != null) ...[
                      const SizedBox(width: 16),
                      ConstrainedBox(
                          constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth * 0.44),
                          child: trailing!)
                    ],
                  ],
                )),
      );
}

@Preview(name: 'Settings • desktop dark', size: Size(960, 720))
Widget settingsShellPreview() => MaterialApp(
    theme: auraTheme(Brightness.dark),
    home: Scaffold(
        body: SettingsShell(
            selected: 0,
            onSelected: (_) {},
            status: 'On-device dictation',
            content: PreferenceGroup(children: [
              const PreferenceRow(
                  icon: Icons.keyboard_outlined,
                  title: 'Shortcut',
                  trailing: Text('⌃ ⌃')),
              const PreferenceRow(
                  icon: Icons.graphic_eq,
                  title: 'Speech model',
                  trailing: Text('Whisper tiny.en')),
              const PreferenceRow(
                  icon: Icons.mic_none_rounded,
                  title: 'Microphone',
                  trailing: Text('System default')),
              PreferenceRow(
                  icon: Icons.vertical_align_bottom,
                  title: 'Dictation indicator',
                  subtitle: 'A compact control at the bottom of your screen.',
                  trailing: Switch(value: true, onChanged: (_) {})),
            ]))));
