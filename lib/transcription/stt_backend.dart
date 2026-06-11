/// Common contract for STT backends (Whisper / Gemma).
///
/// Both backends are constructed lazily and held only for the active engine,
/// so the inactive engine's heavy resources (Whisper model, Gemma 2.4 GB
/// install + ~16 GB RAM) are not allocated until the user actually picks it.
abstract class SttBackend {
  bool get isLoaded;
  bool get isLoading;
  String get modelLabel;
  String get statusMessage => '';

  /// Idempotent load. Returns `null` on success, or an error string.
  Future<String?> load();

  /// Transcribe the WAV at [audioPath] and return plain text.
  Future<String> transcribe(String audioPath);

  /// Release native resources. Safe to call multiple times.
  Future<void> dispose();
}
