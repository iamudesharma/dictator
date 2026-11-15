import '../l10n/app_localizations.dart';

enum DictationMode {
  liveTyping,
  enhancedAccuracy,
}

extension DictationModeX on DictationMode {
  String get label {
    switch (this) {
      case DictationMode.liveTyping:
        return tr('Live Typing');
      case DictationMode.enhancedAccuracy:
        return tr('Enhanced Accuracy');
    }
  }
}
