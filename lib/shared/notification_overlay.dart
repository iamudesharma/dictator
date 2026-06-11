import 'package:flutter/material.dart';
import '../shared/dictation_state.dart';
import 'dictation_mode.dart';
import '../app/dictation_orchestrator.dart';

/// Floating HUD overlay window that shows recording state and waveform animation.
/// This widget is shown as a small floating panel (not in the main window).
class NotificationOverlay extends StatefulWidget {
  final DictationOrchestrator orchestrator;

  const NotificationOverlay({super.key, required this.orchestrator});

  @override
  State<NotificationOverlay> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends State<NotificationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    widget.orchestrator.addListener(_onStateChange);
  }

  void _onStateChange() => setState(() {});

  @override
  void dispose() {
    widget.orchestrator.removeListener(_onStateChange);
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.orchestrator.state;
    final isError = state == DictationState.error;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: state == DictationState.idle
          ? const SizedBox.shrink(key: ValueKey('hidden'))
          : _buildHud(state, isError),
    );
  }

  Widget _buildHud(DictationState state, bool isError) {
    final liveText = widget.orchestrator.liveTranscript;
    final isRecording = state == DictationState.recording;
    final isLiveTyping = widget.orchestrator.dictationMode == DictationMode.liveTyping;

    if (isLiveTyping) {
      return Align(
        key: const ValueKey('hud_tiny'),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFFF3B30).withOpacity(0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF3B30).withOpacity(0.25),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isRecording)
                ScaleTransition(
                  scale: _pulseAnim,
                  child: const Icon(
                    Icons.mic_rounded,
                    color: Color(0xFFFF3B30),
                    size: 16,
                  ),
                )
              else
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(
                      isError ? const Color(0xFFFF3B30) : const Color(0xFF34C759),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                isError
                    ? 'Error'
                    : isRecording
                        ? 'Live'
                        : state == DictationState.transcribing
                            ? 'Done'
                            : 'Typing...',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Align(
      key: const ValueKey('hud'),
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isRecording && liveText.isNotEmpty) ...[
              Container(
                constraints: const BoxConstraints(maxWidth: 400),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF9B59F5).withOpacity(0.3),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: Text(
                  liveText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: _stateColor(state).withOpacity(0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _stateColor(state).withOpacity(0.25),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isRecording)
                    ScaleTransition(
                      scale: _pulseAnim,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B30),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF3B30).withOpacity(0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(_stateColor(state)),
                      ),
                    ),
                  const SizedBox(width: 10),
                  Text(
                    isError
                        ? (widget.orchestrator.errorMessage ?? 'Error')
                        : state.label,
                    style: TextStyle(
                      color: isError ? const Color(0xFFFF3B30) : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (widget.orchestrator.usedFallback && state == DictationState.idle)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        '(clipboard)',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  Color _stateColor(DictationState state) {
    switch (state) {
      case DictationState.recording:
        return const Color(0xFFFF3B30);
      case DictationState.transcribing:
        return const Color(0xFF9B59F5);
      case DictationState.grammarCleanup:
        return const Color(0xFF6E40C9);
      case DictationState.inserting:
        return const Color(0xFF34C759);
      case DictationState.error:
        return const Color(0xFFFF9F0A);
      default:
        return Colors.white;
    }
  }
}
