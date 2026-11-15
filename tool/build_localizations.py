#!/usr/bin/env python3
"""Build AuraScribe UI catalogs; no network services or runtime translation.
Author English-keyed rows in tool/l10n/strings.tsv (English plus nine translations, pipe separated).
Upstream aliases reuse MIT-licensed Hex translations only when meanings match.
"""
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
LANGS = ['pl', 'zh', 'ja', 'de', 'es', 'uk', 'pt', 'fr', 'ru']
base = json.loads((ROOT / 'tool/l10n/hex.json').read_text())
tables = {lang: {} for lang in LANGS + ['zh-Hant']}
for file in sorted((ROOT / 'tool/l10n').glob('*.tsv')):
    for line in file.read_text().splitlines():
        if not line or line.startswith('#'): continue
        cells = line.split('|')
        if len(cells) != 10: raise ValueError(f'{file.name}: expected 10 columns: {cells[0]} ({len(cells)})')
        key = cells[0].replace('\\n', '\n')
        for lang, value in zip(LANGS, cells[1:]): tables[lang][key] = value.replace('\\n', '\n')
# Keep the upstream conversion map checked in so rebuilding does not need Hex.
conversion = json.loads((ROOT / 'tool/l10n/traditional.json').read_text())
phrases = sorted(conversion['phrases'], key=lambda p: -len(p[0]))
def traditional(value):
    out = ''; i = 0
    while i < len(value):
        pair = next((p for p in phrases if value.startswith(p[0], i)), None)
        if pair: out += pair[1]; i += len(pair[0])
        else: out += conversion['characters'].get(value[i], value[i]); i += 1
    return out
for key, value in tables['zh'].items(): tables['zh-Hant'][key] = traditional(value)
aliases = json.loads((ROOT / 'tool/l10n/aliases.json').read_text())
for _ in range(3):
    for key, original in aliases.items():
        for lang, table in tables.items():
            value = table.get(original, base[lang].get(original))
            if value and key not in table: table[key] = value
for lang, table in tables.items():
    for number in range(1, 5):
        table[f'Additional dictation {number}'] = f"{table['Additional dictation shortcuts']} {number}"
# Case-only and trailing-ellipsis variants preserve the same meaning.
keys = json.loads((ROOT / 'tool/l10n/ui_keys.json').read_text())
def normalize(key): return key.strip(' .…').casefold()
for lang, table in tables.items():
    normalized = {normalize(k): v for k,v in {**base[lang], **table}.items()}
    for key in keys:
        if key not in table and key not in base[lang] and normalize(key) in normalized:
            table[key] = normalized[normalize(key)]
    for key, value in table.items():
        if sorted(re.findall(r'\{[^{}]*\}', key)) != sorted(re.findall(r'\{[^{}]*\}', value)):
            raise ValueError(f'Placeholder mismatch: {lang}: {key}')

neutral = set(json.loads((ROOT / 'tool/l10n/neutral.json').read_text()))
missing = [key for key in keys if key not in neutral and key not in tables['fr'] and key not in base['fr']]
# Each locale is loaded separately; neither all languages nor a translation service
# is retained by the menu-bar process.
for lang, table in tables.items():
    catalog = {**base[lang], **table}
    (ROOT / f'assets/l10n/{lang}.json').write_text(json.dumps(catalog, ensure_ascii=False, separators=(',', ':'))+'\n')

print(f'{len(keys)} application strings; '+', '.join(f"{lang}: {sum(key not in tables[lang] and key not in base[lang] and key not in neutral for key in keys)} missing" for lang in tables))
Path('/tmp/aurascribe-untranslated.json').write_text(json.dumps(missing,ensure_ascii=False,indent=2))
