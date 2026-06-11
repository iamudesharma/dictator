enum DictationMode {
  liveTyping,
  enhancedAccuracy,
}

extension DictationModeX on DictationMode {
  String get label {
    switch (this) {
      case DictationMode.liveTyping:
        return 'Live Typing';
      case DictationMode.enhancedAccuracy:
        return 'Enhanced Accuracy';
    }
  }
}
