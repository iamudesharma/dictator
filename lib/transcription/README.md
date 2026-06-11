# Transcription Module

Speech-to-text backends with a unified facade.

## Files

- `transcription_service.dart` — Facade delegating to the active STT backend
- `stt_backend.dart` — Abstract `SttBackend` contract
- `gemma_transcription_backend.dart` — Gemma 4 E2B multimodal (GPU-accelerated, ~2.4 GB)
- `whisper_transcription_backend.dart` — OpenAI Whisper via `whisper_ggml` (75–500 MB)
- `sherpa_nemotron_transcription_backend.dart` — Nemotron-3.5 0.6B ONNX INT8 (~300 MB, streaming)

## Backend Comparison

| Engine | Model Size | RAM | Streaming | GPU | Latency |
|--------|-----------|-----|-----------|-----|---------|
| Gemma 4 E2B | ~2.4 GB | 16 GB+ | No | Metal | Medium |
| Whisper tiny/base/small | 75–500 MB | 8 GB | No | No | Slow |
| Nemotron-3.5 0.6B | ~300 MB | 8 GB | Yes | No | Ultra-low |

## Model Details

### Gemma 4 E2B
- Downloaded from `litert-community/gemma-4-E2B-it-litert-lm` on Hugging Face
- Multimodal: accepts audio bytes directly, outputs text
- GPU-accelerated via Metal on Apple Silicon
- Requires 16 GB RAM recommended
- Reuses model for grammar cleanup (saves 270 MB download)

### Whisper
- Three sizes: tiny.en (~75 MB), base (~142 MB), small
- English-only optimized (tiny.en)
- CPU-based inference via `whisper_ggml` package
- Batch mode: records full WAV, then transcribes

### Nemotron-3.5 0.6B
- NVIDIA's streaming ASR via `sherpa-onnx`
- ONNX INT8 quantized for efficiency
- True streaming: processes audio chunks in real-time
- Supports live typing mode (text appears as you speak)
- Uses encoder/decoder/joiner transducer architecture

## Model Loading

- Backends are constructed lazily — only the active engine allocates RAM
- Concurrent `ensureLoaded()` calls share a single in-flight load
- Models auto-download from Hugging Face on first use
- Cached in `~/Library/Application Support/` with version tracking
