import 'package:flutter/material.dart';
import '../app/dictation_orchestrator.dart';
import 'dictation_indicator.dart';
import 'dictation_state.dart';

class NotificationOverlay extends StatelessWidget {
  final DictationOrchestrator orchestrator;
  const NotificationOverlay({super.key, required this.orchestrator});
  @override
  Widget build(BuildContext context) {
    if (orchestrator.state == DictationState.idle &&
        !orchestrator.isPreparing) {
      return const SizedBox.shrink();
    }
    return DictationIndicator(
      label: orchestrator.isPreparing
          ? 'Preparing speech model'
          : orchestrator.errorMessage ??
              (orchestrator.state == DictationState.recording
                  ? 'Listening'
                  : orchestrator.state.label),
      hint: orchestrator.isPreparing
          ? 'Microphone is not recording'
          : orchestrator.state == DictationState.recording
              ? orchestrator.recordingHint
              : null,
      preparing: orchestrator.isPreparing,
      atTop: orchestrator.indicatorAtTop,
      level: orchestrator.audioLevel,
      transcript: orchestrator.liveTranscript,
      recording: orchestrator.state == DictationState.recording,
      error: orchestrator.state == DictationState.error,
      onStop: () {
        if (orchestrator.isPreparing) {
          orchestrator.cancelPreparation();
        } else if (orchestrator.state == DictationState.error) {
          orchestrator.dismissFeedback();
        } else {
          orchestrator.toggle();
        }
      },
    );
  }
}
