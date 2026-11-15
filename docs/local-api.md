# Local API and Python SDK

Enable **Labs → Local API and CLI** while AuraScribe is running. The service binds only
IPv4 loopback on an ephemeral port. The project-local `.aurascribe/control/connection.json`
contains `port` and a bearer `token`; the directory is mode 700 and receipt mode 600.
Requests require `Authorization: Bearer <token>`. Disable the option to close the server.

```bash
python3 tool/aurascribe.py status
python3 tool/aurascribe.py transcribe /absolute/path/mono-16k.wav --process
python3 tool/aurascribe.py transcribe /absolute/path/mono-16k.wav --timestamps word
python3 tool/aurascribe.py start
python3 tool/aurascribe.py stop
```

Import `AuraScribe` from `tool/aurascribe.py` for the Python SDK. Its `transcribe` method
accepts `process`, `timestamps` and `instruction`; `meeting_events` yields ID-only events
for one SSE connection. Reconnect after the server's bounded connection closes.

| Endpoint | Body / result |
| --- | --- |
| `GET /status` | Dictation state, external activity and model |
| `GET /history` | Retained text history |
| `POST /dictations/start` | Optional `raw: true` |
| `POST /dictations/stop` | Waits for processing; returns state, text and error |
| `POST /dictations/cancel` | Cancels preparation or recording |
| `POST /paste-last` | Inserts the last transcript into the current field |
| `POST /transcriptions` | `path` to mono 16 kHz PCM16 WAV; optional `process`, `instruction`, `timestamps` |
| `GET /meetings/events` | SSE `meeting.transcribed` with `{"id":"..."}` after transcript completion |

`timestamps` is `none`, `segment`, or `word` (`true` also requests segments). Timings
are recognizer results, offset across 25-second decoding chunks; silent chunks may be
omitted. They describe original recognition, before output transformations. Unsupported
backends/models return 422. GGUF and Apple Speech expose the timed interface. Other
backends still support plain transcription. Busy requests return 409; malformed requests
return 400; missing/invalid authentication returns 401. JSON bodies are limited to 64 KiB.

Long WAV files decode in bounded chunks. No new model downloads happen in tests; a live
request may download the model selected in Settings. Model caches, temporary clips,
recordings and API receipts remain inside the project. The API never starts a public
listener and does not enable browser CORS access.

The optional meeting-notes integration invokes the installed OpenCode CLI; see the
[official OpenCode CLI documentation](https://opencode.ai/docs/cli/). Its configured provider
and authentication are managed by OpenCode. This integration is not exercised by the offline tests.
