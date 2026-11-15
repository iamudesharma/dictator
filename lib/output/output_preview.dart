import '../l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import '../app/dictation_orchestrator.dart';
import '../settings/settings_service.dart';
import 'output_pipeline.dart';

class OutputPreview extends StatefulWidget {
  final DictationOrchestrator orchestrator;
  final SettingsService settings;
  final VoidCallback onVocabulary;
  const OutputPreview(
      {super.key,
      required this.orchestrator,
      required this.settings,
      required this.onVocabulary});
  @override
  State<OutputPreview> createState() => _OutputPreviewState();
}

class _OutputPreviewState extends State<OutputPreview> {
  final source = TextEditingController(), application = TextEditingController();
  String result = '', error = '';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    source.text = widget.orchestrator.settingsDrafts['outputSource'] ?? '';
    application.text = widget.orchestrator.settingsDrafts['outputApp'] ?? '*';
  }

  @override
  void dispose() {
    widget.orchestrator.settingsDrafts
        .addAll({'outputSource': source.text, 'outputApp': application.text});
    source.dispose();
    application.dispose();
    super.dispose();
  }

  Future<void> run() async {
    if (!widget.orchestrator.isAvailable || busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    widget.orchestrator.externalActivity = 'Output preview';
    try {
      final steps = PipelineStore.resolve(
          await PipelineStore().read(), application.text.trim());
      final value = await widget.orchestrator
          .previewOutput(widget.settings.applyReplacements(source.text), steps);
      if (mounted) setState(() => result = value);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      widget.orchestrator.externalActivity = null;
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> fix() async {
    final heard = TextEditingController(),
        replacement = TextEditingController();
    try {
      final pair = await widget.orchestrator.withSettingsDialog(() =>
          showDialog<(String, String)>(
              context: context,
              builder: (context) => AlertDialog(
                      title: Text(tr("Fix a word or phrase")),
                      content:
                          Column(mainAxisSize: MainAxisSize.min, children: [
                        TextField(
                            controller: heard,
                            decoration: InputDecoration(
                                labelText: tr("Wrong word or phrase"))),
                        TextField(
                            controller: replacement,
                            decoration: InputDecoration(
                                labelText: tr("Preferred spelling")))
                      ]),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(tr("Cancel"))),
                        FilledButton(
                            onPressed: () {
                              if (heard.text.trim().isNotEmpty &&
                                  replacement.text.trim().isNotEmpty &&
                                  !heard.text.contains('=') &&
                                  !heard.text.contains('\n') &&
                                  !replacement.text.contains('\n')) {
                                Navigator.pop(context, (
                                  heard.text.trim(),
                                  replacement.text.trim()
                                ));
                              }
                            },
                            child: Text(tr("Save correction")))
                      ])));
      if (pair != null) {
        await widget.settings.setVocabulary(
            '${widget.settings.vocabulary}\n${pair.$1}=${pair.$2}'.trim());
        if (mounted) await run();
      }
    } finally {
      heard.dispose();
      replacement.dispose();
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
            controller: application,
            decoration: InputDecoration(
                labelText: tr("Try output for application (* for default)"))),
        TextField(
            controller: source,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(labelText: tr("Try output text"))),
        Wrap(children: [
          TextButton(
              onPressed: busy ? null : run, child: Text(tr("Try output"))),
          TextButton(
              onPressed: widget.onVocabulary, child: Text(tr("Vocabulary"))),
          if (result.isNotEmpty)
            TextButton(
                onPressed: busy ? null : fix, child: Text(tr("Fix this")))
        ]),
        if (busy) const LinearProgressIndicator(),
        if (result.isNotEmpty) SelectableText(result),
        if (error.isNotEmpty)
          Text(error,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]);
}
