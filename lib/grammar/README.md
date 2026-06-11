# Grammar Module

On-device LLM-based text cleanup and smart command execution.

## Files

- `grammar_service.dart` — Grammar cleanup pass (punctuation, capitalization, spelling)
- `grammar_model_service.dart` — Lazy Gemma 3 270M model loader for grammar
- `llm_output_sanitizer.dart` — Strips LLM artifacts (labels, explanations, quotes)
- `smart_command_service.dart` — Execute text transformations on selected text

## Grammar Cleanup

Uses a Gemma model with a system prompt tuned for Indian English transcripts:
- Fixes punctuation and capitalization
- Corrects spelling and grammar
- Preserves meaning and tone
- Skips short text (<24 chars) for performance

## Smart Command Types

- Rephrase, Summarize, Translate, Fix Grammar, Custom prompt

## Model Strategy

| STT Engine | Grammar Model | Notes |
|------------|---------------|-------|
| Gemma 4 E2B | Gemma 4 E2B (shared) | Reuses the multimodal model, no extra download |
| Whisper | Gemma 3 270M | Lightweight text-only model downloaded separately |
| Nemotron | Gemma 3 270M | Lightweight text-only model downloaded separately |

When using Gemma STT, the same model handles both transcription and grammar—saving memory and download time. Whisper and Nemotron use the smaller Gemma 3 270M for grammar cleanup.
