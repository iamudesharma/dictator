# Compact settings redesign

November 13, 2026. The signed release is installed at `/Applications/AuraScribe.app`.

The default sidebar contains General, Models, Dictation, Features, Storage and
Updates. Features contains persistent switches for Vocabulary, History, Meetings,
Voice filter, Capture, Commands, API and Developer. Optional tabs and related
meeting/capture/history tray entries follow those choices. An active meeting keeps
its stop action available even if its tab is hidden.

These switches customize navigation. They do not erase stored data or start
recording, install a driver, enable the API server, or opt into history collection.
Each tool retains its existing operational controls. Configured vocabulary,
enabled history and an existing API configuration remain discoverable on upgrade.
Explicit tool/deep-link navigation can reveal its optional tab; search results for
hidden tools lead to Features so users can choose whether to show them.

General puts shortcut, model, microphone, appearance and permissions first.
Appearance extras, shortcut rules, sound, memory and other audio are disclosures.
Models keeps the selected model prominent and groups engines, filters, imports,
keyboard switching and benchmarks into disclosures. Dictation groups paste rules,
pipelines, recording limits and text helpers similarly. Commands and API now have
their own optional pages. Page IDs 0–11 remain stable; new IDs are 12 and 13.
Search opens and scrolls to the disclosure containing a result. Existing drafts,
modal editors, lazy settings mounting and shared feature controllers remain.

The shared theme uses 12–13 px body text, 11 px secondary text and 18 px page titles,
compact spacing, macOS switches and muted accents. Navigation uses short labels;
help is a single visible line, with full details available on hover. Error text
and editable content retain their full values. System text scaling remains enabled.
All existing interface languages remain available, including localized new page
labels and summaries. Screenshots are not model/performance measurements.

Validation:

- 75 tests pass, including the real Metal/Apple microphone-WAV regression tests.
- All 14 pages render without overflow at 680 and 960 px, at normal and 130% text.
- Feature visibility persistence, hide/show behavior, saved-data retention, search
  disclosure navigation and the active-meeting stop action are covered.
- Existing localization, story previews, draft/lifecycle and native PCM tests pass.
- Flutter analysis is clean. Release build and strict deep signature verification pass.
- Light/dark rendered pages were inspected, followed by the actual installed macOS
  window. No live user configuration or transcription data was reset for the redesign.

Local screenshots: `.aurascribe/ui-redesign/`; installed-window capture:
`installed-settings.png`. Build/check logs: `.aurascribe/tools/redesign-*.log`.

November 14 follow-up: the active implementation is now the flat external
Material/Cupertino UI; Liquid Glass was removed. The catalog/browser and
Filters/benchmark fixes remain. Expanded disclosure testing also found and fixed
story-browser PageStorage collisions. See [flat-ui.md](flat-ui.md) for validation
and the installed-app check.
