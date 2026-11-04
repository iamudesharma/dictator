import 'dart:io';
import 'package:flutter/material.dart';
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
  const MeetingsScreen(
      {super.key,
      required this.orchestrator,
      required this.transcription,
      required this.grammar,
      required this.settings});
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text(
          'Record local and remote participants into separate project-local WAV tracks. System audio requires Screen & System Audio Recording access.',
          style: TextStyle(height: 1.6)),
      const SizedBox(height: 16),
      if (_error != null || service.error.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SelectableText(_error ?? service.error,
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
      PreferenceGroup(children: [
        Padding(
            padding: const EdgeInsets.all(18),
            child: TextField(
                controller: title,
                enabled: !locked,
                decoration: const InputDecoration(labelText: 'Meeting title'))),
        SwitchListTile(
            title: const Text('Microphone'),
            value: _mic,
            onChanged: locked ? null : (v) => setState(() => _mic = v)),
        SwitchListTile(
            title: const Text('System audio'),
            value: _system,
            onChanged: locked ? null : (v) => setState(() => _system = v)),
        SwitchListTile(
            title: const Text('Echo cancellation'),
            subtitle: const Text(
                'Use macOS voice processing on the microphone track.'),
            value: _echo,
            onChanged: locked ? null : (v) => setState(() => _echo = v)),
        Padding(
            padding: const EdgeInsets.all(18),
            child: Wrap(spacing: 12, runSpacing: 8, children: [
              FilledButton.icon(
                  onPressed: _busy || service.processing
                      ? null
                      : () => _run(() async {
                            if (service.recording) {
                              await service.stop();
                            } else {
                              await service.start(title.text,
                                  microphone: _mic,
                                  system: _system,
                                  echoCancellation: _echo);
                            }
                          }),
                  icon: Icon(service.recording
                      ? Icons.stop
                      : Icons.fiber_manual_record),
                  label: Text(
                      service.recording ? 'Stop & save' : 'Record meeting')),
              TextButton(
                  onPressed: () => _run(() async {
                        await MeetingService.channel
                            .invokeMethod<bool>('requestScreenAccess');
                      }),
                  child: const Text('System audio permission')),
            ])),
      ]),
      const SizedBox(height: 16),
      if (service.status.isNotEmpty) Text(service.status),
      if (service.processing) ...[
        const LinearProgressIndicator(),
        TextButton(
            onPressed: service.cancelProcessing,
            child: const Text('Stop after current step'))
      ],
      PreferenceGroup(children: [
        SwitchListTile(
            title: const Text('Identify remote speakers'),
            subtitle: const Text(
                'Downloads segmentation and speaker embedding models into this project when used. Speaker numbers are anonymous, not identities.'),
            value: _diarize,
            onChanged: locked ? null : (v) => setState(() => _diarize = v)),
        PreferenceRow(
            icon: Icons.auto_delete_outlined,
            title: 'Move old meetings to Trash',
            trailing: DropdownButton<int>(
                isExpanded: true,
                value: widget.settings.meetingRetentionDays,
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Keep all')),
                  DropdownMenuItem(value: 7, child: Text('After 7 days')),
                  DropdownMenuItem(value: 30, child: Text('After 30 days'))
                ],
                onChanged: locked
                    ? null
                    : (days) => _run(() async {
                          if (days != null) {
                            await widget.settings.setMeetingRetentionDays(days);
                            await service.applyRetention(days);
                          }
                        }))),
      ]),
      const SizedBox(height: 24),
      if (_meetings.isEmpty)
        const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Your recorded meetings will appear here.')),
      for (final directory in _meetings)
        Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: FutureBuilder<Map<String, dynamic>>(
                future: service.metadata(directory),
                builder: (context, snapshot) {
                  final data = snapshot.data;
                  return PreferenceGroup(children: [
                    PreferenceRow(
                        icon: Icons.groups_outlined,
                        title: data?['title'] as String? ??
                            directory.uri.pathSegments
                                .where((p) => p.isNotEmpty)
                                .last,
                        subtitle:
                            '${data?['startedAt'] ?? ''} • ${data?['state'] ?? 'Unfinished recording'}'),
                    Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                        child: Wrap(spacing: 8, children: [
                          TextButton(
                              onPressed: locked
                                  ? null
                                  : () => _run(() => service.transcribe(
                                      directory,
                                      diarize: _diarize)),
                              child: const Text('Transcribe')),
                          TextButton(
                              onPressed: locked
                                  ? null
                                  : () => _run(() => service.notes(directory)),
                              child: const Text('Generate notes')),
                          TextButton(
                              onPressed: () => _run(() async {
                                    await Process.run('open', [directory.path]);
                                  }),
                              child: const Text('Open files')),
                          TextButton(
                              onPressed: locked
                                  ? null
                                  : () => _run(() => service.trash(directory)),
                              child: const Text('Move to Trash')),
                        ])),
                  ]);
                })),
    ]);
  }
}
