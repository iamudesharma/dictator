import '../l10n/app_localizations.dart';

import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../app/dictation_orchestrator.dart';
import '../output/output_pipeline.dart';
import '../settings/settings_service.dart';
import '../settings/settings_shell.dart';
import '../shared/dictation_indicator.dart';
import '../storage/project_storage.dart';
import '../transcription/transcription_service.dart';
import 'activity_log.dart';
import 'story_browser.dart';

class PlaygroundScreen extends StatefulWidget {
  final DictationOrchestrator orchestrator;
  final TranscriptionService transcription;
  final SettingsService settings;
  const PlaygroundScreen({
    super.key,
    required this.orchestrator,
    required this.transcription,
    required this.settings,
  });
  @override
  State<PlaygroundScreen> createState() => _PlaygroundScreenState();
}

class _PlaygroundScreenState extends State<PlaygroundScreen> {
  final source = TextEditingController(),
      application = TextEditingController(text: '*');
  String output = '', error = '';
  bool _testingInsertion = false;
  bool _stories = true;
  int _storyRequest = 0;
  @override
  void didUpdateWidget(PlaygroundScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_storyRequest != widget.orchestrator.storyRequest) {
      _storyRequest = widget.orchestrator.storyRequest;
      _stories = true;
    }
  }

  @override
  void initState() {
    super.initState();
    source.text = widget.orchestrator.settingsDrafts['playgroundSource'] ?? '';
    application.text =
        widget.orchestrator.settingsDrafts['playgroundApp'] ?? '*';
    ActivityLog.instance.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ActivityLog.instance.removeListener(_refresh);
    widget.orchestrator.settingsDrafts['playgroundSource'] = source.text;
    widget.orchestrator.settingsDrafts['playgroundApp'] = application.text;
    source.dispose();
    application.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SegmentedButton<bool>(
        segments: [
          ButtonSegment(
            value: true,
            label: Text(tr("Story browser")),
            icon: const Icon(Icons.view_quilt_outlined),
          ),
          ButtonSegment(
            value: false,
            label: Text(tr("Diagnostics")),
            icon: const Icon(Icons.monitor_heart_outlined),
          ),
        ],
        selected: {_stories},
        onSelectionChanged: (value) => setState(() => _stories = value.single),
      ),
      const SizedBox(height: 16),
      if (_stories)
        StoryBrowser(
          initialStory:
              widget.orchestrator.requestedStory ??
              widget.orchestrator.settingsDrafts['story'],
          onSelected: (id) => widget.orchestrator.settingsDrafts['story'] = id,
        )
      else
        _diagnostics(),
    ],
  );

  Widget _diagnostics() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        tr("Inspect state and preview dictation."),
        style: const TextStyle(height: 1.6),
      ),
      const SizedBox(height: 16),
      const SizedBox(
        height: 132,
        child: ColoredBox(
          color: Color(0xFF43464A),
          child: DictationIndicator(
            label: 'Listening • preview',
            hint: 'Release shortcut to finish',
            level: 0.65,
            recording: true,
            transcript: 'No microphone is open for this preview.',
          ),
        ),
      ),
      const SizedBox(height: 12),
      TextButton.icon(
        icon: const Icon(Icons.input),
        label: Text(
          _testingInsertion
              ? tr("Click the destination text field now…")
              : tr("Test insertion after 5 seconds"),
        ),
        onPressed: _testingInsertion || !widget.orchestrator.isAvailable
            ? null
            : () async {
                setState(() {
                  _testingInsertion = true;
                  error = '';
                });
                try {
                  await widget.orchestrator.testTextInsertion(
                    source.text.trim().isEmpty
                        ? 'AuraScribe focus test 4837.'
                        : source.text,
                  );
                  if (mounted) {
                    setState(
                      () => output = 'Test text sent to the original field. No microphone or model was used.',
                    );
                  }
                } catch (e) {
                  if (mounted) setState(() => error = e.toString());
                } finally {
                  if (mounted) setState(() => _testingInsertion = false);
                }
              },
      ),
      Text(
        tr("Click a text field during the countdown."),
        style: const TextStyle(fontSize: 12, height: 1.5),
      ),
      const SizedBox(height: 16),
      PreferenceGroup(
        children: [
          PreferenceRow(
            icon: Icons.monitor_heart_outlined,
            title: tr("Current state"),
            subtitle: tr(
              "{v0} • {v1}\nExternal task: {v2}",
              values: {
                "v0": widget.orchestrator.state.name,
                "v1": widget.transcription.modelLabel,
                "v2": widget.orchestrator.externalActivity ?? 'none',
              },
            ),
          ),
          PreferenceRow(
            icon: Icons.folder_outlined,
            title: tr("Project storage"),
            subtitle: ProjectStorage.instance.root.path,
          ),
        ],
      ),
      const SizedBox(height: 16),
      TextField(
        controller: application,
        decoration: InputDecoration(
          labelText: tr("Target application bundle ID"),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: source,
        minLines: 4,
        maxLines: 8,
        decoration: InputDecoration(labelText: tr("Pipeline test text")),
      ),
      TextButton(
        onPressed: () async {
          try {
            if (!widget.orchestrator.isAvailable) {
              throw StateError('Finish the current audio task first.');
            }
            widget.orchestrator.externalActivity = 'Pipeline preview';
            final steps = PipelineStore.resolve(
              await PipelineStore().read(),
              application.text.trim(),
            );
            final result = await widget.orchestrator.previewOutput(
              source.text,
              steps,
            );
            if (mounted) {
              setState(() {
                output = result;
                error = '';
              });
            }
          } catch (e) {
            if (mounted) setState(() => error = e.toString());
          } finally {
            widget.orchestrator.externalActivity = null;
          }
        },
        child: Text(tr("Run pipeline preview")),
      ),
      if (error.isNotEmpty)
        Text(
          error,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (output.isNotEmpty) SelectableText(output),
      const SizedBox(height: 16),
      TextButton(
        onPressed: () async {
          final directory = await ProjectStorage.instance.directory(
            'diagnostics',
          );
          final file = File('${directory.path}/diagnostics.json');
          final data = {
            'events': ActivityLog.instance.events,
            'time': DateTime.now().toUtc().toIso8601String(),
            'platform': Platform.operatingSystemVersion,
            'dart': Platform.version,
            'state': widget.orchestrator.state.name,
            'model': widget.transcription.modelLabel,
            'loaded': widget.transcription.isLoaded,
            'engine': widget.transcription.activeEngine.name,
            'projectStorage': ProjectStorage.instance.root.path,
            'processRssBytes': ProcessInfo.currentRss,
            'processPeakRssBytes': ProcessInfo.maxRss,
            'shortcuts': widget.settings.shortcuts.map(
              (action, binding) => MapEntry(action.name, binding.label),
            ),
          };
          await file.writeAsString(
            const JsonEncoder.withIndent('  ').convert(data),
            flush: true,
          );
          await Process.run('open', ['-R', file.path]);
        },
        child: Text(tr("Export diagnostics (no tokens, audio or transcripts)")),
      ),
      const SizedBox(height: 16),
      Text(
        tr("Recent activity"),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      for (final event in ActivityLog.instance.events.take(20))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '${event['time']} • ${event['event']} • ${event['state'] ?? ''}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
    ],
  );
}
