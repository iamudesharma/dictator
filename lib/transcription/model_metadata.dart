// Catalog capabilities and published benchmark facts from Hex v3.4.0 (MIT).
// These are upstream measurements, not AuraScribe measurements. Unknown fields stay unknown.
import 'dart:convert';

class SpeechModelMetadata {
  final List<String> languages;
  final bool acceptsHint, detectsLanguage;
  final Map<String, dynamic>? benchmark;
  SpeechModelMetadata(Map<String, dynamic> data)
      : languages = (data['languages'] as List).cast<String>(),
        acceptsHint = data['acceptsHint'] == true,
        detectsLanguage = data['detectsLanguage'] == true,
        benchmark = (data['benchmark'] as Map?)?.cast<String, dynamic>();
  bool supports(String language) => language == 'auto'
      ? detectsLanguage
      : languages.contains('*') || languages.contains(language);
  String? runtimeLanguage(String language) {
    if (!acceptsHint) return null;
    if (languages.length == 1 && languages.single != '*') {
      return languages.single;
    }
    return language == 'auto' ? null : language;
  }
}

final speechModelMetadata = (jsonDecode(_catalog) as Map).map((key, value) =>
    MapEntry(key as String,
        SpeechModelMetadata(Map<String, dynamic>.from(value as Map))));
