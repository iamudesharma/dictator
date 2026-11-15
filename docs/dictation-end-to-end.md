# Installed-app dictation test

November 13, 2026. Installed signed release: `/Applications/AuraScribe.app`.

Seven logged dictations completed from shortcut to saved text, including two
runs on the final build. The very first attempt entered an error state before
app stdout logging was enabled. Its error message was not captured. It did not
recur during seven subsequent logged runs; these results do not establish its
cause or rule out an intermittent failure.

## What was actually exercised

- The existing press-and-hold Option shortcut was sent as macOS keyboard events
  through CGEvent, handled by the app's native shortcut monitor. Releasing Option
  stopped recording. The dictation API start/stop routes were not used.
- The known 50-word, approximately 20-second reference WAV played through the
  built-in MacBook Pro speakers into its actual built-in microphone. This was
  acoustic microphone capture, not file transcription or a virtual audio input.
- The existing Parakeet Unified English model transcribed through Metal (`MTL0`).
  Copy-only mode was off; the existing live-typing dictation mode was unchanged.
- AuraScribe inserted the resulting text into a dedicated plain-text TextEdit
  document through its normal native paste path. The driver never typed or
  pasted the transcript. AX readback established that new text appeared; saving
  with Command-S and comparing file contents verified that it persisted.
- Each successful run returned to idle without a transcription or insertion
  error. The original clipboard contents matched after each test batch.

| Launch / lifecycle | Successful dictations | Normalized word errors per 50 words |
| --- | ---: | --- |
| Restart with stdout logging | 2 | 1, 1 |
| Normal Launch Services launch | 2 | 0, 1 |
| After idle model unloading | 1 | 1 |
| Final signed build, normal launch | 2 | 0, 1 |

The one-word differences were `control` versus `controlled`. Word comparison
ignores capitalization and punctuation; punctuation varied. This verifies the
sample's content and insertion, not perfect recognition for every utterance,
other microphones, or insertion into every application.

The loopback API was temporarily enabled only to observe status and backend.
Its setting was restored to disabled afterward. Shortcut, model, microphone,
dictation mode, clipboard settings and history settings were not changed. No
Accessibility permission database reset, driver install or new model download
was performed. The final app remains running with the monitoring API disabled.

## Additional settings issue found

The app log exposed a separate settings error:
`type 'bool' is not a subtype of type 'double?'` in scroll-position restoration.
An unkeyed published-benchmark ExpansionTile shared the page's scroll state;
text editors inside disclosures could also inherit a tile's boolean state.
This was independent of the initial dictation error, whose cause is unknown.

Benchmark expansion and its selectable text now have distinct PageStorage keys.
Advanced section bodies use separate, stable PageStorage buckets, preserving
section state while keeping editor scroll offsets separate from expansion
booleans. The buckets are released when settings are disposed.

A widget regression reproduced the error before the fix at all four combinations
of 680/960 px widths and normal/130% text. It now passes, including opening Filters,
expanding benchmark details and leaving/reopening Models. All 79 tests pass,
including real retained Metal inference and native PCM checks; analysis is clean.
The rebuilt release passes strict deep signature verification. Two final live
shortcut/insertion runs passed after installing this change. The settings
regression is covered by widget tests; the native AX driver did not complete
its optional disclosure-navigation check.

## Local evidence

All artifacts are under `.aurascribe/benchmarks/shortcut-e2e/`:

- `comparison.json`: seven transcripts, observed phases, backend, saved-file
  checks and word comparisons. Timings are polling observations, not a benchmark.
- `direct-launch-results.json`, `normal-launch-results.json`,
  `idle-reload-results.json`, `final-build-results.json`: individual batches.
- `first-attempt.log`: initial driver's error-state observation; no error message.
- `app.log`, `normal-launch-app.log`, `final-app.log`: successful app pipelines.
- `run.swift`: actual shortcut / playback / editor readback driver.
- `AuraScribe Dictation Test.txt` and `inserted-text.png`: saved text and screenshot.
- `settings-before-fix.log`, `settings-after-fix.log`, `tests.log`, `analyze.log`,
  `build.log`: regression, validation and release build evidence.
- `installed-session.log`: stdout/stderr for the restored running app, to help
  diagnose another failure without changing app settings.

The test document remains open in TextEdit. These logs and the generated
transcripts are project-local ignored artifacts, not committed model/audio data.

Follow-up for the Filters screenshot: verified the running final build directly
with native mouse and keyboard events. Models → Filters rendered normally;
typed `parakeet`, cleared the field, navigated to General and back to Models.
Filters remained expanded with all controls rendered and no new runtime errors.
The test filter was cleared and temporary accessibility inspection flags were
reset. Native screenshots: `.aurascribe/benchmarks/filters-ui/typing.png` and
`verified-filters.png`. This completes native Filters verification beyond the
prior widget regression; no further application code change was necessary.
