# AuraScribe redesign and implementation notes

Reviewed 2026-11-04 against [anomalyco/hex](https://github.com/anomalyco/hex) commit `6813f74029a9ac00daf1a02c146952e4356b7461`. The sequential [implementation ledger](implementation-checklist.md) records each previously missing option and its remaining acceptance checks.

## Interface

The settings window has native traffic lights, draggable header, system light/dark appearance, grouped preferences and a scrollable sidebar. Navigation collapses to labeled tooltips below 760 points. Dictation uses a separate 104×30 point native NSPanel just below the menu bar on the pointer’s display, with optional bottom placement. The panel has the nonactivating style, cannot become key/main, ignores mouse events, and never calls NSApp.activate. The settings window is not resized, hidden, activated or replaced during dictation. Preparation feedback appears before cold model loading; a held shortcut released during preparation never starts microphone capture. Listening shows animated microphone bars; processing shows three pulsing dots. The compact pill has no transcript paragraph or input controls. Release the held shortcut, use the toggle shortcut again, or stop from the tray. Bundled ascending/descending earcons indicate start/stop and respect the sound-volume setting. The new app icon has monochrome native-template menu bar companions.

The twelve pages are General, Speech models, Output, Vocabulary, History, Privacy & storage, Labs, Meetings, Voice filter, Capture & annotate, Updates and Playground. Features include customizable hold/toggle/raw shortcuts; mic selection; duck/mute; clipboard and terminal paste policies; ordered per-app pipelines; personal commands; opt-in history; vocabulary replacement and supported decoder prompts; input-source model switching; user-WAV benchmarks; meeting capture/transcription/diarization/notes; virtual microphone filtering/preview; region annotation/OCR; verified release updates; and metadata-only diagnostics.

## Speech runtime and models

Five backend families are available: Whisper, Gemma 4 E2B, Nemotron 3.5, Moonshine Tiny INT8 and the native GGUF speech runtime. The latter uses [transcribe.cpp](https://github.com/anomalyco/transcribe.cpp) pinned at `7045d1c0fe7cee37747b2792977421d435e75fca` (see build script for authoritative pin), with 15 Hex catalog artifacts plus Moonshine Streaming Tiny Q8. Supported catalog families include Parakeet, Qwen, SenseVoice, Cohere, GigaAM, Whisper, Nemotron and Moonshine. Custom imports validate the container’s supported speech architecture and copy weights into this project; they never move the source file.

The newer [Moonshine Streaming Tiny GGUF](https://huggingface.co/handy-computer/moonshine-streaming-tiny-gguf) is pinned at `4125c28c22a76494162094ab3566387cd92fb2f5`, 50,462,816 bytes, SHA256 `930e4622ad3a24158b91406c30c977fa6a26b34cb32d6ac3e57cfb23383a869e`. It uses a separate architecture from the original sherpa Moonshine Tiny INT8. The current GGUF adapter performs CPU clip inference and releases its subprocess after each clip; the word “Streaming” in the model name does not imply live partial text in this adapter. Nemotron’s original backend retains live streaming.

Catalog downloads verify pinned lengths and SHA256 digests. Downloads are cancellable and partial files are removed. Older noncatalog adapters retain length/receipt validation; they do not all have trusted digest verification. Disk size and parameter count are not measured RAM requirements. Benchmark the user’s microphone and accent before choosing a default. No accuracy score is invented for an unlabelled WAV.

## Storage contract

```
<project>/.aurascribe/
  models/        # weights, licenses, receipts and temporary downloads
  runtime/       # Gemma install metadata and inference compilation cache
  cache/         # plugin caches
  tmp/           # ephemeral dictation/clip WAVs
  history/       # opt-in text history
  output/        # pipeline and personal-command JSON
  meetings/      # separate audio tracks, metadata, transcripts and notes
  captures/      # screenshot, annotation metadata and exports
  benchmarks/    # selected WAV copies and results
  updates/       # verified release downloads/staging
  diagnostics/   # user-exported runtime metadata
  audio/         # audio-output recovery lease
  tools/         # native helper, build output and driver installer
```

`ProjectStorage.initialize` redirects path-provider support/library/cache/temporary paths before inference. Directory traversal and symlink destinations are rejected. Whisper receives an explicit model path; Gemma registers a project file via fromFile. No global model fallback exists and old Library downloads are not touched. Preferences and Keychain credentials use macOS facilities; model weights and inference caches do not. Build dependencies managed by pub/CocoaPods are separate from model storage.

The native plugin persists the selected checkout root so a future signed update retains it. The source directory must remain accessible, including for a DMG-launched build. To override it explicitly use `--dart-define=AURASCRIBE_PROJECT_ROOT=/absolute/project`. Cleanup is explicit; saved meeting audio is retained until deleted or the configured retention moves it to macOS Trash.

## Native packaging

The existing Gemma dylib phase is preserved. `macos/scripts/setup_aurascribe_runtime.sh` packages the native speech helper, driver installer and third-party notices. `tool/build_transcribe_runtime.sh` builds the pinned runtime; `tool/build_virtual_microphone.sh` builds the arm64 HAL plugin and installer. Native dependency copies are staged and signed inside the project without modifying the shared package cache.

The virtual microphone driver is adapted from Hex under MIT, with unique AuraScribe UIDs. Attribution is in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md). Opening the installer is an explicit user action and requires administrator authorization; building the app does not install a privileged driver.

Updates check public releases of `iamudesharma/dictator`, reject non-newer/prerelease assets, verify the GitHub digest and size, then require a valid Developer ID signature, matching Team ID/bundle ID and Gatekeeper acceptance before replacement. An ad hoc development build cannot install updates. Installation is deferred until idle with the voice filter stopped.

## Verification on this Mac

- `flutter analyze --no-pub`: no issues. `flutter test --no-pub`: 31 passing tests, including all twelve settings pages at 680/960 points, shortcut/pipeline validation and canceled-download cleanup.
- Native debug and final release builds succeeded with the added Capture, VoiceFilter and Update plugins. The final review app is 143.4 MB. `codesign --verify --deep --strict` passed; the 8.8 MB speech helper, 11 KB driver installer and notices are bundled. This is an ad hoc development signature, not notarized distribution.
- Original Moonshine INT8: real pinned sample decode passed in 181 ms. Test process RSS was 142.2 MiB before load, 176.3 MiB after load and 219.0 MiB peak; these are whole-process readings for that fixture, not per-model requirements.
- SenseVoice GGUF: real public sample decoded in 9,255 ms.
- Moonshine Streaming Tiny Q8: real public sample decoded in 437 ms with the 50 MB artifact. No subprocess memory claim is made.
- Native diarization: official public four-speaker fixture produced 10 segments across 4 anonymous speakers. Segmentation is pinned at `9403a6902bb58e3d5ae8c7e77c3422de279db2e0`, Titanet embeddings at `0743f301363dec56491a490f6d6cbc9d67f9a3bf`.

Live mic/system capture, real AX insertion/shortcuts, audio duck/restore, virtual microphone routing/echo quality, OCR capture permissions, signed login startup and newer signed-update replacement remain manual acceptance checks. No app permissions were granted or privileged driver installed during implementation. Other catalog models were not all downloaded/run.

The bundled sherpa ONNX Runtime advertises a macOS 15.5 build despite this app’s 13.0 deployment target. Successful builds on this Mac do not prove macOS 13/14 compatibility. Distribution to older macOS requires that check and potentially a compatible runtime rebuild.

For review without a startup model download:

```sh
flutter run -d macos --dart-define=AURASCRIBE_SHOW_SETTINGS=true
```

Standalone opt-in model checks are in `tool/verify_moonshine.dart`, `tool/verify_gguf.dart`, `tool/verify_moonshine_streaming.dart` and `tool/verify_diarization.dart`. They download only into this project.

## Modifier-only hold shortcut

Option hold is the default preset: either Option key held for 180 ms starts dictation; release stops or cancels preparation. A quick tap or another key pressed before activation cancels the pending trigger, so ordinary Option shortcuts do not arm the recorder. The shortcut picker can capture a standalone left/right Option, Control, Command, Shift or Fn/Globe key on release, or retain a normal multi-key chord. Modifier-only bindings are limited to dictation; other action shortcuts remain chords. Custom modifier shortcuts also support toggle mode.

The native listener observes local and global modifier changes without consuming normal key events. Global monitoring requires macOS Accessibility access. Tests cover modifier validation/persistence, picker key-down/up, native-channel routing, toggle semantics, and release while model/audio startup is pending. Real system-wide key monitoring still needs an authorized permission journey.

## Focus and insertion repair

The previous Flutter overlay called `window_manager.show(inactive: true)`, but the installed macOS plugin unconditionally called `makeKeyAndOrderFront` and `NSApp.activate`. This changed the active application even though the window overrode `canBecomeKey`. Normal dictation also did not save its destination; insertion errors were caught and returned as `false`, indistinguishable from a dispatched clipboard fallback. Live typing optimistically advanced its insertion cursor before native success.

The repaired path captures the destination PID and native focused AX element before showing feedback, uses the separate non-activating native panel, waits for the original app before insertion, restores/checks the original field, and reports missing Accessibility access or unavailable targets. Synthetic paste uses a private event source so a held Option key does not contaminate its explicit modifiers. The clipboard is restored only if its change count is unchanged.

Dart propagates native errors, commits live progress after native success, resets the live queue on every clip/backend session, retains the transcript after insertion failure, and permits Paste last recovery from the error state. A posted clipboard shortcut still cannot prove that every third-party app accepted the paste; cross-app acceptance remains manual.

`tool/verify_focus_panel.swift` exercises the production native panel without microphone access, keyboard injection or model downloads. On this Mac it passed: the panel stayed non-key and preserved the foreground application through show, animation, processing and hide. Regression tests cover both output modes failing visibly, subsequent Paste last recovery, destination capture before panel display without any main-window show call, and repeated clip insertion. With explicit user approval, the stale macOS Accessibility entry was removed and the current release app was re-added. A text-only test through the production capture → native panel → insertion path appended the sample phrase to a disposable TextEdit document, with the original text view still focused. No microphone or model was used for that insertion test. The earlier enabled switch was not sufficient: AXIsProcessTrusted remained false until the stale registration was replaced and the app restarted.

Playground includes “Test insertion after 5 seconds” for repeating the text-only check. It uses the test text or a fixed sample phrase, never opens the microphone, and does not download a model. Click the destination field during the countdown. This checks the insertion path separately from speech recognition.
