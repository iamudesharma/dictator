# Hex 3.4 implementation and acceptance ledger

Reference: [Hex v3.4.0](https://github.com/anomalyco/hex/releases/tag/v3.4.0), commit
`8766d096eb3c98a5b1a54cb966a6daa717bc839d` (November 11, 2026).
The table records the implemented macOS behavior. It is not a claim that hardware,
model quality, signing, or every detail of the upstream interface has passed acceptance.

## Models

All 17 pinned GGUF artifacts from the release are in `lib/transcription/gguf_catalog.dart`,
including Orukeet, Granite Speech 5.0 multilingual, NB-Whisper Medium and Parakeet Ultra.
Repository revisions, filenames, byte sizes and SHA-256 values follow the released catalog.
The existing Moonshine Streaming Tiny artifact is also retained. Capability and published
benchmark metadata comes from the same release; WER and CER from different datasets are
not ranked as comparable results.

Apple Speech is available as an additional on-device backend using installed macOS speech
assets and Speech Recognition permission. It rejects unavailable on-device recognition;
it does not silently use Apple's server recognizer. Existing Gemma, Whisper, Nemotron ONNX
and Moonshine INT8 backends remain available. Only selected weights download.

## All 72 released Labs options

| Hex option | AuraScribe implementation / platform boundary |
| --- | --- |
| `Meetings` | Separate microphone/system tracks, import, resume checkpoints, diarization and local/OpenCode notes (`lib/meetings`). |
| `VoiceFilter` | Existing real-time native filter and optional virtual microphone; driver installation and hardware acceptance remain manual. |
| `Playground` | Searchable story browser with 63 isolated AuraScribe fixtures, language/theme/size controls, reset, story links and Command-Shift-D; diagnostics and real output preview remain a separate tab. |
| `LiveText` | Partial transcript in the native dictation indicator. |
| `FailureNotices` | Native indicator and settings surface preparation, recognition and insertion failures. |
| `LiveTyping` | Incremental focused-field insertion with final transcript reconciliation. |
| `LiveChapters` | Optional local chapter headings while completed meeting chunks transcribe. |
| `VocabularyBiasing` | Parakeet vocabulary and Whisper context prompts; deterministic preferred-spelling replacements. |
| `TerminalPaste` | Terminal-aware Ctrl-Shift-V insertion policy. |
| `KeyboardModelSwitching` | Input-source speech-model mapping, applied when a dictation starts. |
| `AppModelSwitching` | Per-application output profile can override speech model and language; original selection restores afterward. |
| `MouseShortcuts` | Middle/button 4/button 5 dictation controls. |
| `PauseBrowser` | Opt-in browser media pause/restore via Apple Events; Safari/Chromium JavaScript automation permissions are required. |
| `ShareShortcut` | Optional native event tap passes configured keys to the foreground app. |
| `UnloadIdle` | Existing activity-fenced memory policy and standalone Moonshine worker. |
| `RestoreShortcutDefault` | Restore Paste-last shortcut in General. |
| `KeepOnClipboard` | Existing restore-clipboard preference. |
| `CopyOnly` | Global clipboard-only dictation output. |
| `ReturnToApp` | Configurable return to the pinned original app before insertion. |
| `SpokenFormatting` | Deterministic English new-line, paragraph, bullet and quote commands. |
| `FillerWords` | Deterministic English filler removal, with word boundaries. |
| `SubtitleExport` | Meeting SRT/VTT files. Current meeting subtitles use chunk/diarization boundaries, not word alignment. |
| `SecondDictationShortcut` | Independent second shortcut with toggle/hold activation. |
| `TerminalPasteShortcut` | Optional dedicated terminal dictation shortcut. |
| `SmartSpacing` | AX caret context adds a leading space after an existing word; unavailable AX context leaves text unchanged. |
| `SpokenSymbols` | Deterministic English punctuation, symbols and joined identifier components. |
| `PickerSortFilter` | Name/size ordering, model-name search and supported-language filter. |
| `SidedChords` | Recorder preserves left/right modifiers; native event tap checks physical modifier state. |
| `TapOrHold` | Toggle shortcuts may stop on release after a hold; short taps toggle. |
| `DoubleTapModifiers` | Main modifier or modifier-only chord supports double tap. |
| `BenchmarkDetails` | Published raw WER/CER, dataset, source revision and recorded conditions; unknown facts stay unknown. |
| `ParakeetUltra` | Pinned upstream artifact already included. |
| `StandaloneSpecialKeys` | Unmodified function/navigation and special keys accepted where macOS supplies a key mapping. |
| `HistoryStats` | Retained-entry and word counts. |
| `RecentDictations` | Copy any of the five most recent retained dictations from the menu bar. |
| `SkipPauses` | Optional bounded-memory pause compaction before whole-clip inference; original history audio is retained. |
| `StopWhenCallEnds` | Auto-started recordings stop after 30 seconds without detected call-app microphone activity. |
| `OutputFixes` | Output preview includes Vocabulary and Fix this actions. |
| `PickerActiveFirst` | Active-model-first ordering. |
| `ModelInPlace` | Reference models already inside project `.aurascribe/models`; external files are copied to respect this project’s storage boundary. |
| `PickerDownloaded` | Downloaded-model filter and artifact sizes. |
| `SectionKeyAlone` | ISO section key can use the native shortcut tap without a modifier. |
| `KeepRecordings` | Separate opt-in history audio, playback, retranscription, retention and orphan cleanup. |
| `SettingsSearch` | Search indexed setting labels across all settings pages. |
| `Appearance` | System/light/dark window appearance. |
| `ReleaseNotesLink` | Reference release notes link in Labs; project update notes remain in Updates. |
| `HideMenuBarIcon` | Hide icon while shortcuts run; reopening the app shows Settings. |
| `MovableMeetingCapsules` | Draggable native meeting control panel with saved placement. |
| `GnomeClipboardRestore` | Not applicable to macOS; native clipboard save/restore remains enabled by default. |
| `TypedText` | Optional shortcut processes the AX-exposed focused field using the app’s output steps. |
| `MeetingNotesVocabulary` | Preferred spellings passed to local and OpenCode meeting notes. |
| `NotchIndicator` | Optional native indicator placement using the screen’s safe-area inset. |
| `MeetingFinishedEvent` | Authenticated SSE `/meetings/events`, carrying the ID when transcription completes. |
| `GnomeMeetingCapsules` | Not applicable to macOS; native AppKit capsule provided. |
| `GnomeAnnotate` | Not applicable to macOS; native capture and Flutter annotation provided. |
| `Screenshots` | Region/window capture, clipboard copy, local PNG, annotation, crop and share sheet. |
| `FollowLiveTranscript` | Live transcript follows the bottom while allowing scrolling through earlier text. |
| `MoreCallApps` | Microphone activity detection on macOS 14.2+, including browser helper ownership. Visible call tabs name supported web calls through Accessibility, with an optional Automation fallback. |
| `AnnotateReplay` | Opt-in encoded screen-only rolling buffer; save the last 15 seconds to MOV. Screen-recording permission required. |
| `MeetingImport` | Audio/video file picker and local mono PCM conversion. |
| `MeetingDescriptiveFilenames` | Dated title-based transcript and notes exports after naming/rename. |
| `MeetingNotesFile` | Separate linked Markdown notes and transcript exports. |
| `QuitClosesWindow` | Optional Command-Q closes Settings; tray Quit terminates the app. |
| `ExpireMeetingAudio` | Separate 7/30-day expiry for successfully transcribed meeting audio. |
| `CapsLockDictation` | Caps Lock toggles dictation; native HID lock light follows recording/processing and restores the prior state when disabled. |
| `OpenCodeInWsl` | WSL is not applicable to macOS. Optional installed macOS OpenCode integration uses its configured provider. |
| `TranscribeFiles` | Python CLI/SDK and authenticated local WAV transcription endpoint. |
| `ApiProcessing` | Optional global output processing and additional instruction per API transcription. |
| `ApiTimestamps` | Recognizer segment/word timestamps through GGUF and Apple Speech; unsupported requests return 422 instead of invented timings. |
| `SpeakersOnly` | Output-volume adjustment restricted to a known internal-speaker route; unknown/headphone routes stay unchanged. |
| `MoreDictationShortcuts` | Four additional independently enabled dictation shortcuts with toggle/hold activation. |
| `PauseMenu` | Pause unregisters keyboard and auxiliary shortcuts; Resume reinstates them. |

## Additional workflows and limits

- First-run setup includes permission guidance and a practice dictation.
- History keeps up to 100 text entries, five previous text versions, configured language,
  optional WAV recordings and 1/7/30/90-day retention. Language metadata is a configured
  hint, not a detected-language claim.
- Meeting transcription checkpoints survive interruption and can resume with the original
  engine, catalog model and language. Cancellation retains original tracks and partial text.
- Interface language is independent of speech language: System, English, Polish, Simplified
  Chinese, Traditional Chinese, Japanese, German, Spanish, Ukrainian, Brazilian Portuguese,
  French and Russian. Flutter controls, settings search, tray labels and application help use
  local catalogs. Provider/OS errors and published model metadata retain their source text.
- The story browser uses AuraScribe components and 63 in-memory fixtures across 11 families.
  Preview actions never invoke microphone/model/download/settings services. It is not a
  pixel-for-pixel port of Hex's Rune, Linux, Windows or discarded prototype scenes.
- Browser naming reads the microphone-active browser's front window/tab, including behind
  another application. Recognized sites: Google Meet, Banshee, WhatsApp, Gather, Google Voice,
  Messenger, Teams, FaceTime and GroupMe. Unknown sites or denied permissions use the app name.
  Only the call service and host are persisted, never URL query strings or fragments. An
  optional Automation fallback can request macOS permission; it never executes page scripts.
  User-entered meeting names survive summary generation.
- Screen replay currently records the selected primary display without audio. It is explicit
  opt-in and shows the macOS recording indicator. Saved replay/recording files are project-local.
- OpenCode is optional and uses its installed CLI/configured provider, which can send the
  transcript to a remote service. AuraScribe's default speech and cleanup paths remain local.
- In-place models deliberately remain under the project storage boundary. No global model
  cache fallback or external model symlink is introduced.

## Combined acceptance session

1. Launch the built app. Check first-run guidance, all pages at narrow/wide window sizes,
   settings search, appearance, close/reopen, and menu-bar visibility/Command-Q behavior.
2. Grant microphone and Accessibility permissions. Try toggle, hold, quick release during
   loading, cancellation, extra shortcuts, double tap, sided chords, mouse and Caps Lock.
   Pause shortcuts and verify the foreground app receives its keys.
3. Dictate into TextEdit, a browser editor and a terminal. Try live text, copy-only,
   keep/restore clipboard, return-to-app, smart spacing, spoken symbols, vocabulary,
   per-app speech/language and typed-text processing.
4. Check speakers/headphones, volume restoration after stop/cancel/error, and optional
   browser-media pause/restore including a tab switch while recording.
5. Enable history/audio retention. Dictate, play, retranscribe using another model/language,
   edit/restore versions, delete and verify the recording is removed.
6. Download and decode a known fixture for each desired model. Check language-hint behavior,
   native timestamps where supported, cold/warm latency and memory. Merely compiling a
   backend does not establish these results.
7. Import an audio file; record a meeting with microphone/system tracks. Try live transcript,
   chapters, diarization, stop, interrupt/resume, notes, rename, subtitle exports and expiry.
   Test call detection with a real supported app and verify stopping does not immediately
   restart the same call recording.
8. Capture a region/window, draw, crop, add text/notes, undo, export/copy/share. Record a screen
   video. Enable replay, wait at least 15 seconds, save it, stop replay and verify its buffer
   is cleared and macOS recording stops.
9. Enable the API and use `tool/aurascribe.py`. Verify authentication, WAV transcription,
   output processing, unsupported timestamps and `/meetings/events` against a completed
   meeting. API connection credentials stay private under `.aurascribe/control`.
10. In General, switch interface languages and System, restart, and check localized search,
    tray labels and speech-language independence. Review translated wording with native speakers.
11. In Playground, search and open fixture families, change preview language/theme/size, edit
    a fixture, reset it, and open a copied `aurascribe://story/...` link. Check Command-Shift-D.
    Preview language changes must not change the application language or real settings.
12. Enable call detection and Browser-tab naming. Try Google Meet and other supported sites
    in Safari/Chrome/Firefox, including a background browser and a browser helper process.
    Check permission denial, a non-call tab, ended calls, blank manual titles, explicit names,
    and summary generation after renaming. Automation is separately opt-in.
13. Validate the optional virtual-microphone driver and signed updater separately using the
    existing hardware/signing gates in `implementation-checklist.md`.

## Validation record

Completed November 12, 2026:

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --reporter expanded`: all 52 tests passed. Includes settings
  navigation at 680/960 px, existing lifecycle/memory tests, retained history audio,
  model metadata, native-timestamp parsing, pause compaction, output transforms and
  authenticated loopback API transcription using an injected recognizer.
- All 17 upstream model repository/revision/filename/size/SHA pins matched the local catalog.
- Debug and release macOS builds succeeded using Xcode's developer directory. Release
  artifact: `build/macos/Build/Products/Release/AuraScribe.app` (reported 150.2 MB).
- `codesign --verify --deep --strict` passed for the release bundle. This is bundle
  integrity verification, not Developer ID notarization or signed-updater acceptance.
- Native Moonshine AOT and transcribe helpers are present in the release Resources directory.
- Python CLI syntax/help, plist/project syntax and `git diff --check` passed.

Build warnings include dependencies without Swift Package Manager support, existing
Whisper/HotKey compiler warnings, and an ONNX runtime dylib built for macOS 15.5 while the
app targets 13.0. The macOS 13/14 compatibility gate therefore remains open.

No live microphone, Accessibility insertion, screen capture, call, provider or model-quality
acceptance is implied by compilation or mocked tests. No model weights, external provider
calls, driver installation, update publication or deployment were performed in this pass.

## Final combined validation — November 13, 2026

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --reporter expanded`: all **63 tests passed**, including the
  existing regressions, all 63 story fixtures at compact width with enlarged French text,
  localized navigation/search, independent language persistence, placeholder preservation,
  browser call-site selection/cache expiry/privacy, story links/reset, and UTF-8 meeting
  export filenames. All 593 registered application strings have catalog entries in each
  non-English interface language, except explicitly listed proper names and units.
- Release macOS build succeeded (152.2 MB). The CoreAudio ownership warning in the new
  browser lookup was corrected. Native lookup also handles microphone helper processes
  without a LaunchServices application entry by following process ancestry.
- `codesign --verify --deep --strict` passed. All ten packaged translation catalogs match
  their source hashes; English is the source language. Both bundled inference helpers remain
  present. Plist/project syntax and `git diff --check` passed.
- Logs: `.aurascribe/completion-analyze.log`, `.aurascribe/completion-tests.log`, and
  `.aurascribe/completion-release-build.log`.

The release artifact is `build/macos/Build/Products/Release/AuraScribe.app`. This validation
used mocked native operations and fixture data; real microphone, Accessibility, browser
Automation, call capture, model-quality, driver, signed-update and macOS 13/14 acceptance
remain the combined manual session above. Existing plugin SwiftPM/deprecation warnings and
ONNX's macOS 15.5 deployment warning remain. No model weights were downloaded, provider
requests sent, driver installed, update published or app deployed during this completion pass.
