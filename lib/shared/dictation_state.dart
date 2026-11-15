import '../l10n/app_localizations.dart';

enum DictationState {
  idle,
  recording,
  transcribing,
  grammarCleanup,
  inserting,
  error,
}

extension DictationStateX on DictationState {
  bool get isActive =>
      this != DictationState.idle && this != DictationState.error;

  String get label {
    switch (this) {
      case DictationState.idle:
        return tr('Idle');
      case DictationState.recording:
        return tr('Recording…');
      case DictationState.transcribing:
        return tr('Transcribing…');
      case DictationState.grammarCleanup:
        return tr('Cleaning up…');
      case DictationState.inserting:
        return tr('Inserting…');
      case DictationState.error:
        return tr('Error');
    }
  }
}
