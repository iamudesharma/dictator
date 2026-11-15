/// Timing supplied by a recognizer, never estimated by dividing text evenly.
class TranscriptSpan {
  final double start, end;
  final String text;
  const TranscriptSpan(this.start, this.end, this.text);
  Map<String, dynamic> toJson([double offset = 0]) => {
    'start': start + offset,
    'end': end + offset,
    'text': text,
  };
}

class TimedTranscript {
  final String text;
  final List<TranscriptSpan> segments, words;
  final bool skippedSilence;
  const TimedTranscript(
    this.text, {
    this.segments = const [],
    this.words = const [],
    this.skippedSilence = false,
  });

  /// Pinned transcribe.cpp CLI emits explicit sections with second-based times.
  static TimedTranscript fromRuntime(
    String text,
    String output,
    String requested,
  ) {
    final segments = <TranscriptSpan>[], words = <TranscriptSpan>[];
    List<TranscriptSpan>? rows;
    final pattern = RegExp(r'^\s*\[\s*([\d.]+) ->\s*([\d.]+)\] (.*)$');
    for (final line in output.split('\n')) {
      if (RegExp(r'^segments: \d+$').hasMatch(line)) {
        rows = segments;
        continue;
      }
      if (RegExp(r'^words: \d+$').hasMatch(line)) {
        rows = words;
        continue;
      }
      final match = pattern.firstMatch(line);
      if (match != null && rows != null) {
        final start = double.parse(match[1]!), end = double.parse(match[2]!);
        if (start.isFinite && end.isFinite && start >= 0 && end >= start) {
          rows.add(TranscriptSpan(start, end, match[3]!));
        }
      } else {
        rows = null;
      }
    }
    if (text.isNotEmpty &&
        (requested == 'word'
            ? words.isEmpty
            : requested == 'segment' && segments.isEmpty)) {
      throw UnsupportedError(
        'The selected model did not return $requested timestamps. Choose a model that supports them.',
      );
    }
    return TimedTranscript(text, segments: segments, words: words);
  }
}

abstract interface class TimedSttBackend {
  Future<TimedTranscript> transcribeTimed(
    String path, {
    required String timestamps,
  });
}

/// Optional bounded WAV access; times are relative to the requested slice.
abstract interface class SlicedSttBackend {
  Future<TimedTranscript> transcribeSlice(
    String path, {
    required int startSample,
    required int sampleCount,
    required String timestamps,
    required bool skipSilence,
  });
}
