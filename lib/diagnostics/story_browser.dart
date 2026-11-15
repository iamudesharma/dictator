import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../shared/app_theme.dart';
import 'story_catalog.dart';
import 'story_fixture.dart';

class StoryBrowser extends StatefulWidget {
  final String? initialStory;
  final ValueChanged<String>? onSelected;
  const StoryBrowser({super.key, this.initialStory, this.onSelected});
  @override
  State<StoryBrowser> createState() => _StoryBrowserState();
}

class _StoryBrowserState extends State<StoryBrowser> {
  late AppStory story;
  String query = '', language = 'en';
  bool dark = true, compact = false;
  double textScale = 1;
  int revision = 0, _languageChange = 0;
  @override
  void initState() {
    super.initState();
    story = AppStory.byId(widget.initialStory ?? '') ?? appStories.first;
  }

  @override
  void didUpdateWidget(StoryBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStory != widget.initialStory) {
      final next = AppStory.byId(widget.initialStory ?? '');
      if (next != null) {
        story = next;
        revision++;
      }
    }
  }

  @override
  void dispose() {
    AppLocalizations.instance.releasePreviewLocales();
    super.dispose();
  }

  void select(AppStory value) {
    setState(() {
      story = value;
      revision++;
    });
    widget.onSelected?.call(value.id);
  }

  @override
  Widget build(BuildContext context) {
    final matches = appStories
        .where(
          (s) => '${s.group} ${s.title} ${s.id} ${tr(s.group)} ${tr(s.title)}'
              .toLowerCase()
              .contains(query.toLowerCase()),
        )
        .toList();
    final groups = matches.map((s) => s.group).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(
            "Explore isolated interface states. Preview controls never change your settings or start real audio, downloads, or recordings.",
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          onChanged: (value) => setState(() => query = value),
          decoration: InputDecoration(
            labelText: tr("Find a story"),
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<String>(
              value: language,
              items: [
                for (final entry in interfaceLanguages.entries.where(
                  (e) => e.key != 'system',
                ))
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) async {
                final request = ++_languageChange;
                await AppLocalizations.instance.ensureLocale(value!);
                if (mounted && request == _languageChange) {
                  AppLocalizations.instance.retainPreviewLocale(value);
                  setState(() => language = value);
                }
              },
            ),
            FilterChip(
              label: Text(tr("Dark")),
              selected: dark,
              onSelected: (v) => setState(() => dark = v),
            ),
            FilterChip(
              label: Text(tr("Compact")),
              selected: compact,
              onSelected: (v) => setState(() => compact = v),
            ),
            DropdownButton<double>(
              value: textScale,
              items: [
                for (final scale in [1.0, 1.3, 1.6])
                  DropdownMenuItem(
                    value: scale,
                    child: Text('${(scale * 100).round()}%'),
                  ),
              ],
              onChanged: (value) => setState(() => textScale = value!),
            ),
            TextButton.icon(
              onPressed: () => setState(() => revision++),
              icon: const Icon(Icons.restart_alt),
              label: Text(tr("Reset preview")),
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: story.link.toString()),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(tr('Story link copied'))),
                  );
                }
              },
              icon: const Icon(Icons.link),
              label: Text(tr("Copy story link")),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 580,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 620;
              final navigation = ListView(
                key: const PageStorageKey('story-navigation'),
                children: [
                  for (final group in groups)
                    ExpansionTile(
                      key: PageStorageKey('story-group-$group:$query'),
                      initiallyExpanded: query.isNotEmpty,
                      title: Text(tr(group)),
                      children: [
                        for (final item in matches.where(
                          (s) => s.group == group,
                        ))
                          ListTile(
                            dense: true,
                            selected: story.id == item.id,
                            title: Text(tr(item.title)),
                            onTap: () => select(item),
                          ),
                      ],
                    ),
                  if (matches.isEmpty)
                    ListTile(title: Text(tr("No matching stories"))),
                ],
              );
              final preview = Localizations.override(
                context: context,
                locale: AppLocalizations.localeFor(language),
                child: Theme(
                  data: auraTheme(dark ? Brightness.dark : Brightness.light),
                  child: Builder(
                    builder: (context) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(textScale),
                        disableAnimations: true,
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: compact ? 360 : 720,
                          child: Material(
                            color: Theme.of(context).colorScheme.surface,
                            child: SingleChildScrollView(
                              key: PageStorageKey('story-preview-${story.id}'),
                              padding: const EdgeInsets.all(16),
                              child: StoryFixture(
                                key: ValueKey('${story.id}:$revision'),
                                story: story,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              return narrow
                  ? Column(
                      children: [
                        SizedBox(height: 140, child: navigation),
                        const Divider(),
                        Expanded(child: preview),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 206, child: navigation),
                        const VerticalDivider(width: 24),
                        Expanded(child: preview),
                      ],
                    );
            },
          ),
        ),
      ],
    );
  }
}
