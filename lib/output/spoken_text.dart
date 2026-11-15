/// Deterministic English dictation transformations, explicitly enabled by users.
class SpokenText {
  static String apply(String text,
      {bool symbols = false,
      bool formatting = false,
      bool fillers = false,
      bool spacing = false,
      String language = 'en'}) {
    if (language == 'en' || language.startsWith('en-')) {
      final replacements = <String, String>{
        if (formatting) ...{
          'new paragraph': '\n\n',
          'new line': '\n',
          'bullet point': '\n• ',
          'open quote': '“',
          'close quote': '”'
        },
        if (symbols) ...{
          'question mark': '?',
          'exclamation mark': '!',
          'full stop': '.',
          'open parenthesis': '(',
          'close parenthesis': ')',
          'at sign': '@',
          'hash sign': '#',
          'hashtag': '#',
          'underscore': '_',
          'forward slash': '/',
          'backslash': r'\',
          'plus sign': '+',
          'equals sign': '=',
          'percent sign': '%',
          'ampersand': '&',
          'colon': ':',
          'semicolon': ';',
          'comma': ','
        },
      };
      for (final entry in replacements.entries) {
        text = text.replaceAll(
            RegExp('\\b${RegExp.escape(entry.key)}\\b', caseSensitive: false),
            entry.value);
      }
      if (fillers) {
        text = text.replaceAll(
            RegExp(r'(?<![\w-])(um+|uh+|erm+)(?![\w-])[, ]*',
                caseSensitive: false),
            '');
      }
    }
    if (symbols || formatting || fillers || spacing) {
      text = text.replaceAll(RegExp(r'[ \t]*\n[ \t]*'), '\n');
      text = text.replaceAllMapped(RegExp(r'([@_/#])\s+'), (m) => m[1]!);
      text = text.replaceAllMapped(RegExp(r'\s+([@_/])'), (m) => m[1]!);
      text = text.replaceAllMapped(RegExp(r'([“(])[ \t]+'), (m) => m[1]!);
      text = text.replaceAllMapped(RegExp(r'[ \t]+([”)])'), (m) => m[1]!);
      text = text
          .replaceAllMapped(RegExp(r'[ \t]+([,.!?;:])'), (m) => m[1]!)
          .replaceAllMapped(
              RegExp(r'([,.!?;:])(?=[A-Za-z])'), (m) => '${m[1]} ')
          .replaceAll(RegExp(r'[ \t]{2,}'), ' ');
    }
    return text.trim();
  }
}
