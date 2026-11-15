#!/usr/bin/env python3
"""Import MIT-licensed UI strings from the pinned Hex v3.4.0 source tree.
Usage: python3 tool/import_hex_localizations.py /path/to/hex
App-specific translations are maintained separately in tool/l10n/strings.tsv.
"""
import json
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]) / 'src/desktop'
string = r'"(?:\\.|[^"\\])*"'
def decode(value):
    value = re.sub(r'\\u\{([0-9a-fA-F]+)\}', lambda m: chr(int(m[1], 16)), value)
    return json.loads(value)
def brand(value):
    return re.sub(r'\bHex\b', 'AuraScribe', value)
langs = ['pl', 'zh', 'ja', 'de', 'es', 'uk']
tables = {code: {} for code in langs + ['pt', 'fr', 'ru', 'zh-Hant']}
for name in ['i18n.rs', 'i18n/meetings.rs', 'i18n/labs.rs', 'i18n/failures.rs', 'i18n/onboarding.rs']:
    source = (root / name).read_text()
    for match in re.finditer(r'\(\s*('+string+r')\s*,\s*\[\s*((?:'+string+r'\s*,?\s*){6})\]\s*\)', source):
        key = brand(decode(match[1]))
        values = re.findall(string, match[2])
        for code, value in zip(langs, values): tables[code][key] = brand(decode(value))
for code, filename in [('pt','portuguese'), ('fr','french'), ('ru','russian')]:
    source = (root / f'i18n/{filename}.rs').read_text()
    for match in re.finditer(r'\(\s*('+string+r')\s*,\s*('+string+r')\s*\)', source):
        tables[code][brand(decode(match[1]))] = brand(decode(match[2]))
source = (root / 'i18n/traditional_chinese.rs').read_text()
phrases = [(decode(a), decode(b)) for a,b in re.findall(r'\(\s*('+string+r')\s*,\s*('+string+r')\s*\)', source)]
character_section = source.split('const CHARACTERS:')[1].split('];')[0]
characters = dict(token for line in re.findall(string, character_section)
                  for token in decode(line).split() if len(token) == 2)
phrases.sort(key=lambda pair: -len(pair[0]))
def traditional(value):
    result = ''; i = 0
    while i < len(value):
        pair = next((p for p in phrases if value.startswith(p[0], i)), None)
        if pair: result += pair[1]; i += len(pair[0])
        else: result += characters.get(value[i], value[i]); i += 1
    return result
for key, value in tables['zh'].items(): tables['zh-Hant'][key] = traditional(value)
output = Path(__file__).resolve().parent.parent / 'tool/l10n/hex.json'
output.write_text(json.dumps(tables, ensure_ascii=False, indent=2) + '\n')
print({code: len(table) for code, table in tables.items()})
