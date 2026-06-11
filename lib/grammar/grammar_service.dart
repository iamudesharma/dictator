import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import '../settings/settings_service.dart';
import 'grammar_model_service.dart';
import 'llm_output_sanitizer.dart';

/// Cleans up raw transcription text using an on-device Gemma prompt.
///
/// Uses Gemma 3 270M when STT is Whisper or Nemotron; reuses the Gemma 4 E2B
/// STT model when the user selected Gemma for audio.
class GrammarService {
  final SettingsService _settings;
  final GrammarModelService Function() _grammarModelFactory;

  /// Set from [TranscriptionService.sharedGemmaModelForGrammar] when STT is Gemma.
  InferenceModel? _sttSharedModel;

  GrammarModelService? _cachedGrammarModel;

  GrammarService(this._settings, GrammarModelService Function() grammarModelFactory)
      : _grammarModelFactory = grammarModelFactory;

  /// Convenience constructor that creates its own [GrammarModelService] on
  /// first use. Kept for callers that just want the simple flow.
  factory GrammarService.simple(SettingsService settings) =>
      GrammarService(settings, () => GrammarModelService(settings));

  void attachSttModel(InferenceModel? model) {
    _sttSharedModel = model;
  }

  Future<String> clean(String rawText) async {
    if (!_settings.grammarEnabled) {
      debugPrint('[AuraScribe][Grammar] skipped — disabled in settings');
      return rawText;
    }
    if (rawText.trim().isEmpty) {
      debugPrint('[AuraScribe][Grammar] skipped — empty input');
      return rawText;
    }
    if (rawText.trim().length < 24) {
      debugPrint('[AuraScribe][Grammar] skipped — short text (<24 chars)');
      return rawText;
    }

    InferenceModel? model;
    try {
      final grammarModel = _cachedGrammarModel ??= _grammarModelFactory();
      model = await grammarModel.resolveTextModel(sttSharedModel: _sttSharedModel);
    } catch (e) {
      debugPrint('[AuraScribe][Grammar] model unavailable: $e');
      return rawText;
    }

    if (model == null) return rawText;

    debugPrint('[AuraScribe][Grammar] cleaning ${rawText.length} chars…');

    const systemPrompt =
        'You fix dictation transcripts from Indian English speakers. '
        'Fix punctuation, capitalization, grammar, and spelling only when needed. '
        'Preserve meaning and tone. Do not add or remove ideas. '
        'If the text is already correct, return it EXACTLY as given — same words, same order. '
        'NEVER write comments like "grammar is already correct", "no changes needed", or "here is the corrected text". '
        'NEVER add labels, explanations, or quotes. '
        'Your entire reply must be ONLY the final text to paste — nothing before it, nothing after it.';

    final session = await model.createSession();

    try {
      await session.addQueryChunk(
        Message.text(text: '$systemPrompt\n\n$rawText'),
      );

      final result = await session.getResponse();
      final out = LlmOutputSanitizer.clean(
        result,
        originalText: rawText,
        grammarMode: true,
      );
      debugPrint('[AuraScribe][Grammar] done → ${out.length} chars');
      return out;
    } finally {
      await session.close();
    }
  }
}
