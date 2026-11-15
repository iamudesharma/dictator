import '../l10n/app_localizations.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../app/dictation_orchestrator.dart';
import 'settings_service.dart';

class OnboardingCard extends StatefulWidget {
  final DictationOrchestrator orchestrator;
  final SettingsService settings;
  const OnboardingCard({
    super.key,
    required this.orchestrator,
    required this.settings,
  });
  @override
  State<OnboardingCard> createState() => _OnboardingCardState();
}

class _OnboardingCardState extends State<OnboardingCard> {
  String _text = '', _error = '';
  bool _busy = false;
  Future<void> _practice() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await widget.orchestrator.dictateTo((text) async {
        if (mounted) setState(() => _text = text);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr("Quick setup"),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(tr("Choose a model, allow access, then try dictation.")),
          Wrap(
            spacing: 10,
            children: [
              TextButton(
                onPressed: () =>
                    const MethodChannel('com.aurascribe/accessibility')
                        .invokeMethod<void>('requestPermission'),
                child: Text(tr("Grant Accessibility")),
              ),
              FilledButton(
                onPressed: _busy ? null : _practice,
                child: Text(
                  widget.orchestrator.state.name == 'recording'
                      ? tr("Stop practice")
                      : tr("Try dictation"),
                ),
              ),
              TextButton(
                onPressed: () async {
                  await widget.settings.setOption('onboardingComplete', true);
                  widget.orchestrator.refreshPreferences();
                },
                child: Text(
                  _text.isEmpty ? tr("Set up later") : tr("Finish setup"),
                ),
              ),
            ],
          ),
          if (_text.isNotEmpty) SelectableText(_text),
          if (_error.isNotEmpty)
            Text(
              _error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
  );
}
