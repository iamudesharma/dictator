import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

/// A compact preview of the native, click-through 104×30 macOS panel.
/// Production uses DictationIndicatorPanel, never a Flutter settings window.
class DictationIndicator extends StatelessWidget {
  final String label;
  final String? transcript, hint;
  final bool recording, error, preparing, atTop;
  final double level;
  final VoidCallback? onStop;
  const DictationIndicator(
      {super.key,
      required this.label,
      this.transcript,
      this.hint,
      this.recording = false,
      this.error = false,
      this.preparing = false,
      this.atTop = true,
      this.level = 0,
      this.onStop});

  @override
  Widget build(BuildContext context) => Align(
        alignment: atTop ? Alignment.topCenter : Alignment.bottomCenter,
        child: Padding(
            padding: const EdgeInsets.all(8),
            child: Semantics(
                label: '$label. ${hint ?? ''}',
                child: Tooltip(
                    message: label,
                    child: Container(
                      key: const ValueKey('dictation-pill'),
                      width: error ? 328 : 104,
                      height: error ? 64 : 30,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                          color: const Color(0xF513171B),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.white24)),
                      child: error
                          ? Center(
                              child: Text(label,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11, color: Color(0xFFFFB5AD))))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                  const Text('⌥',
                                      style: TextStyle(
                                          fontSize: 13, color: Colors.white70)),
                                  if (recording)
                                    VoiceLevelBars(level: level)
                                  else
                                    const SizedBox(
                                        width: 25,
                                        height: 10,
                                        child: LinearProgressIndicator(
                                            minHeight: 2,
                                            color: Color(0xFF91DED9),
                                            backgroundColor:
                                                Colors.transparent)),
                                  const SizedBox(width: 2),
                                ]),
                    )))),
      );
}

class VoiceLevelBars extends StatelessWidget {
  final double level;
  const VoiceLevelBars({super.key, required this.level});
  @override
  Widget build(BuildContext context) => Semantics(
      label: 'Microphone level',
      value: '${(level.clamp(0, 1) * 100).round()}%',
      child: SizedBox(
          width: 35,
          height: 22,
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (final weight in [0.45, 0.8, 1.0, 0.7, 0.4])
              AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 130),
                  width: 3,
                  height: 4 + 17 * weight * level.clamp(0, 1),
                  decoration: BoxDecoration(
                      color: const Color(0xFF91DED9),
                      borderRadius: BorderRadius.circular(2)))
          ])));
}

@Preview(name: 'Compact listening • native panel preview', size: Size(240, 80))
Widget dictationIndicatorPreview() => const MaterialApp(
    home: Scaffold(
        backgroundColor: Colors.transparent,
        body: DictationIndicator(
            label: 'Listening',
            hint: 'Release shortcut to finish',
            recording: true,
            level: 0.65)));

@Preview(name: 'Compact preparation', size: Size(240, 80))
Widget preparingIndicatorPreview() => const MaterialApp(
    home: Scaffold(
        backgroundColor: Colors.transparent,
        body: DictationIndicator(
            label: 'Preparing speech model', preparing: true)));
