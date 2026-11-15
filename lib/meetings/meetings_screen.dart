import '../l10n/app_localizations.dart';
import '../l10n/status_message.dart';

import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../app/dictation_orchestrator.dart';
import '../grammar/grammar_service.dart';
import '../settings/settings_service.dart';
import '../settings/settings_shell.dart';
import '../transcription/transcription_service.dart';
import 'meeting_service.dart';

class MeetingsScreen extends StatefulWidget {
  final DictationOrchestrator orchestrator;
  final TranscriptionService transcription;
  final GrammarService grammar;
  final SettingsService settings;
  const MeetingsScreen({
    super.key,
    required this.orchestrator,
    required this.transcription,
    required this.grammar,
    required this.settings,
  });
  @override
  State<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends State<MeetingsScreen>
    with AutomaticKeepAliveClientMixin {
  late final service = widget.orchestrator.meetings;
  final title = TextEditingController();
  List<Directory> _meetings = [];
  bool _mic = true,
      _system = true,
      _echo = true,
      _diarize = false,
      _busy = false;
  String? _error;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    final drafts = widget.orchestrator.settingsDrafts;
    title.text = drafts['meetingTitle'] ?? '';
    _mic = drafts['meetingMic'] != 'false';
    _system = drafts['meetingSystem'] != 'false';
    _echo = drafts['meetingEcho'] != 'false';
    _diarize = drafts['meetingDiarize'] == 'true';
    service.addListener(_refresh);
    _list();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _list() async {
    final values = await service.list();
    if (mounted) setState(() => _meetings = values);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _list();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    service.removeListener(_refresh);
    widget.orchestrator.settingsDrafts.addAll({
      'meetingTitle': title.text,
      'meetingMic': '$_mic',
      'meetingSystem': '$_system',
      'meetingEcho': '$_echo',
      'meetingDiarize': '$_diarize',
    });
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final locked = service.recording || service.processing || _busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr("Record microphone and system audio."),
          style: const TextStyle(height: 1.6),
        ),
        const SizedBox(height: 16),
        if (_error != null || service.error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SelectableText(
              _error ?? service.error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        SwitchListTile(
          title: Text(tr("Browser-tab naming")),
          subtitle: Text(tr("Use the active browser tab as the title.")),
          value: widget.settings.option('browserTabNaming', fallback: true),
          onChanged: locked
              ? null
              : (value) async {
                  await widget.settings.setOption('browserTabNaming', value);
                  if (mounted) setState(() {});
                },
        ),
        SwitchListTile(
          title: Text(tr("Browser Automation fallback")),
          subtitle: Text(tr("Use Automation when tab access fails.")),
          value: widget.settings.option('browserTabAutomation'),
          onChanged: locked
              ? null
              : (value) async {
                  await widget.settings.setOption(
                    'browserTabAutomation',
                    value,
                  );
                  if (mounted) setState(() {});
                },
        ),
        PreferenceGroup(
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: TextField(
                controller: title,
                enabled: !locked,
                decoration: InputDecoration(labelText: tr("Meeting title")),
              ),
            ),
            SwitchListTile(
              title: Text(tr("Microphone")),
              value: _mic,
              onChanged: locked ? null : (v) => setState(() => _mic = v),
            ),
            SwitchListTile(
              title: Text(tr("System audio")),
              value: _system,
              onChanged: locked ? null : (v) => setState(() => _system = v),
            ),
            SwitchListTile(
              title: Text(tr("Echo cancellation")),
              subtitle: Text(
                tr("Use macOS voice processing on the microphone track."),
              ),
              value: _echo,
              onChanged: locked ? null : (v) => setState(() => _echo = v),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy || service.processing
                        ? null
                        : () => _run(() async {
                            if (service.recording) {
                              await service.stop();
                            } else {
                              await service.start(
                                title.text,
                                microphone: _mic,
                                system: _system,
                                echoCancellation: _echo,
                              );
                            }
                          }),
                    icon: Icon(
                      service.recording
                          ? Icons.stop
                          : Icons.fiber_manual_record,
                    ),
                    label: Text(
                      service.recording
                          ? tr("Stop & save")
                          : tr("Record meeting"),
                    ),
                  ),
                  TextButton(
                    onPressed: locked ? null : () => _run(service.importAudio),
                    child: Text(tr("Import audio")),
                  ),
                  TextButton(
                    onPressed: () => _run(() async {
                      await MeetingService.channel.invokeMethod<bool>(
                        'requestScreenAccess',
                      );
                    }),
                    child: Text(tr("System audio permission")),
                  ),
                ],
              ),
            ),
          ],
        ),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: widget.settings.meetingSummaryProvider,
          decoration: InputDecoration(
            labelText: tr("Meeting names and summaries"),
          ),
          items: [
            DropdownMenuItem(value: 'off', child: Text(tr("Off"))),
            DropdownMenuItem(value: 'local', child: Text(tr("On this Mac"))),
            DropdownMenuItem(
              value: 'opencode',
              child: Text(
                tr("OpenCode (sends transcript to configured provider)"),
              ),
            ),
          ],
          onChanged: locked
              ? null
              : (value) {
                  if (value != null) {
                    _run(
                      () => widget.settings.setMeetingSummaryProvider(value),
                    );
                  }
                },
        ),
        const SizedBox(height: 16),
        PreferenceGroup(
          children: [
            for (final entry in const {
              'detectCalls':
                  'Detect microphone activity in call apps (macOS 14.2+)',
              'autoRecordCalls': 'Automatically record detected calls',
              'stopWhenCallEnds': 'Stop automatic recording when the call ends',
              'meetingCapsule': 'Floating draggable meeting controls',
              'liveMeetings': 'Live meeting transcript',
              'liveChapters': 'Local live chapter headings',
            }.entries)
              SwitchListTile(
                title: Text(tr(entry.value)),
                value: widget.settings.option(entry.key),
                onChanged: locked
                    ? null
                    : (value) => _run(() async {
                        await widget.settings.setOption(entry.key, value);
                        await service.configure();
                      }),
              ),
          ],
        ),
        if (service.status.isNotEmpty) Text(localizedStatus(service.status)),
        if (service.liveText.isNotEmpty)
          SizedBox(
            height: 180,
            child: SingleChildScrollView(
              reverse: true,
              child: SelectableText(service.liveText),
            ),
          ),
        if (service.processing) ...[
          const LinearProgressIndicator(),
          TextButton(
            onPressed: service.cancelProcessing,
            child: Text(tr("Stop after current step")),
          ),
        ],
        PreferenceGroup(
          children: [
            SwitchListTile(
              title: Text(tr("Identify remote speakers")),
              subtitle: Text(
                tr("Anonymous speakers. Downloads models on first use."),
              ),
              value: _diarize,
              onChanged: locked ? null : (v) => setState(() => _diarize = v),
            ),
            PreferenceRow(
              icon: Icons.auto_delete_outlined,
              title: tr("Move old meetings to Trash"),
              trailing: DropdownButton<int>(
                isExpanded: true,
                value: widget.settings.meetingRetentionDays,
                items: [
                  DropdownMenuItem(value: 0, child: Text(tr("Keep all"))),
                  DropdownMenuItem(value: 7, child: Text(tr("After 7 days"))),
                  DropdownMenuItem(value: 30, child: Text(tr("After 30 days"))),
                ],
                onChanged: locked
                    ? null
                    : (days) => _run(() async {
                        if (days != null) {
                          await widget.settings.setMeetingRetentionDays(days);
                          await service.applyRetention(days);
                        }
                      }),
              ),
            ),
          ],
        ),
        PreferenceRow(
          icon: Icons.audio_file_outlined,
          title: tr("Expire audio after transcription"),
          subtitle: tr("Keep transcripts and notes."),
          trailing: DropdownButton<int>(
            value:
                int.tryParse(
                  widget.settings.optionText('meetingAudioDays', '0'),
                ) ??
                0,
            items: [
              DropdownMenuItem(value: 0, child: Text(tr("Keep audio"))),
              DropdownMenuItem(value: 7, child: Text(tr("7 days"))),
              DropdownMenuItem(value: 30, child: Text(tr("30 days"))),
            ],
            onChanged: locked
                ? null
                : (days) => _run(() async {
                    if (days != null) {
                      await widget.settings.setOptionText(
                        'meetingAudioDays',
                        '$days',
                      );
                      await service.expireAudio(days);
                    }
                  }),
          ),
        ),
        const SizedBox(height: 24),
        if (_meetings.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(tr("Your recorded meetings will appear here.")),
          ),
        for (final directory in _meetings)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: FutureBuilder<Map<String, dynamic>>(
              future: service.metadata(directory),
              builder: (context, snapshot) {
                final data = snapshot.data;
                return PreferenceGroup(
                  children: [
                    PreferenceRow(
                      icon: Icons.groups_outlined,
                      title:
                          data?['title'] as String? ??
                          directory.uri.pathSegments
                              .where((p) => p.isNotEmpty)
                              .last,
                      subtitle:
                          '${data?['startedAt'] ?? ''} • ${data?['state'] ?? 'Unfinished recording'}',
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: locked
                                ? null
                                : () => _run(
                                    () => service.transcribe(
                                      directory,
                                      diarize: _diarize,
                                    ),
                                  ),
                            child: Text(tr("Transcribe")),
                          ),
                          if (data?['state'] == 'interrupted')
                            TextButton(
                              onPressed: locked
                                  ? null
                                  : () => _run(
                                      () => service.transcribe(
                                        directory,
                                        diarize:
                                            data?['processingDiarize'] == true,
                                        resume: true,
                                      ),
                                    ),
                              child: Text(tr("Resume transcription")),
                            ),
                          TextButton(
                            onPressed: locked
                                ? null
                                : () => _run(
                                    () => service.notes(
                                      directory,
                                      provider: widget
                                          .settings
                                          .meetingSummaryProvider,
                                    ),
                                  ),
                            child: Text(tr("Generate notes")),
                          ),
                          TextButton(
                            onPressed: locked
                                ? null
                                : () async {
                                    final editor = TextEditingController(
                                      text: data?['title'] as String? ?? '',
                                    );
                                    String? name;
                                    try {
                                      name = await widget.orchestrator
                                          .withSettingsDialog(
                                            () => showDialog<String>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: Text(
                                                  tr("Rename meeting"),
                                                ),
                                                content: TextField(
                                                  controller: editor,
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(context),
                                                    child: Text(tr("Cancel")),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          context,
                                                          editor.text,
                                                        ),
                                                    child: Text(tr("Save")),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                    } finally {
                                      editor.dispose();
                                    }
                                    if (name != null) {
                                      await _run(
                                        () => service.rename(directory, name!),
                                      );
                                    }
                                  },
                            child: Text(tr("Rename")),
                          ),
                          TextButton(
                            onPressed: () => _run(() async {
                              await Process.run('open', [directory.path]);
                            }),
                            child: Text(tr("Open files")),
                          ),
                          TextButton(
                            onPressed: locked
                                ? null
                                : () => _run(() => service.trash(directory)),
                            child: Text(tr("Move to Trash")),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}
