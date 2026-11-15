import '../l10n/app_localizations.dart';

class SettingsSearchEntry {
  final String label;
  final int page;
  const SettingsSearchEntry(this.label, this.page);

  /// Open the disclosure containing the result rather than landing on a hidden row.
  String? get section {
    final text = label.toLowerCase();
    if (page == 0) {
      if (text.contains('memory') ||
          text.contains('preload') ||
          text.contains('release')) {
        return 'Memory';
      }
      if (text.contains('sound')) {
        return 'Sound';
      }
      if (text.contains('recording audio') ||
          text.contains('volume while') ||
          text.contains('built-in speakers')) {
        return 'Other audio';
      }
      if (text.contains('indicator') ||
          text.contains('launch at login') ||
          text.contains('menu bar') ||
          text.contains('command-q')) {
        return 'Appearance';
      }
      if (text != 'dictation shortcut' &&
          text != 'shortcut mode' &&
          (text.contains('shortcut') ||
              text.contains('modifier') ||
              text.contains('caps lock') ||
              text.contains('button'))) {
        return 'Shortcuts';
      }
    }
    if (page == 1) {
      if (text.contains('benchmark')) {
        return 'Benchmarks';
      }
      if (text.contains('keyboard')) {
        return 'Keyboard switching';
      }
      if (text.contains('existing project') || text.contains('import')) {
        return 'Custom models';
      }
      if (text.contains('unload')) {
        return 'Memory';
      }
      if (text.contains('filter') || text.contains('downloaded models')) {
        return 'Filters';
      }
    }
    if (page == 2) {
      if (text.contains('silence') || text.contains('maximum recording')) {
        return 'Recording limits';
      }
      if (text.contains('terminal') || text.contains('restore clipboard')) {
        return 'Paste behavior';
      }
      if (text.contains('pipeline') ||
          text.contains('try output') ||
          text == 'fix this') {
        return 'Pipelines';
      }
      if (text.contains('spoken') ||
          text.contains('filler') ||
          text.contains('spacing') ||
          text.contains('pause browser') ||
          text.contains('long pauses') ||
          text.contains('live transcript')) {
        return 'Text tools';
      }
    }
    return null;
  }
}

