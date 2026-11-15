# Active flat UI

November 14, 2026. The current installed release uses the flat external
`material_ui` and `cupertino_ui` packages. Liquid Glass has been removed.

Keep this flat implementation as the production baseline. A framework migration
purely for memory optimization needs demonstrated project-specific evidence.
The subsequent [counterbalanced comparison](flat-counterbalanced.md), with four
fresh launches per build, measured median post-close footprint at 62.7 MiB for
historical flat and 63.6 MiB for active flat (2–8 seconds), settling to 62.9 and
63.1 MiB at 24–30 seconds. Both builds had higher runs; the earlier 62.4 versus
77.5 MiB difference was not reproduced as a consistent build difference.

The renderer, dependency, glass adapter and glass-only tests were removed.
The sidebar, header, preference groups and fields again use ordinary opaque
surfaces. The app's theme supplies both external Material and Cupertino theming;
there is no deprecated compatibility bridge or extra UI framework.

The package check included [the official standalone libraries](https://docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui)
and [macos_ui](https://pub.dev/packages/macos_ui). Those pages did not provide a
comparable memory measurement for AuraScribe. The existing flat implementation
already had measured lower overhead, so another framework migration was not
justified by evidence. This is not a claim that no alternative can be lighter.

## UI bugs and features

The existing Filters/published-benchmark PageStorage isolation remains. The
complete 18-model browser, imports, optional tabs, search, localization and
compact fonts remain; restoring flat styling did not restore older feature code.

Expanded-panel testing exposed a further Developer story-browser bug: its group
expansion booleans and navigation/preview scroll offsets could inherit the same
parent PageStorage identifier. Its list, groups and per-story preview now have
distinct PageStorage keys. This fixes the double-versus-bool type error without
removing the browser or changing story selection and search behavior.

The settings regression now opens and closes every advanced disclosure, including
story groups, at both 680/960 px and normal/130% text, rather than only testing
collapsed pages. No layout or state exceptions occur in those checks.

## Validation

- All 85 tests pass, including real retained Metal inference/native PCM checks,
  complete catalog access, navigation, saved drafts and settings disposal.
- Flat-specific checks cover adaptive switch interaction, external Cupertino
  appearance, opaque fields, high contrast and absence of backdrop filters.
- Analysis is clean; dependency resolution and CocoaPods install complete.
- Release built, installed at `/Applications/AuraScribe.app`, strict deep signature
  verified. Installed Dart binary matches the verified flat bundle.
- Light/dark rendered pages and the actual installed window were inspected.
- One full Option-shortcut → real microphone → Parakeet/Metal → native paste →
  saved TextEdit document test passed. The reference audio played through the
  built-in speakers into the built-in microphone. Clipboard contents were restored.
- Four file transcriptions returned the exact reference text on MTL0.
- Original preferences/model were restored and verified; temporary API disabled.

A single post-removal running-app check measured settings idle physical footprint
at 98.6 MiB, scrolling CPU at 8.1% of one core, and post-close footprint at 77.5 MiB.
The earlier tuned-glass measurements were 145.4 MiB, 11.0%, and 120.8 MiB
respectively. This is a one-pass verification against earlier measurements, not
another counterbalanced benchmark or a guarantee for every workload. The four
file requests had a 0.289 s median for the 20.099 s fixture; no causal speedup is
claimed from that small follow-up.

Evidence: `.aurascribe/benchmarks/flat-ui/` contains `tests.log`, `analyze.log`,
`build.log`, `results.json`, `summary.json`, running-app logs, the live driver
result, and `1-flat-settings.png`. Older glass reports/bundles are historical
benchmark artifacts and are not dependencies of the running app.
