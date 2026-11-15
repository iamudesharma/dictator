# Full built-in model browser

November 13, 2026.

The pinned GGUF catalog still contains all 18 built-in models. The existing
filtered dropdown could show a subset, and its scroll position could make other
entries difficult to discover. Importing is not required for built-in models.

Models now includes **Browse all models (18)** below the current model picker.
It opens the complete built-in catalog independently of the page's name,
language and downloaded-only filters. The dialog has its own search field,
a visible scrollbar, download sizes and current-selection marker. Imported
models appear alongside the built-in entries. Closing and reopening resets the
dialog search. Choosing a different model uses the same verified project-local
download/load path as the existing picker.

Existing engine choices, page filters and custom imports remain available.
The dialog and its scroll controller are disposed on close. Its labels are
translated into all supported interface languages. No model pin, checksum,
architecture, inference settings or storage location changed.

Built-in entries:

- Cohere Transcribe
- GigaAM v3
- Granite Speech 5.0 470M TurboCTC
- Ivrit Whisper Large v3 Turbo
- Moonshine Streaming Tiny Q8
- NB Whisper Medium
- Nemotron 3.5 ASR
- Orukeet
- Parakeet Ultra
- Parakeet Unified English
- Parakeet v2
- Parakeet v3
- Qwen3 ASR 0.6B
- QwenCleo ASR 1.7B
- SenseVoice Small
- Underdog Bark 3 Clean
- Underdog Bark 3 Pro
- Whisper Large v3 Turbo

Validation: 83 tests pass, including all catalog entries, imported entries,
search/clear, selection returned by the dialog, and access to the full catalog
while the page is filtered to Parakeet. Tests cover 680/960 px windows and
normal/130% text, together with existing native Metal and PCM regressions.
Analysis is clean. The signed release is installed at
`/Applications/AuraScribe.app` and passes strict deep signature verification.
The complete browser was opened and visually inspected in the running app.
This does not assert live inference testing of every model in the catalog.

Evidence: `.aurascribe/benchmarks/model-catalog/` includes test, analysis and
build logs; `page.png` shows the 18-model button and `browser.png` shows the
running full-catalog dialog. The new widget is
`lib/settings/model_catalog_dialog.dart`.
