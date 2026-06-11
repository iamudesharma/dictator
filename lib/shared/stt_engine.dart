/// Speech-to-text backend selection.
enum SttEngine {
  /// Whisper.cpp — lower RAM (~75–500 MB), slower per phrase in debug.
  whisper,

  /// Gemma 4 E2B multimodal — faster on GPU, needs ~16 GB RAM recommended.
  gemma,

  /// NVIDIA Nemotron-3.5-ASR-Streaming-0.6b — extremely fast CPU/GPU streaming.
  nemotron,
}

extension SttEngineX on SttEngine {
  static SttEngine fromIndex(int index) {
    switch (index) {
      case 1:
        return SttEngine.gemma;
      case 2:
        return SttEngine.nemotron;
      default:
        return SttEngine.whisper;
    }
  }

  int get index {
    switch (this) {
      case SttEngine.whisper:
        return 0;
      case SttEngine.gemma:
        return 1;
      case SttEngine.nemotron:
        return 2;
    }
  }
}
