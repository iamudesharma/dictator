/// Strips common LLM preamble/meta replies so only usable text is inserted.
class LlmOutputSanitizer {
  LlmOutputSanitizer._();

  static const _noChangePhrases = [
    'already correct',
    'already grammatically correct',
    'grammar is correct',
    'grammar is already',
    'no changes needed',
    'no changes required',
    'no correction',
    'no corrections',
    'nothing to change',
    'text is fine',
    'looks good as is',
    'does not need',
    "doesn't need",
  ];

  static final _preamblePattern = RegExp(
    r'^(?:'
    r"here(?:'s| is)(?: the)?(?: a)?\s+"
    r'|below is(?: the)?\s+'
    r'|the following is(?: the)?\s+'
    r"|i(?: have|'ve)?\s+(?:summarized|rewritten|translated)\s+"
    r'|key points\s*:\s*'
    r'|bullet points\s*:\s*'
    r'|summary\s*:\s*'
    r'|summarized(?:\s+text)?\s*:\s*'
    r'|rewritten(?:\s+text)?\s*:\s*'
    r'|translation\s*:\s*'
    r'|output\s*:\s*'
    r'|result\s*:\s*'
    r'|answer\s*:\s*'
    r')+',
    caseSensitive: false,
  );

  /// Cleans [raw] model output. For grammar mode, returns [originalText] when
  /// the model only produced a meta "no changes" message.
  static String clean(
    String raw, {
    required String originalText,
    bool grammarMode = false,
  }) {
    var out = raw.trim();
    if (out.isEmpty) return originalText;

    out = _stripCodeFences(out);
    out = _stripWrappingQuotes(out);
    out = _stripPreamble(out);
    out = _stripTrailingMeta(out);

    if (grammarMode && _isNoChangeMetaReply(out, originalText)) {
      return originalText;
    }

    if (out.isEmpty) return originalText;
    return out;
  }

  static String _stripCodeFences(String text) {
    final fence = RegExp(
      r'^```(?:\w+)?\s*\n?([\s\S]*?)\n?```\s*$',
      multiLine: true,
    );
    final match = fence.firstMatch(text.trim());
    if (match != null) return match.group(1)!.trim();
    return text;
  }

  static String _stripWrappingQuotes(String text) {
    if (text.length >= 2) {
      if ((text.startsWith('"') && text.endsWith('"')) ||
          (text.startsWith("'") && text.endsWith("'"))) {
        return text.substring(1, text.length - 1).trim();
      }
    }
    return text;
  }

  static String _stripPreamble(String text) {
    var out = text;
    for (var i = 0; i < 3; i++) {
      final next = out.replaceFirst(_preamblePattern, '').trim();
      if (next == out) break;
      out = next;
    }
    return out;
  }

  static final _trailingMetaPattern = RegExp(
    r'\n\s*(?:'
    r'let me know\b.*'
    r'|hope this helps\b.*'
    r'|if you (?:need|want)\b.*'
    r'|feel free to\b.*'
    r')\s*$',
    caseSensitive: false,
    dotAll: true,
  );

  static String _stripTrailingMeta(String text) {
    return text.replaceFirst(_trailingMetaPattern, '').trim();
  }

  static bool _isNoChangeMetaReply(String output, String originalText) {
    final lower = output.toLowerCase().trim();
    if (lower.isEmpty) return true;

    for (final phrase in _noChangePhrases) {
      if (lower.contains(phrase)) return true;
    }

    // Very short reply that is not a substring of reasonable correction work.
    if (output.length < originalText.length * 0.4 &&
        output.length < 80 &&
        !lower.contains('\n') &&
        RegExp(r'^(the |this |your )?(text|grammar|sentence|paragraph)\b',
                caseSensitive: false)
            .hasMatch(lower)) {
      return true;
    }

    return false;
  }
}