const _catalog = r'''
{
  "parakeet_unified_english": {
    "languages": [
      "en"
    ],
    "acceptsHint": true,
    "detectsLanguage": false,
    "benchmark": {
      "metric": "WER",
      "value": 1.6,
      "language": "en"
    }
  },
  "parakeet_v2": {
    "languages": [
      "en"
    ],
    "acceptsHint": true,
    "detectsLanguage": false,
    "benchmark": {
      "metric": "WER",
      "value": 1.69,
      "language": "en"
    }
  },
  "parakeet_v3": {
    "languages": [
      "bg",
      "hr",
      "cs",
      "da",
      "nl",
      "en",
      "et",
      "fi",
      "fr",
      "de",
      "el",
      "hu",
      "it",
      "lv",
      "lt",
      "mt",
      "pl",
      "pt",
      "ro",
      "ru",
      "sk",
      "sl",
      "es",
      "sv",
      "uk"
    ],
    "acceptsHint": false,
    "detectsLanguage": true,
    "benchmark": {
      "metric": "WER",
      "value": 1.94,
      "language": "en"
    }
  },
  "orukeet": {
    "languages": [
      "bg",
      "hr",
      "cs",
      "da",
      "nl",
      "en",
      "et",
      "fi",
      "fr",
      "de",
      "el",
      "hu",
      "it",
      "lv",
      "lt",
      "mt",
      "pl",
      "pt",
      "ro",
      "ru",
      "sk",
      "sl",
      "es",
      "sv",
      "uk"
    ],
    "acceptsHint": false,
    "detectsLanguage": true,
    "benchmark": {
      "metric": "WER",
      "value": 1.86,
      "language": "en",
      "dataset": "LibriSpeech test-clean",
      "source": "transcribe.cpp's published conversion benchmark",
      "source_revision": "37273409",
      "utterances": 2620,
      "batch_size": 8,
      "timestamps": false,
      "hardware": "CUDA"
    }
  },
  "whisper": {
    "languages": [
      "*"
    ],
    "acceptsHint": true,
    "detectsLanguage": true,
    "benchmark": {
      "metric": "WER",
      "value": 2.01,
      "language": "en"
    }
  },
  "qwen": {
    "languages": [
      "zh",
      "en",
      "yue",
      "ar",
      "de",
      "fr",
      "es",
      "pt",
      "id",
      "it",
      "ko",
      "ru",
      "th",
      "vi",
      "ja",
      "tr",
      "hi",
      "ms",
      "nl",
      "sv",
      "da",
      "fi",
      "pl",
      "cs",
      "fil",
      "fa",
      "el",
      "ro",
      "hu",
      "mk"
    ],
    "acceptsHint": true,
    "detectsLanguage": true,
    "benchmark": {
      "metric": "CER",
      "value": 7.57,
      "language": "zh",
      "dataset": "FLEURS test",
      "source": "transcribe.cpp benchmark record, legacy-published",
      "source_revision": "7045d1c",
      "utterances": 945,
      "batch_size": 8,
      "timestamps": false,
      "hardware": null
    }
  },
  "qwencleo": {
    "languages": [
      "ar"
    ],
    "acceptsHint": true,
    "detectsLanguage": false,
    "benchmark": {
      "metric": "WER",
      "value": 19.85,
      "language": "ar",
      "dataset": "Author's Egyptian Arabic test",
      "source": "The model author's own evaluation",
      "utterances": 3699
    }
  },
  "ivrit_whisper": {
    "languages": [
      "he"
    ],
    "acceptsHint": true,
    "detectsLanguage": false,
    "benchmark": {
      "metric": "WER",
      "value": 18.45,
      "language": "he",
      "dataset": "FLEURS test",
      "source": "Hex's run of the transcribe.cpp WER harness",
      "source_revision": "7045d1c",
      "utterances": 792,
      "batch_size": 1,
      "timestamps": false,
      "hardware": "Radeon 8060S (Vulkan)"
    }
  },
  "sensevoice": {
    "languages": [
      "zh",
      "yue",
      "en",
      "ja",
      "ko"
    ],
    "acceptsHint": true,
    "detectsLanguage": true,
    "benchmark": {
      "metric": "CER",
      "value": 10.12,
      "language": "zh",
      "dataset": "FLEURS test",
      "source": "transcribe.cpp benchmark record, legacy-published",
      "source_revision": "7045d1c",
      "utterances": 945,
      "batch_size": 8,
      "timestamps": false,
      "hardware": null
    }
  },
  "cohere": {
    "languages": [
      "en",
      "fr",
      "de",
      "es",
      "it",
      "pt",
      "nl",
      "pl",
      "el",
      "ar",
      "ja",
      "zh",
      "vi",
      "ko"
    ],
    "acceptsHint": true,
    "detectsLanguage": false,
    "benchmark": {
      "metric": "WER",
      "value": 1.27,
      "language": "en"
    }
  },
  "underdog_bark_3_pro": {
    "languages": [
      "en"
    ],
    "acceptsHint": false,
    "detectsLanguage": false,
    "benchmark": {
      "metric": "WER",
      "value": 1.38,
      "language": "en"
    }
  },
  "underdog_bark_3_clean": {
    "languages": [
      "en"
    ],
    "acceptsHint": false,
    "detectsLanguage": false,
    "benchmark": {
      "metric": "WER",
      "value": 1.71,
      "language": "en"
    }
  },
  "parakeet_ultra": {
    "languages": [
      "bg",
      "hr",
      "cs",
      "da",
      "nl",
      "en",
      "et",
      "fi",
      "fr",
      "de",
      "el",
      "hu",
      "it",
      "lv",
      "lt",
      "mt",
      "pl",
      "pt",
      "ro",
      "ru",
      "sk",
      "sl",
      "es",
      "sv",
      "uk"
    ],
    "acceptsHint": false,
    "detectsLanguage": true,
    "benchmark": {
      "metric": "WER",
      "value": 1.8,
      "language": "en",
      "dataset": "LibriSpeech test-clean",
      "source": "transcribe.cpp's published conversion benchmark",
      "source_revision": "021aa17d",
      "utterances": 2620,
      "batch_size": 8,
      "timestamps": false,
      "hardware": "CUDA"
    }
  },
  "nemotron_3_5_asr": {
    "languages": [
      "en",
      "es",
      "fr",
      "de",
      "it",
      "pt",
      "nl",
      "tr",
      "ru",
      "uk",
      "pl",
      "cs",
      "sk",
      "bg",
      "hr",
      "ro",
      "hu",
      "sv",
      "da",
      "fi",
      "et",
      "ar",
      "hi",
      "ja",
      "ko",
      "zh",
      "vi"
    ],
    "acceptsHint": true,
    "detectsLanguage": true,
    "benchmark": {
      "metric": "WER",
      "value": 3.05,
      "language": "en",
      "dataset": "LibriSpeech test-clean",
      "source": "Hex's run of the transcribe.cpp WER harness",
      "source_revision": "7045d1c",
      "utterances": 2620,
      "batch_size": 1,
      "timestamps": false,
      "hardware": "Radeon 8060S (Vulkan)"
    }
  },
  "gigaam_v3_e2e_rnnt": {
    "languages": [
      "ru"
    ],
    "acceptsHint": false,
    "detectsLanguage": false,
    "benchmark": {
      "metric": "WER",
      "value": 5.37,
      "language": "ru",
      "dataset": "FLEURS test",
      "source": "Hex's run of the transcribe.cpp WER harness",
      "source_revision": "7045d1c",
      "utterances": 775,
      "batch_size": 1,
      "timestamps": false,
      "hardware": "Radeon 8060S (Vulkan)"
    }
  },
  "nb_whisper_medium": {
    "languages": [
      "no"
    ],
    "acceptsHint": true,
    "detectsLanguage": false,
    "benchmark": {
      "metric": "WER",
      "value": 6.68,
      "language": "no",
      "dataset": "FLEURS test",
      "source": "Hex's run of the transcribe.cpp WER harness",
      "source_revision": "7045d1c",
      "utterances": 357,
      "batch_size": 1,
      "timestamps": false,
      "hardware": "Radeon 8060S (Vulkan)"
    }
  },
  "granite_speech_5": {
    "languages": [
      "en",
      "fr",
      "de",
      "es",
      "pt",
      "it",
      "ja"
    ],
    "acceptsHint": false,
    "detectsLanguage": true,
    "benchmark": {
      "metric": "WER",
      "value": 4.77,
      "language": "en",
      "dataset": "FLEURS test",
      "source": "Hex's run of the transcribe.cpp WER harness",
      "source_revision": "7045d1c",
      "utterances": 647,
      "batch_size": 1,
      "timestamps": false,
      "hardware": "Radeon 8060S (Vulkan)"
    }
  },
  "moonshine_streaming_tiny": {
    "languages": [
      "en"
    ],
    "acceptsHint": false,
    "detectsLanguage": false
  }
}
''';
const speechLanguages = <String, String>{
  "en": "English",
  "zh": "Mandarin Chinese",
  "yue": "Cantonese",
  "ja": "Japanese",
  "ko": "Korean",
  "es": "Spanish",
  "fr": "French",
  "de": "German",
  "pt": "Portuguese",
  "it": "Italian",
  "ar": "Arabic",
  "hi": "Hindi",
  "bn": "Bangla",
  "vi": "Vietnamese",
  "ru": "Russian",
  "uk": "Ukrainian",
  "nl": "Dutch",
  "pl": "Polish",
  "tr": "Turkish",
  "sv": "Swedish",
  "da": "Danish",
  "no": "Norwegian",
  "fi": "Finnish",
  "cs": "Czech",
  "el": "Greek",
  "ro": "Romanian",
  "hu": "Hungarian",
  "id": "Indonesian",
  "ms": "Malay",
  "th": "Thai",
  "fa": "Persian",
  "he": "Hebrew",
  "bg": "Bulgarian",
  "hr": "Croatian",
  "et": "Estonian",
  "lv": "Latvian",
  "lt": "Lithuanian",
  "mt": "Maltese",
  "sk": "Slovak",
  "sl": "Slovenian",
  "mk": "Macedonian",
  "fil": "Filipino",
  "nn": "Norwegian Nynorsk",
  "ca": "Catalan",
  "ta": "Tamil",
  "ur": "Urdu",
  "la": "Latin",
  "mi": "Maori",
  "ml": "Malayalam",
  "cy": "Welsh",
  "te": "Telugu",
  "sr": "Serbian",
  "az": "Azerbaijani",
  "kn": "Kannada",
  "br": "Breton",
  "eu": "Basque",
  "is": "Icelandic",
  "hy": "Armenian",
  "ne": "Nepali",
  "mn": "Mongolian",
  "bs": "Bosnian",
  "kk": "Kazakh",
  "sq": "Albanian",
  "sw": "Swahili",
  "gl": "Galician",
  "mr": "Marathi",
  "pa": "Punjabi",
  "si": "Sinhala",
  "km": "Khmer",
  "sn": "Shona",
  "yo": "Yoruba",
  "so": "Somali",
  "af": "Afrikaans",
  "oc": "Occitan",
  "ka": "Georgian",
  "be": "Belarusian",
  "tg": "Tajik",
  "sd": "Sindhi",
  "gu": "Gujarati",
  "am": "Amharic",
  "yi": "Yiddish",
  "lo": "Lao",
  "uz": "Uzbek",
  "fo": "Faroese",
  "ht": "Haitian Creole",
  "ps": "Pashto",
  "tk": "Turkmen",
  "sa": "Sanskrit",
  "lb": "Luxembourgish",
  "my": "Burmese",
  "bo": "Tibetan",
  "tl": "Tagalog",
  "mg": "Malagasy",
  "as": "Assamese",
  "tt": "Tatar",
  "haw": "Hawaiian",
  "ln": "Lingala",
  "ha": "Hausa",
  "ba": "Bashkir",
  "jw": "Javanese",
  "su": "Sundanese",
};

const nemotronLocales = <String, String>{
  "en": "en-US",
  "es": "es-ES",
  "fr": "fr-FR",
  "de": "de-DE",
  "it": "it-IT",
  "pt": "pt-BR",
  "nl": "nl-NL",
  "tr": "tr-TR",
  "ru": "ru-RU",
  "uk": "uk-UA",
  "pl": "pl-PL",
  "cs": "cs-CZ",
  "sk": "sk-SK",
  "bg": "bg-BG",
  "hr": "hr-HR",
  "ro": "ro-RO",
  "hu": "hu-HU",
  "sv": "sv-SE",
  "da": "da-DK",
  "fi": "fi-FI",
  "et": "et-EE",
  "ar": "ar-AR",
  "hi": "hi-IN",
  "ja": "ja-JP",
  "ko": "ko-KR",
  "zh": "zh-CN",
  "vi": "vi-VN"
};
