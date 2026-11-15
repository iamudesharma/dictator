/// Stable page IDs preserve drafts, search destinations and native deep links.
const settingsPageCount = 14;
const coreSettingsPages = [0, 1, 2, 6, 5, 10];

class SettingsFeature {
  final int page;
  final String id, label, description;
  const SettingsFeature(this.page, this.id, this.label, this.description);
}

const optionalSettingsFeatures = [
  SettingsFeature(3, 'words', 'Vocabulary', 'Names and replacements.'),
  SettingsFeature(4, 'history', 'History', 'Recent dictation.'),
  SettingsFeature(7, 'meetings', 'Meetings', 'Record and transcribe calls.'),
  SettingsFeature(8, 'voice', 'Voice filter', 'Clean up microphone audio.'),
  SettingsFeature(9, 'capture', 'Capture', 'Screenshots and annotations.'),
  SettingsFeature(12, 'commands', 'Commands', 'Rewrite selected text.'),
  SettingsFeature(13, 'api', 'API', 'Connect local tools.'),
  SettingsFeature(11, 'developer', 'Developer', 'Stories and diagnostics.'),
];
