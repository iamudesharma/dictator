import '../l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'output_pipeline.dart';
import '../transcription/gguf_catalog.dart';

class PipelineEditor extends StatefulWidget {
  final OutputProfile? profile;
  const PipelineEditor({super.key, this.profile});
  @override
  State<PipelineEditor> createState() => _PipelineEditorState();
}

class _PipelineEditorState extends State<PipelineEditor> {
  late final _application =
      TextEditingController(text: widget.profile?.application ?? '*');
  late final List<OutputStep> _steps = [...?widget.profile?.steps];
  late bool _includeDefault = widget.profile?.includeDefault ?? true;
  late String _speechModel = widget.profile?.speechModel ?? '';
  late final _language =
      TextEditingController(text: widget.profile?.language ?? '');
  String? _error;
  @override
  void dispose() {
    _application.dispose();
    _language.dispose();
    super.dispose();
  }

  Future<void> _step([int? index]) async {
    var kind = index == null ? OutputStepKind.cleanup : _steps[index].kind;
    final value =
        TextEditingController(text: index == null ? '' : _steps[index].value);
    final step = await showDialog<OutputStep>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                    title: Text(tr("Output step")),
                    content: SizedBox(
                        width: 420,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          DropdownButton<OutputStepKind>(
                              value: kind,
                              isExpanded: true,
                              items: OutputStepKind.values
                                  .map((k) => DropdownMenuItem(
                                      value: k, child: Text(tr(k.name))))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) update(() => kind = v);
                              }),
                          if ({
                            OutputStepKind.replacements,
                            OutputStepKind.translate,
                            OutputStepKind.instruction
                          }.contains(kind))
                            TextField(
                                controller: value,
                                minLines: 2,
                                maxLines: 5,
                                decoration: InputDecoration(
                                    labelText: switch (kind) {
                                  OutputStepKind.replacements =>
                                    'One heard = replacement per line',
                                  OutputStepKind.translate => 'Target language',
                                  _ => 'Instruction'
                                })),
                        ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(tr("Cancel"))),
                      FilledButton(
                          onPressed: () => Navigator.pop(
                              context, OutputStep(kind, value.text.trim())),
                          child: Text(tr("Add step")))
                    ])));
    value.dispose();
    if (step != null && mounted) {
      setState(() {
        if (index == null) {
          _steps.add(step);
        } else {
          _steps[index] = step;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(tr("Output pipeline")),
          content: SizedBox(
              width: 580,
              height: 560,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                        controller: _application,
                        decoration: InputDecoration(
                            labelText: tr("Application bundle ID"),
                            helperText: tr(
                                "Use * for every app, e.g. com.apple.mail for Mail."))),
                    DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _speechModel,
                        decoration: InputDecoration(
                            labelText: tr("Speech model for this mode")),
                        items: [
                          DropdownMenuItem(
                              value: '',
                              child: Text(tr("Follow current model"))),
                          for (final engine in [
                            'whisper',
                            'gemma',
                            'moonshine',
                            'nemotron',
                            'apple'
                          ])
                            DropdownMenuItem(
                                value: engine, child: Text(engine)),
                          for (final model in ggufCatalog)
                            DropdownMenuItem(
                                value: 'gguf:${model.id}',
                                child: Text(model.name))
                        ],
                        onChanged: (value) =>
                            setState(() => _speechModel = value ?? '')),
                    TextField(
                        controller: _language,
                        decoration: InputDecoration(
                            labelText: tr(
                                "Language code (blank follows current, auto detects)"))),
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(tr("Include the default pipeline")),
                        value: _includeDefault,
                        onChanged: (v) => setState(() => _includeDefault = v)),
                    Expanded(
                        child: ReorderableListView.builder(
                            itemCount: _steps.length,
                            onReorderItem: (from, to) => setState(() {
                                  final step = _steps.removeAt(from);
                                  _steps.insert(to, step);
                                }),
                            itemBuilder: (context, index) => ListTile(
                                key: ValueKey(_steps[index]),
                                onTap: () => _step(index),
                                title: Text(tr(_steps[index].kind.name)),
                                subtitle: Text(_steps[index].value,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                trailing: Padding(
                                    padding: const EdgeInsets.only(right: 28),
                                    child: IconButton(
                                        tooltip: tr("Remove step"),
                                        icon: const Icon(
                                            Icons.remove_circle_outline),
                                        onPressed: () => setState(
                                            () => _steps.removeAt(index))))))),
                    TextButton.icon(
                        onPressed: () => _step(),
                        icon: const Icon(Icons.add),
                        label: Text(tr("Add processing step"))),
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                  ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr("Cancel"))),
            FilledButton(
                onPressed: () {
                  try {
                    final profile = OutputProfile(
                        _application.text.trim(), _steps,
                        includeDefault: _includeDefault,
                        speechModel: _speechModel.isEmpty ? null : _speechModel,
                        language: _language.text.trim().isEmpty
                            ? null
                            : _language.text.trim());
                    PipelineStore.validate([profile]);
                    Navigator.pop(context, profile);
                  } catch (e) {
                    setState(() => _error = e.toString());
                  }
                },
                child: Text(tr("Save pipeline")))
          ]);
}
