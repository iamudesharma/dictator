import 'app_localizations.dart';

/// Controllers keep stable English status text for logs/state. Only presentation
/// uses these explicit templates, so translated data never affects control flow.
String localizedStatus(String message) {
  const templates = [
    'Microphone activity detected in {v0}',
    'Call detected: {v0}',
    'Transcribing {v0}: {v1} / {v2} seconds',
    'Downloading update: {v0}%',
    'Update {v0} is available.',
  ];
  for (final template in templates) {
    final parts = template.split(RegExp(r'\{v\d+\}'));
    final match = RegExp('^${parts.map(RegExp.escape).join('(.+?)')}\$')
        .firstMatch(message);
    if (match != null) {
      return tr(template, values: {
        for (var i = 0; i < match.groupCount; i++) 'v$i': match.group(i + 1)
      });
    }
  }
  return tr(message);
}
