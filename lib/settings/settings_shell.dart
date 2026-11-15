import '../l10n/app_localizations.dart';
import 'settings_features.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/widget_previews.dart';

import '../shared/app_theme.dart';

const settingsPages = [
  'General',
  'Models',
  'Dictation',
  'Vocabulary',
  'History',
  'Storage',
  'Features',
  'Meetings',
  'Voice filter',
  'Capture',
  'Updates',
  'Developer',
  'Commands',
  'API',
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
  Icons.developer_mode,
  Icons.auto_awesome_outlined,
  Icons.api_outlined,
];
const _pageHints = [
  'Make dictation feel natural.',
  'Choose your speech engine.',
  'Control your words and output.',
  'Names and replacements.',
  'Recent dictation.',
  'Files and model access.',
  'Show only the tools you use.',
  'Record and transcribe calls.',
  'Clean up microphone audio.',
  'Screenshots and annotations.',
  'Keep AuraScribe up to date.',
  'Stories and diagnostics.',
  'Rewrite selected text.',
  'Connect local tools.',
];

class SettingsShell extends StatelessWidget {
  final int selected;
  final String query;
  final ValueChanged<String>? onSearch;
  final ValueChanged<int> onSelected;
  final Widget content;
  final String status;
  final VoidCallback? onDrag;
  final List<int> visiblePages;
  final TextEditingController? searchController;
  const SettingsShell({
    super.key,
    required this.selected,
    this.query = '',
    this.onSearch,
    required this.onSelected,
    required this.content,
    required this.status,
    this.onDrag,
    this.searchController,
    this.visiblePages = coreSettingsPages,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 800;
        Widget nav(int page) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Semantics(
            selected: selected == page,
            button: true,
            child: Material(
              color: selected == page
                  ? colors.primary.withValues(alpha: .11)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              child: InkWell(
                borderRadius: BorderRadius.circular(7),
                key: ValueKey('settings-nav-$page'),
                onTap: () => onSelected(page),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        settingsIcons[page],
                        size: 17,
                        color: selected == page
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          context.tr(settingsPages[page]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selected == page
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: selected == page
                                ? colors.primary
                                : colors.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        Widget group(String label, Iterable<int> pages) {
          final items = pages.where(visiblePages.contains).toList();
          if (items.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 7),
                child: Text(
                  tr(label),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                    letterSpacing: .5,
                  ),
                ),
              ),
              for (final page in items) nav(page),
            ],
          );
        }

        return Row(
          children: [
            Container(
              width: compact ? 164 : 186,
              decoration: BoxDecoration(
                color: colors.brightness == Brightness.dark
                    ? const Color(0xFF121417)
                    : const Color(0xFFF0F2F5),
                border: Border(
                  right: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => onDrag?.call(),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 46, 12, 16),
                      child: Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.graphic_eq_rounded,
                              size: 17,
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(width: 9),
                          const Expanded(
                            child: Text(
                              'AuraScribe',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        group('Workspace', [0, 1, 2]),
                        group('Tools', [3, 4, 7, 8, 9, 12, 13, 11]),
                        group('Customize', [6]),
                        group('System', [5, 10]),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Tooltip(
                      message: status,
                      child: Row(
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: colors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              tr('On-device'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Text(
                            '1.0',
                            style: TextStyle(
                              fontSize: 10,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 20 : 28,
                      38,
                      compact ? 20 : 28,
                      20,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (_) => onDrag?.call(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.tr(settingsPages[selected]),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  tr(_pageHints[selected]),
                                  style: Theme.of(context).textTheme.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (onSearch != null) ...[
                          const SizedBox(width: 12),
                          SizedBox(
                            width: compact ? 148 : 190,
                            child: TextField(
                              key: const ValueKey('settings-search'),
                              controller: searchController,
                              onChanged: onSearch,
                              style: const TextStyle(fontSize: 12),
                              decoration: InputDecoration(
                                hintText: tr('Find settings'),
                                prefixIcon: const Icon(Icons.search, size: 16),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      key: PageStorageKey(selected),
                      padding: EdgeInsets.fromLTRB(
                        compact ? 20 : 28,
                        0,
                        compact ? 20 : 28,
                        28,
                      ),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: content,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class PreferenceGroup extends StatelessWidget {
  final List<Widget> children;
  const PreferenceGroup({super.key, required this.children});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Material(
      color: Theme.of(context).colorScheme.brightness == Brightness.dark
          ? const Color(0xFF1D2025)
          : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Divider(
                  height: 1,
                  color: Theme.of(context).dividerColor.withValues(alpha: .7),
                ),
              ),
            children[i],
          ],
        ],
      ),
    ),
  );
}

class PreferenceRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const PreferenceRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    child: LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Tooltip(
                    message: subtitle!,
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * .44),
              child: trailing!,
            ),
          ],
        ],
      ),
    ),
  );
}

@Preview(name: 'Settings • compact', size: Size(960, 720))
Widget settingsShellPreview() => MaterialApp(
  theme: auraTheme(Brightness.dark),
  home: Scaffold(
    body: SettingsShell(
      selected: 0,
      onSelected: (_) {},
      status: 'On-device',
      content: PreferenceGroup(
        children: [
          PreferenceRow(
            icon: Icons.keyboard_outlined,
            title: tr('Dictation shortcut'),
            trailing: const Text('⌥'),
          ),
          PreferenceRow(
            icon: Icons.mic_none,
            title: tr('Microphone'),
            trailing: Text(tr('System default')),
          ),
        ],
      ),
    ),
  ),
);
