enum DictationState {
  idle,
  recording,
  transcribing,
  grammarCleanup,
  inserting,
  error,
}

extension DictationStateX on DictationState {
  bool get isActive => this != DictationState.idle && this != DictationState.error;

  String get label {
    switch (this) {
      case DictationState.idle:
        return 'Idle';
      case DictationState.recording:
        return 'Recording…';
      case DictationState.transcribing:
        return 'Transcribing…';
      case DictationState.grammarCleanup:
        return 'Cleaning up…';
      case DictationState.inserting:
        return 'Inserting…';
      case DictationState.error:
        return 'Error';
    }
  }
}
