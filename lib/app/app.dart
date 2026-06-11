import 'package:flutter/material.dart';
import '../app/dictation_orchestrator.dart';
import '../shared/notification_overlay.dart';
import '../shared/smart_command_hud.dart';
import '../settings/settings_screen.dart';
import '../settings/settings_service.dart';
import '../hotkeys/hotkey_service.dart';
import '../accessibility/accessibility_service.dart';
import '../grammar/grammar_service.dart';
import '../transcription/transcription_service.dart';

class DictatorApp extends StatelessWidget {
  final DictationOrchestrator orchestrator;
  final SettingsService settings;
  final HotkeyService hotkeyService;
  final AccessibilityService accessibility;
  final TranscriptionService transcriptionService;
  final GrammarService grammarService;

  const DictatorApp({
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
    return MaterialApp(
      title: 'Dictator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF9B59F5),
          surface: const Color(0xFF1C1C1E),
        ),
        useMaterial3: true,
      ),
      home: DictatorHome(
        orchestrator: orchestrator,
        settings: settings,
        hotkeyService: hotkeyService,
        accessibility: accessibility,
        transcriptionService: transcriptionService,
        grammarService: grammarService,
      ),
    );
  }
}

class DictatorHome extends StatelessWidget {
  final DictationOrchestrator orchestrator;
  final SettingsService settings;
  final HotkeyService hotkeyService;
  final AccessibilityService accessibility;
  final TranscriptionService transcriptionService;
  final GrammarService grammarService;

  const DictatorHome({
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
      backgroundColor: orchestrator.isHudOnly ? Colors.transparent : const Color(0xFF1C1C1E),
      body: ListenableBuilder(
        listenable: orchestrator,
        builder: (context, _) {
          return Stack(
            children: [
              if (orchestrator.currentView == AppView.smartCommands)
                SmartCommandHUD(orchestrator: orchestrator)
              else if (!orchestrator.isHudOnly)
                SettingsScreen(
                  settings: settings,
                  hotkeyService: hotkeyService,
                  accessibility: accessibility,
                  transcriptionService: transcriptionService,
                  grammarService: grammarService,
                ),
              NotificationOverlay(orchestrator: orchestrator),
            ],
          );
        },
      ),
    );
  }
}
