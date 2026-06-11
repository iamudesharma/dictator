import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import '../transcription/transcription_service.dart';
import 'grammar_model_service.dart';
import 'llm_output_sanitizer.dart';

enum SmartCommandType {
  rewriteProfessionally,
  translateToHindi,
  summarize,
  custom,
}

extension SmartCommandTypeX on SmartCommandType {
  String get label {
    switch (this) {
      case SmartCommandType.rewriteProfessionally:
        return 'Rewrite Professionally';
      case SmartCommandType.translateToHindi:
        return 'Translate to Hindi';
      case SmartCommandType.summarize:
        return 'Summarize Text';
      case SmartCommandType.custom:
        return 'Custom Command...';
    }
  }
}

class SmartCommandService {
  final GrammarModelService Function() _grammarModelFactory;
  final TranscriptionService _transcription;

  GrammarModelService? _cachedModelService;

  SmartCommandService(
    this._grammarModelFactory,
    this._transcription,
  );

  Future<String> execute({
    required SmartCommandType type,
    required String text,
    String? customPrompt,
  }) async {
    debugPrint('[Dictator][SmartCommand] execute() entry: type = $type, text length = ${text.length}');
    if (text.trim().isEmpty) {
      debugPrint('[Dictator][SmartCommand] Text is empty, returning early');
      return text;
    }

    // Gemma STT → reuse multimodal model; Whisper / Nemotron → Gemma 3 270M.
    InferenceModel? model;
    try {
      final modelService = _cachedModelService ??= _grammarModelFactory();
      model = await modelService.resolveTextModel(
        sttSharedModel: _transcription.sharedGemmaModelForGrammar,
      );
    } catch (e, stack) {
      debugPrint('[Dictator][SmartCommand] Model load failed: $e\n$stack');
      return 'Error: Gemma model is unavailable ($e)';
    }

    if (model == null) {
      return 'Error: Gemma model not loaded';
    }

    const outputRules =
        'Reply with ONLY the final text to paste into a document. '
        'No introductions (e.g. "Here is the summary"). '
        'No labels (e.g. "Summary:", "Output:"). '
        'No explanations before or after. '
        'No markdown code fences. '
        'No quotes around the whole answer.';

    String systemPrompt;
    switch (type) {
      case SmartCommandType.rewriteProfessionally:
        systemPrompt =
            'Rewrite the text to be professional, clear, and grammatically correct. '
            'Keep the same meaning. $outputRules';
        break;
      case SmartCommandType.translateToHindi:
        systemPrompt =
            'Translate the text into natural Hindi. $outputRules';
        break;
      case SmartCommandType.summarize:
        systemPrompt =
            'Summarize the text concisely. Keep only the essential points. '
            'Output only the summary itself — sentences or bullet lines starting with "- ". '
            'Do not write "Here is the summary", "Key points:", or any other framing. '
            '$outputRules';
        break;
      case SmartCommandType.custom:
        systemPrompt =
            '${customPrompt ?? 'Transform the text as requested.'} $outputRules';
        break;
    }

    debugPrint('[Dictator][SmartCommand] Executing $type on ${text.length} chars…');

    final session = await model.createSession();
    try {
      await session.addQueryChunk(
        Message.text(text: '$systemPrompt\n\n$text'),
      );
      final result = await session.getResponse();
      final out = LlmOutputSanitizer.clean(result, originalText: text);
      debugPrint('[Dictator][SmartCommand] Completed → ${out.length} chars');
      return out.isNotEmpty ? out : 'No response from model';
    } catch (e) {
      debugPrint('[Dictator][SmartCommand] Execution error: $e');
      return 'Error executing command: $e';
    } finally {
      await session.close();
    }
  }
}
