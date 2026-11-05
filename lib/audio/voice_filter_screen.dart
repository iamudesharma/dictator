import 'package:flutter/material.dart';
import 'package:record/record.dart';
import '../app/dictation_orchestrator.dart';
import '../settings/settings_service.dart';
import '../settings/settings_shell.dart';
import 'voice_filter_service.dart';

class VoiceFilterScreen extends StatefulWidget {
  final DictationOrchestrator orchestrator;
  final SettingsService settings;
  final List<InputDevice> microphones;
  const VoiceFilterScreen(
      {super.key,
      required this.orchestrator,
      required this.settings,
      required this.microphones});
  @override
  State<VoiceFilterScreen> createState() => _VoiceFilterScreenState();
}

class _VoiceFilterScreenState extends State<VoiceFilterScreen> {
  late final service = widget.orchestrator.voiceFilter;
  String? _error;
  SettingsService get s => widget.settings;
  @override
  void initState() {
    super.initState();
    service.addListener(_refresh);
    service.refresh().catchError((Object e) {
      if (mounted) setState(() => _error = e.toString());
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    service.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text(
            'Use macOS voice processing, automatic gain and a noise gate before sending audio to AuraScribe Microphone. Select that microphone in your calling app. Preview works without the driver; use headphones.',
            style: TextStyle(height: 1.6)),
        const SizedBox(height: 16),
        if (_error != null || service.error.isNotEmpty)
          Text(_error ?? service.error,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        PreferenceGroup(children: [
          PreferenceRow(
              icon: Icons.extension_outlined,
              title: 'Virtual microphone driver',
              subtitle: service.installed
                  ? 'Installed and detected'
                  : 'Not installed • installation needs administrator authorization',
              trailing: TextButton(
                  onPressed: service.busy
                      ? null
                      : () => _run(() async {
                            await VoiceFilterService.channel
                                .invokeMethod<void>('installer');
                          }),
                  child: const Text('Open installer'))),
          PreferenceRow(
              icon: Icons.mic_none,
              title: 'Physical input microphone',
              trailing: DropdownButton<String>(
                  isExpanded: true,
                  value: s.voiceMicrophoneId,
                  items: {
                    '': 'System default',
                    for (final mic in widget.microphones.where(
                        (m) => !m.id.startsWith('com.aurascribe.microphone')))
                      mic.id: mic.label,
                    if (s.voiceMicrophoneId.isNotEmpty &&
                        !widget.microphones
                            .any((m) => m.id == s.voiceMicrophoneId))
                      s.voiceMicrophoneId: 'Disconnected input'
                  }
                      .entries
                      .map((e) => DropdownMenuItem(
                          value: e.key,
                          child:
                              Text(e.value, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: service.running || service.busy
                      ? null
                      : (v) => _run(() async {
                            if (v != null) await s.setVoiceMicrophoneId(v);
                          }))),
          SwitchListTile(
              title: const Text('Voice processing & echo cancellation'),
              subtitle: const Text(
                  'macOS applies voice isolation and acoustic echo processing together.'),
              value: s.voiceProcessing,
              onChanged: service.running
                  ? null
                  : (v) => _run(() => s.setVoiceProcessing(v))),
          SwitchListTile(
              title: const Text('Automatic gain control'),
              subtitle: const Text('Requires voice processing.'),
              value: s.voiceAutomaticGain,
              onChanged: service.running || !s.voiceProcessing
                  ? null
                  : (v) => _run(() => s.setVoiceAutomaticGain(v))),
          PreferenceRow(
              icon: Icons.volume_up_outlined,
              title: 'Input gain',
              subtitle: '${s.voiceGain.toStringAsFixed(1)}×',
              trailing: Slider(
                  value: s.voiceGain,
                  min: 0.2,
                  max: 3,
                  divisions: 28,
                  onChanged: service.running
                      ? null
                      : (v) => _run(() => s.setVoiceGain(v)))),
          PreferenceRow(
              icon: Icons.noise_control_off,
              title: 'Noise gate',
              subtitle: '${s.voiceGateDb.round()} dBFS',
              trailing: Slider(
                  value: s.voiceGateDb,
                  min: -90,
                  max: -20,
                  divisions: 70,
                  onChanged: service.running
                      ? null
                      : (v) => _run(() => s.setVoiceGateDb(v)))),
          SwitchListTile(
              title: const Text('Monitor processed audio'),
              subtitle: const Text(
                  'Play the filtered microphone through your output device.'),
              value: s.voiceMonitor,
              onChanged: service.running
                  ? null
                  : (v) => _run(() => s.setVoiceMonitor(v))),
        ]),
        const SizedBox(height: 18),
        LinearProgressIndicator(
            value: ((service.levelDb + 90) / 90).clamp(0, 1)),
        const SizedBox(height: 8),
        Text(
            '${service.levelDb.toStringAsFixed(0)} dBFS • ${service.running ? service.previewOnly ? 'Preview active' : 'Virtual microphone active' : 'Stopped'}'),
        const SizedBox(height: 16),
        Wrap(spacing: 12, children: [
          FilledButton(
              onPressed: service.busy || !service.installed && !service.running
                  ? null
                  : () => _run(() =>
                      service.running ? service.stop() : service.start(s)),
              child: Text(service.running
                  ? 'Stop voice filter'
                  : 'Start virtual microphone')),
          OutlinedButton(
              onPressed: service.busy || service.running
                  ? null
                  : () => _run(() => service.start(s, preview: true)),
              child: const Text('Try audio preview')),
          TextButton(
              onPressed: () => _run(service.refresh),
              child: const Text('Refresh driver status')),
        ]),
      ]);
}
