/// Speech-to-text backend selection.
enum SttEngine {
  /// Whisper.cpp — 75–466 MB weight files; runtime RAM depends on model and clip.
  whisper,

  /// Gemma 4 E2B multimodal — faster on GPU, needs ~16 GB RAM recommended.
  gemma,

  /// NVIDIA Nemotron-3.5-ASR-Streaming-0.6b — extremely fast CPU/GPU streaming.
  nemotron,

  /// Quantized English Moonshine Tiny, clip-based CPU recognition.
  moonshine,
  gguf,
}

extension SttEngineX on SttEngine {
  static SttEngine fromIndex(int index) {
    switch (index) {
      case 1:
        return SttEngine.gemma;
      case 2:
        return SttEngine.nemotron;
      case 3:
        return SttEngine.moonshine;
      case 4:
        return SttEngine.gguf;
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
      case SttEngine.moonshine:
        return 3;
      case SttEngine.gguf:
        return 4;
    }
  }
}
