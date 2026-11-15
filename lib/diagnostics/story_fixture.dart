import 'package:material_ui/material_ui.dart';
import '../l10n/app_localizations.dart';
import '../settings/settings_shell.dart';
import '../shared/dictation_indicator.dart';
import '../transcription/gguf_catalog.dart';
import 'story_catalog.dart';

/// Only in-memory fixture values live here. No service/channel dependencies.
class StoryFixture extends StatefulWidget {
  final AppStory story;
  const StoryFixture({super.key, required this.story});
  @override
  State<StoryFixture> createState() => _StoryFixtureState();
}

class _StoryFixtureState extends State<StoryFixture> {
  bool enabled = true, complete = false;
  double level = .65;
  int selected = 0;
  final points = <Offset?>[];
  final editor = TextEditingController(text: 'Design review');
  String get state => widget.story.state;
  @override
  void initState() {
    super.initState();
    enabled = !['muted', 'empty', 'denied', 'missing'].contains(state);
  }

  @override
  void dispose() {
    editor.dispose();
    super.dispose();
  }

  Widget text(String value) => Text(context.tr(value));
  Widget action(String label, VoidCallback callback) =>
      TextButton(onPressed: callback, child: text(label));
  Widget row(String title, String subtitle, {Widget? trailing}) =>
      PreferenceRow(
          icon: Icons.tune,
          title: context.tr(title),
          subtitle: context.tr(subtitle),
          trailing: trailing);
  Widget toggle(String title) => SwitchListTile(
      title: text(title),
      value: enabled,
      onChanged: (v) => setState(() => enabled = v));
  Widget progress(String label) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        text(label),
        LinearProgressIndicator(value: level),
        Slider(value: level, onChanged: (v) => setState(() => level = v))
      ]);
  Widget permission(String label) => Column(children: [
        Icon(enabled ? Icons.check_circle_outline : Icons.lock_outline,
            size: 44),
        text(label),
        toggle('Permission granted'),
        text('Preview only')
      ]);
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.tr(widget.story.title),
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        text('Preview only'),
        const Divider(height: 28),
        ...switch (widget.story.family) {
          StoryFamily.indicator => [
              SizedBox(
                  height: 130,
                  child: DictationIndicator(
                      animated: false,
                      label: context.tr(state == 'error'
                          ? 'Microphone unavailable'
                          : widget.story.title),
                      hint: context.tr('Release shortcut to finish'),
                      level: level,
                      recording:
                          ['recording', 'live'].contains(state) && enabled,
                      preparing: state == 'preparing',
                      error: state == 'error')),
              if (state == 'live')
                const SelectableText(
                    'Let’s review the design and agree on the next steps.'),
              if (['recording', 'live'].contains(state)) ...[
                toggle('Recording'),
                Slider(
                    value: level, onChanged: (v) => setState(() => level = v))
              ],
              if (state == 'error') permission('Microphone'),
            ],
          StoryFamily.settings => [
              PreferenceGroup(children: [
                if (state == 'general') ...[
                  row('Appearance', 'Follow system'),
                  toggle('Copy only'),
                  toggle('Notch indicator')
                ],
                if (state == 'permissions') ...[
                  permission('Accessibility'),
                  permission('Microphone')
                ],
                if (state == 'microphone') ...[
                  row('Microphone', 'Built-in microphone'),
                  VoiceLevelBars(level: level),
                  Slider(
                      value: level, onChanged: (v) => setState(() => level = v))
                ],
                if (state == 'missing') ...[
                  row('Microphone unavailable', 'Choose another microphone'),
                  toggle('Microphone connected')
                ],
                if (state == 'audio') ...[
                  toggle('Lower volume'),
                  progress('Volume while recording')
                ],
                if (state == 'memory') ...[
                  toggle('Release models when idle'),
                  row('Release after', '60 s')
                ],
              ])
            ],
          StoryFamily.shortcut => [
              row('Dictation shortcut',
                  state == 'right' ? 'Right Option' : 'Left Option',
                  trailing: Chip(
                      label: Text(state == 'right' ? '⌥ Right' : '⌥ Left'))),
              if (state == 'conflict') text('This shortcut is already in use.'),
              if (state == 'recording' && !complete) text('Press a shortcut'),
              if (state == 'saved' || complete) text('Shortcut saved'),
              action(complete ? 'Record again' : 'Save shortcut',
                  () => setState(() => complete = !complete)),
              toggle('Hold to dictate'),
            ],
          StoryFamily.models => [
              if (state == 'language') row('Language', 'Japanese'),
              if (state == 'custom') ...[
                TextField(
                    controller: editor,
                    decoration:
                        InputDecoration(labelText: context.tr('Model name'))),
                action('Add model', () => setState(() => complete = true))
              ],
              if (state == 'failed' && !complete) ...[
                text('Download failed'),
                action('Retry', () => setState(() => complete = true))
              ],
              if (state == 'downloading' || complete)
                progress('Downloading model'),
              for (var i = 0; i < 3; i++)
                ListTile(
                    title: Text(ggufCatalog[i].name),
                    subtitle: text(state == 'installed'
                        ? 'Downloaded'
                        : 'Available to download'),
                    trailing: Icon(selected == i
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off),
                    onTap: () => setState(() => selected = i)),
            ],
          StoryFamily.output => [
              if (state == 'app') row('Application', 'TextEdit'),
              if (state == 'unavailable') ...[
                text('Provider unavailable'),
                action('Retry', () => setState(() => complete = true)),
                if (complete) text('Ready')
              ] else if (state == 'empty' && !complete) ...[
                text('No output steps'),
                action('Add step', () => setState(() => complete = true))
              ] else ...[
                ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorderItem: (_, __) =>
                        setState(() => selected = 1 - selected),
                    children: [
                      for (final item in selected == 0
                          ? ['Preferred spelling', 'Grammar cleanup']
                          : ['Grammar cleanup', 'Preferred spelling'])
                        ListTile(
                            key: ValueKey(item),
                            title: text(item),
                            trailing: const Icon(Icons.drag_handle)),
                    ]),
                if (state == 'preview') ...[
                  TextField(
                      controller: editor,
                      decoration: InputDecoration(
                          labelText: context.tr('Sample text'))),
                  action('Preview', () => setState(() => complete = true)),
                  if (complete) SelectableText(editor.text)
                ],
              ],
            ],
          StoryFamily.onboarding => [
              if (['permissions', 'denied'].contains(state))
                permission('Microphone and Accessibility'),
              if (state == 'downloading') progress('Downloading model'),
              if (state == 'practice') ...[
                text('Hold Option and speak'),
                TextField(
                    controller: editor,
                    decoration:
                        InputDecoration(labelText: context.tr('Practice text')))
              ],
              if (state == 'welcome') ...[
                const Icon(Icons.graphic_eq, size: 48),
                text('Welcome to AuraScribe')
              ],
              if (state == 'ready' || complete) ...[
                const Icon(Icons.check_circle, size: 48),
                text('Ready to dictate')
              ] else
                action('Continue', () => setState(() => complete = true)),
            ],
          StoryFamily.history => [
              if (state == 'empty' || complete && state == 'delete')
                text('No dictations yet')
              else ...[
                const SelectableText(
                    'Send the updated design tomorrow morning.'),
                row('Speech model', 'Whisper Small'),
                if (state == 'audio') ...[
                  progress('Saved recording'),
                  toggle('Playing')
                ],
                if (state == 'versions') ...[
                  row('Earlier versions', 'Send the design tomorrow.'),
                  action('Use this version',
                      () => setState(() => complete = true)),
                  if (complete) const Text('Send the design tomorrow.')
                ],
                if (state == 'retention')
                  DropdownButton<int>(
                      value: selected,
                      items: [
                        for (var i = 0; i < 3; i++)
                          DropdownMenuItem(
                              value: i,
                              child: text(['Forever', '7 days', '30 days'][i]))
                      ],
                      onChanged: (v) => setState(() => selected = v!)),
                if (state == 'delete') ...[
                  text('Delete all history?'),
                  action('Delete', () => setState(() => complete = true))
                ],
              ],
            ],
          StoryFamily.meetings => [
              if (state == 'empty')
                text('No meetings yet')
              else if (state == 'permission')
                permission('System audio')
              else ...[
                if (state == 'rename') ...[
                  TextField(
                      controller: editor,
                      decoration: InputDecoration(
                          labelText: context.tr('Meeting title'))),
                  action('Save', () => setState(() => complete = true)),
                  if (complete) Text(editor.text)
                ] else
                  const Text('Design review'),
                if (state == 'browser') ...[
                  row('Browser-tab naming', 'Google Meet · Safari'),
                  text('Design review — Google Meet')
                ],
                if (state == 'recording') ...[
                  row('Recording', enabled ? '00:42' : '00:42 · stopped'),
                  VoiceLevelBars(level: level),
                  action(enabled ? 'Stop & save' : 'Record meeting',
                      () => setState(() => enabled = !enabled))
                ],
                if (state == 'transcribing') progress('Transcribing meeting'),
                if (state == 'failed') ...[
                  text(complete
                      ? 'Transcribing meeting'
                      : 'Interrupted transcription'),
                  action('Resume', () => setState(() => complete = true))
                ],
                if (state == 'chapters') ...[
                  text('Live chapters'),
                  const ListTile(title: Text('00:00 · Design review')),
                  const ListTile(title: Text('00:25 · Next steps'))
                ],
                if (state == 'notes') ...[
                  text('Meeting notes'),
                  const SelectableText(
                      'Decision: simplify the toolbar.\nAction: share the revised design tomorrow.')
                ],
                if (state == 'saved')
                  const SelectableText(
                      'Speaker 1: Let’s review the design.\nSpeaker 2: The toolbar could be simpler.'),
              ],
            ],
          StoryFamily.capture => [
              if (state == 'empty')
                text('No captures yet')
              else if (state == 'permission')
                permission('Screen Recording')
              else if (state == 'draw') ...[
                text('Draw on the preview'),
                SizedBox(
                    height: 220,
                    child: GestureDetector(
                        onPanUpdate: (event) =>
                            setState(() => points.add(event.localPosition)),
                        onPanEnd: (_) => setState(() => points.add(null)),
                        child: ClipRect(
                            child: CustomPaint(
                                painter: _Drawing(List.of(points)),
                                child: const SizedBox.expand())))),
                action('Clear', () => setState(points.clear)),
              ] else ...[
                row(state == 'replay' ? 'Replay buffer' : 'Screen recording',
                    enabled ? '00:15' : 'Stopped'),
                toggle('Recording'),
                if (state == 'replay')
                  action('Save replay', () => setState(() => complete = true)),
                if (complete) text('Replay saved')
              ],
            ],
          StoryFamily.voiceFilter => [
              if (state == 'driver') ...[
                text('Virtual microphone unavailable'),
                action('Preview installed state',
                    () => setState(() => complete = true)),
                if (complete) text('Ready')
              ] else ...[
                toggle('Voice filter'),
                VoiceLevelBars(level: enabled ? level : 0),
                progress('Input gain'),
                row('Output device', 'AuraScribe Microphone')
              ],
            ],
          StoryFamily.updates => [
              if (state == 'checking') progress('Checking for updates'),
              if (state == 'downloading') progress('Downloading update'),
              if (state == 'failed') ...[
                text('Update failed'),
                action('Retry', () => setState(() => complete = true)),
                if (complete) progress('Checking for updates')
              ],
              if (state == 'ready') ...[
                text('Update ready'),
                action(
                    'Preview restart', () => setState(() => complete = true)),
                if (complete) text('Ready')
              ],
            ],
        },
      ]);
}

class _Drawing extends CustomPainter {
  final List<Offset?> points;
  _Drawing(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xFF202630), BlendMode.src);
    final paint = Paint()
      ..color = const Color(0xFF91DED9)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < points.length; i++) {
      if (points[i - 1] != null && points[i] != null) {
        canvas.drawLine(points[i - 1]!, points[i]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Drawing oldDelegate) => true;
}
