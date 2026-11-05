import 'package:flutter/material.dart';
import '../app/dictation_orchestrator.dart';
import '../shared/app_theme.dart';
import '../shared/smart_command_hud.dart';
import '../settings/settings_screen.dart';
import '../settings/settings_service.dart';
import '../hotkeys/hotkey_service.dart';
import '../accessibility/accessibility_service.dart';
import '../grammar/grammar_service.dart';
import '../transcription/transcription_service.dart';

class AuraScribeApp extends StatelessWidget {
  final DictationOrchestrator orchestrator;
  final SettingsService settings;
  final HotkeyService hotkeyService;
  final AccessibilityService accessibility;
  final TranscriptionService transcriptionService;
  final GrammarService grammarService;

  const AuraScribeApp({
    super.key,
    required this.orchestrator,
    required this.settings,
    required this.hotkeyService,
    required this.accessibility,
    required this.transcriptionService,
    required this.grammarService,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
        valueListenable: orchestrator.settingsTreeVisible,
        builder: (context, visible, _) => visible
            ? MaterialApp(
                title: 'AuraScribe',
                debugShowCheckedModeBanner: false,
                theme: auraTheme(Brightness.light),
                darkTheme: auraTheme(Brightness.dark),
                themeMode: ThemeMode.system,
                home: AuraScribeHome(
                  orchestrator: orchestrator,
                  settings: settings,
                  hotkeyService: hotkeyService,
                  accessibility: accessibility,
                  transcriptionService: transcriptionService,
                  grammarService: grammarService,
                ),
              )
            : const SizedBox.shrink());
  }
}

class AuraScribeHome extends StatelessWidget {
  final DictationOrchestrator orchestrator;
  final SettingsService settings;
  final HotkeyService hotkeyService;
  final AccessibilityService accessibility;
  final TranscriptionService transcriptionService;
  final GrammarService grammarService;

  const AuraScribeHome({
    super.key,
    required this.orchestrator,
    required this.settings,
    required this.hotkeyService,
    required this.accessibility,
    required this.transcriptionService,
    required this.grammarService,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListenableBuilder(
        listenable: orchestrator,
        builder: (context, _) {
          return Stack(
            children: [
              if (!orchestrator.settingsTreeVisible.value)
                const SizedBox.shrink()
              else if (orchestrator.currentView == AppView.smartCommands)
                SmartCommandHUD(orchestrator: orchestrator)
              else
                SettingsScreen(
                  orchestrator: orchestrator,
                  settings: settings,
                  hotkeyService: hotkeyService,
                  accessibility: accessibility,
                  transcriptionService: transcriptionService,
                  grammarService: grammarService,
                ),
            ],
          );
        },
      ),
    );
  }
}