const settingsSearchEntries = <SettingsSearchEntry>[
  SettingsSearchEntry('Features', 6),
  SettingsSearchEntry('Models', 1),
  SettingsSearchEntry('Commands', 12),
  SettingsSearchEntry('API', 13),
  SettingsSearchEntry('Interface language', 0),
  SettingsSearchEntry('Story browser', 11),
  SettingsSearchEntry('Browser-tab naming', 7),
  SettingsSearchEntry('Browser Automation fallback', 7),
  SettingsSearchEntry('Reference an existing project model', 1),
  SettingsSearchEntry('Return to the original app', 2),
  SettingsSearchEntry("Appearance", 0),
  SettingsSearchEntry("Dictation shortcut", 0),
  SettingsSearchEntry("Shortcut mode", 0),
  SettingsSearchEntry("Speech model", 0),
  SettingsSearchEntry("Microphone", 0),
  SettingsSearchEntry("Indicator position", 0),
  SettingsSearchEntry("Mouse dictation shortcut", 0),
  SettingsSearchEntry("Sound volume", 0),
  SettingsSearchEntry("Start & stop sounds", 0),
  SettingsSearchEntry(
    "A rising tone means ready; a falling tone means stopped.",
    0,
  ),
  SettingsSearchEntry("Release after", 0),
  SettingsSearchEntry("Recording audio", 0),
  SettingsSearchEntry("Volume while recording", 0),
  SettingsSearchEntry("Accessibility", 0),
  SettingsSearchEntry("Copy only", 0),
  SettingsSearchEntry("Audio changes only on built-in speakers", 0),
  SettingsSearchEntry("Notch indicator", 0),
  SettingsSearchEntry("Dictation indicator", 0),
  SettingsSearchEntry("Launch at login", 0),
  SettingsSearchEntry("Hide menu bar icon", 0),
  SettingsSearchEntry("Command-Q closes Settings", 0),
  SettingsSearchEntry("Preload speech model", 0),
  SettingsSearchEntry("Release models when idle", 0),
  SettingsSearchEntry("Follow system", 0),
  SettingsSearchEntry("Light", 0),
  SettingsSearchEntry("Dark", 0),
  SettingsSearchEntry("Record left and right modifiers separately", 0),
  SettingsSearchEntry("Hold a toggle shortcut to stop on release", 0),
  SettingsSearchEntry("Double-tap the main modifier shortcut", 0),
  SettingsSearchEntry("Share shortcuts with the focused app", 0),
  SettingsSearchEntry("Caps Lock starts and stops dictation", 0),
  SettingsSearchEntry("Middle button", 0),
  SettingsSearchEntry("Button 4", 0),
  SettingsSearchEntry("Button 5", 0),
  SettingsSearchEntry("Leave unchanged", 0),
  SettingsSearchEntry("Lower volume", 0),
  SettingsSearchEntry("Mute", 0),
  SettingsSearchEntry("Whisper size", 1),
  SettingsSearchEntry("Filter speech models", 1),
  SettingsSearchEntry("Catalog or imported model", 1),
  SettingsSearchEntry("Unload models", 1),
  SettingsSearchEntry(
    "Release speech and cleanup models. The files stay available for next time.",
    1,
  ),
  SettingsSearchEntry("Dictation mode", 2),
  SettingsSearchEntry("Language", 2),
  SettingsSearchEntry(
    "Used by models that accept language hints. Single-language models use their own language.",
    2,
  ),
  SettingsSearchEntry("Paste last dictation", 2),
  SettingsSearchEntry("Insert the last transcript into the focused app.", 2),
  SettingsSearchEntry("Silence duration", 2),
  SettingsSearchEntry("Silence threshold", 2),
  SettingsSearchEntry("Maximum recording", 2),
  SettingsSearchEntry("Grammar cleanup", 2),
  SettingsSearchEntry("Clipboard fallback notice", 2),
  SettingsSearchEntry("Terminal paste shortcut", 2),
  SettingsSearchEntry("Restore clipboard after paste", 2),
  SettingsSearchEntry("Stop after silence", 2),
  SettingsSearchEntry("Recognition vocabulary", 3),
  SettingsSearchEntry("Vocabulary replacements", 3),
  SettingsSearchEntry(
    "One replacement per line: what was heard = what should be inserted. Matches whole words, ignoring case.",
    3,
  ),
  SettingsSearchEntry("Replacements", 3),
  SettingsSearchEntry("Keep history", 4),
  SettingsSearchEntry(
    "Expired entries are removed at launch and after dictation. Up to 100 entries.",
    4,
  ),
  SettingsSearchEntry("Search transcripts", 4),
  SettingsSearchEntry("Keep recordings", 4),
  SettingsSearchEntry("Save dictation history", 4),
  SettingsSearchEntry("Project model storage", 5),
  SettingsSearchEntry("Remove downloaded models & caches", 5),
  SettingsSearchEntry(
    "Unloads models first. The next dictation will download the selected model again.",
    5,
  ),
  SettingsSearchEntry("Access token", 5),
  SettingsSearchEntry(
    "Only needed for gated models. Stored in macOS Keychain; sent only to Hugging Face model downloads.",
    5,
  ),
  SettingsSearchEntry("Hugging Face token", 5),
  SettingsSearchEntry("Smart Commands", 12),
  SettingsSearchEntry(
    "Select text in any app, then press \u2303 \u21e7 C. Rewrite professionally, summarize, translate to Hindi, or enter your own instruction.",
    6,
  ),
  SettingsSearchEntry("Keyboard navigation", 6),
  SettingsSearchEntry(
    "Use arrow keys to choose a command, Return to run it, and Escape to close.",
    6,
  ),
  SettingsSearchEntry("Moonshine Tiny INT8", 6),
  SettingsSearchEntry(
    "Available under Speech models. An English CPU option with a small download. Compare accuracy with Whisper on your own microphone.",
    6,
  ),
  SettingsSearchEntry("Newer candidates", 6),
  SettingsSearchEntry(
    "The full GGUF catalog includes Parakeet variants, Orukeet, Granite Speech 5.0, Qwen, SenseVoice, Cohere and Moonshine Streaming Tiny. All selected-model downloads remain inside this project.",
    6,
  ),
  SettingsSearchEntry("Local API and CLI", 13),
  SettingsSearchEntry("Spoken punctuation and symbols", 2),
  SettingsSearchEntry("Spoken new lines and paragraphs", 2),
  SettingsSearchEntry("Remove English filler words", 2),
  SettingsSearchEntry("Shorten long pauses before transcription", 2),
  SettingsSearchEntry("Add a space after existing words", 2),
  SettingsSearchEntry("Show live transcript beside the indicator", 2),
  SettingsSearchEntry("Pause browser media while dictating", 2),
  SettingsSearchEntry("Check for updates automatically", 10),
  SettingsSearchEntry("Download updates automatically", 10),
  SettingsSearchEntry("Install updates when idle", 10),
  SettingsSearchEntry("Meeting title", 7),
  SettingsSearchEntry("Microphone", 7),
  SettingsSearchEntry("System audio", 7),
  SettingsSearchEntry("Echo cancellation", 7),
  SettingsSearchEntry("Use macOS voice processing on the microphone track.", 7),
  SettingsSearchEntry("Meeting names and summaries", 7),
  SettingsSearchEntry("Identify remote speakers", 7),
  SettingsSearchEntry(
    "Downloads segmentation and speaker embedding models into this project when used. Speaker numbers are anonymous, not identities.",
    7,
  ),
  SettingsSearchEntry("Move old meetings to Trash", 7),
  SettingsSearchEntry("Expire audio after transcription", 7),
  SettingsSearchEntry("Keep transcripts and notes.", 7),
  SettingsSearchEntry("Rename meeting", 7),
  SettingsSearchEntry("Screen replay buffer", 9),
  SettingsSearchEntry(
    "Continuously capture the main screen locally while enabled. Saves the latest 15 seconds, without audio.",
    9,
  ),
  SettingsSearchEntry("Annotation text", 9),
  SettingsSearchEntry("Capture notes", 9),
  SettingsSearchEntry("Current state", 11),
  SettingsSearchEntry("Project storage", 11),
  SettingsSearchEntry("Target application bundle ID", 11),
  SettingsSearchEntry("Pipeline test text", 11),
  SettingsSearchEntry("Second dictation shortcut", 0),
  SettingsSearchEntry("Additional dictation shortcuts", 0),
  SettingsSearchEntry("Process focused text", 0),
  SettingsSearchEntry("Dictate to terminal", 0),
  SettingsSearchEntry("Save screen replay", 0),
  SettingsSearchEntry("Model benchmark details", 1),
  SettingsSearchEntry("Language filter", 1),
  SettingsSearchEntry("Downloaded models", 1),
  SettingsSearchEntry("Try output", 2),
  SettingsSearchEntry("Fix this", 2),
  SettingsSearchEntry("History recording playback", 4),
  SettingsSearchEntry("Retranscribe history", 4),
  SettingsSearchEntry("Screen replay", 9),
];
List<SettingsSearchEntry> searchSettings(String query) {
  final terms = query.toLowerCase().trim().split(RegExp(r'\s+'));
  if (terms.every((t) => t.isEmpty)) {
    return [];
  }
  return settingsSearchEntries
      .where(
        (entry) => terms.every(
          (term) =>
              '${entry.label} ${tr(entry.label)}'.toLowerCase().contains(term),
        ),
      )
      .toList();
}
