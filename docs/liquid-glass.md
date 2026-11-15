# Liquid Glass package integration

Historical report: Liquid Glass was removed on November 14, 2026. The current
app uses the flat external Material/Cupertino UI. See [flat-ui.md](flat-ui.md).

November 13, 2026. Flutter 3.50 / Dart 3.14 remains pinned. The signed release
is installed at `/Applications/AuraScribe.app`.

## Package research

| Package checked | Finding | Decision |
| --- | --- | --- |
| `material_ui` 1.11.0 | External official Material library; already used by the app. | Retained. |
| `cupertino_ui` 1.1.6 | External official Cupertino library. Its current API/changelog has no Liquid Glass surface or new glass control implementation. | Added as a direct dependency and used for Cupertino theming. |
| `cupertino_native` 0.1.1 | Real AppKit/UIKit controls through platform views and method channels; its author describes it as a proof of concept. | Not selected for this rendering layer. |
| `macos_glass` 0.1.4 | macOS-oriented design widgets with native window vibrancy/configuration. | Considered; would need more integration with the existing native window/HUD lifecycle. |
| `liquid_glass_renderer` 1.0.0-dev.2 | Prerelease GPU renderer; its published SDK constraint is `>=3.13.0 <3.14.0`, excluding this checkout. Full rendering also uses preview Flutter GPU. | Not selected; no SDK downgrade or dependency override. |
| `cupertino_liquid_glass` 0.9.0 | Flutter-painted glass approximation, macOS supported, compatible SDK constraint, no native plugin/channel. | Pinned and isolated behind the app's rendering adapter. |

Primary sources checked:

- [Flutter's design-library decoupling](https://flutter.dev/blog/decoupling-material-cupertino)
- [Cupertino package](https://pub.dev/packages/cupertino_ui) and [changelog](https://pub.dev/packages/cupertino_ui/changelog)
- [Cupertino Native](https://pub.dev/packages/cupertino_native)
- [macOS Glass](https://pub.dev/packages/macos_glass)
- [Liquid Glass Renderer](https://pub.dev/packages/liquid_glass_renderer) and [published metadata](https://pub.dev/api/packages/liquid_glass_renderer)
- [Cupertino Liquid Glass](https://pub.dev/packages/cupertino_liquid_glass)

## App boundary and appearance

Only `lib/shared/aura_glass.dart` imports the glass vendor. Feature screens use
`AuraGlassSurface` and `AuraGlassBackdrop`; they do not consume its settings,
theme types or widgets. Replacing the renderer is confined to this adapter.
The application continues using the external Material library and explicitly
uses the external Cupertino theme. The chosen vendor still imports SDK Cupertino
internally; explicit light/dark surface themes avoid requiring its ambient legacy
theme or the deprecated Cupertino compatibility bridge. App code adds no legacy
`flutter/material.dart` or `flutter/cupertino.dart` import.

The sidebar and header use glass surfaces with blur, tint and restrained edge
lighting over a static in-window gradient. Preference groups and input fields
use readable translucent fills. Compact fonts, page IDs, optional tabs, all 18
built-in models, imported models, search, drafts and native window interactions
remain. This is a Flutter-rendered approximation of Apple's material, not an
AppKit NSGlassEffectView bridge or desktop-wallpaper refraction.

A shared BackdropGroup covers the two non-overlapping glass regions. Scrolling
cards do not each add a blur layer. The core surface has no animation controller,
periodic timer or custom shader preload. Reduced motion removes decorative
intensity, and high contrast uses an opaque fallback. The existing lazy settings
mount/disposal policy controls the entire effect lifetime, including when the
settings window is closed. No speech, model-memory or audio code changed.

## Validation

- All 85 tests pass, including real retained Metal/PCM checks, complete model
  browser access, settings navigation, disclosure state and settings disposal.
- New tests cover light/dark glass, high-contrast fallback, reduced motion,
  absence of continuously scheduled idle frames and clean unmounting.
- All 14 settings pages pass layout checks at 680/960 px and normal/130% text.
- Light and dark renders inspected; final installed macOS window inspected.
- Analysis clean; dependency resolution and required CocoaPods install complete.
- Signed release builds (161.9 MB on disk) and passes strict deep signature
  verification. The installed app is running with Accessibility permission.
- This is UI validation, not a new CPU/RAM or speech-speed benchmark. Disk size
  and an idle-frame assertion do not establish measured resource equivalence.

Evidence: `.aurascribe/benchmarks/liquid-glass/` contains validation/build logs
and `installed-window.png`. Light/dark renders are in `.aurascribe/ui-redesign/`.
The dependency license is included in `THIRD_PARTY_NOTICES.md`.

## Measured performance follow-up

The subsequent [running-app comparison](liquid-glass-performance.md) found a
measurable UI memory and scrolling CPU cost. The adapter now caches pane themes
and omits the saturation and blurred inner-shadow passes while retaining blur,
tint, edge lighting and the shared backdrop. The tuned build is installed and
measured; the report documents remaining overhead and timing limits. It should
not be described as performance-neutral.
