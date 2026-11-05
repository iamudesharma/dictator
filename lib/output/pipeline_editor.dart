import 'package:flutter/material.dart';
import 'output_pipeline.dart';

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
  String? _error;
  @override
  void dispose() {
    _application.dispose();
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
                    title: const Text('Output step'),
                    content: SizedBox(
                        width: 420,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          DropdownButton<OutputStepKind>(
                              value: kind,
                              isExpanded: true,
                              items: OutputStepKind.values
                                  .map((k) => DropdownMenuItem(
                                      value: k, child: Text(k.name)))
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
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(
                              context, OutputStep(kind, value.text.trim())),
                          child: const Text('Add step'))
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
          title: const Text('Output pipeline'),
          content: SizedBox(
              width: 580,
              height: 430,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                        controller: _application,
                        decoration: const InputDecoration(
                            labelText: 'Application bundle ID',
                            helperText:
                                'Use * for every app, e.g. com.apple.mail for Mail.')),
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Include the default pipeline'),
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
                                title: Text(_steps[index].kind.name),
                                subtitle: Text(_steps[index].value,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                trailing: Padding(
                                    padding: const EdgeInsets.only(right: 28),
                                    child: IconButton(
                                        tooltip: 'Remove step',
                                        icon: const Icon(
                                            Icons.remove_circle_outline),
                                        onPressed: () => setState(
                                            () => _steps.removeAt(index))))))),
                    TextButton.icon(
                        onPressed: () => _step(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add processing step')),
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                  ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () {
                  try {
                    final profile = OutputProfile(
                        _application.text.trim(), _steps,
                        includeDefault: _includeDefault);
                    PipelineStore.validate([profile]);
                    Navigator.pop(context, profile);
                  } catch (e) {
                    setState(() => _error = e.toString());
                  }
                },
                child: const Text('Save pipeline'))
          ]);
}
