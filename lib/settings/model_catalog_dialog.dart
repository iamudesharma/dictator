import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../transcription/gguf_catalog.dart';

/// The complete built-in catalog, independent of the page's optional filters.
/// Selecting an entry returns its ID; the existing model loader owns downloads.
class ModelCatalogDialog extends StatefulWidget {
  const ModelCatalogDialog({
    super.key,
    required this.selected,
    this.imported = const {},
  });
  final String selected;
  final Map<String, String> imported;

  @override
  State<ModelCatalogDialog> createState() => _ModelCatalogDialogState();
}

class _ModelCatalogDialogState extends State<ModelCatalogDialog> {
  String _query = '';
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = {
      for (final model in ggufCatalog) model.id: model.name,
      ...widget.imported,
    };
    final sizes = {for (final model in ggufCatalog) model.id: model.bytes};
    final matches =
        options.entries
            .where(
              (entry) => entry.value.toLowerCase().contains(
                _query.trim().toLowerCase(),
              ),
            )
            .toList()
          ..sort((a, b) => a.value.compareTo(b.value));
    return AlertDialog(
      title: Text(tr('All models')),
      content: SizedBox(
        width: 540,
        height: (MediaQuery.sizeOf(context).height * .55).clamp(180, 440),
        child: Column(
          children: [
            TextField(
              key: const ValueKey('catalog-search'),
              decoration: InputDecoration(
                labelText: tr('Filter speech models'),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: Column(
                    children: [
                      for (final entry in matches)
                        ListTile(
                          key: ValueKey('catalog-option-${entry.key}'),
                          leading: Icon(
                            entry.key == widget.selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                          ),
                          title: Text(entry.value),
                          trailing: sizes[entry.key] == null
                              ? null
                              : Text(
                                  '${(sizes[entry.key]! / 1048576).round()} MB',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                          onTap: () => Navigator.of(context).pop(entry.key),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Close')),
        ),
      ],
    );
  }
}
