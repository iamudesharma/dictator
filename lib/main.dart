import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/dictation_orchestrator.dart';
import 'audio/audio_service.dart';
import 'vad/vad_service.dart';
import 'transcription/transcription_service.dart';
import 'grammar/grammar_model_service.dart';
import 'grammar/grammar_service.dart';
import 'grammar/smart_command_service.dart';
import 'accessibility/accessibility_service.dart';
import 'hotkeys/hotkey_service.dart';
import 'settings/settings_service.dart';
import 'tray/tray_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Window Manager ─────────────────────────────────────
  await windowManager.ensureInitialized();
  const WindowOptions windowOptions = WindowOptions(
    size: Size(480, 640),
    center: true,
    backgroundColor: Color(0xFF1C1C1E),
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'AuraScribe Settings',
    minimumSize: Size(420, 500),
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    // Start hidden — app lives in menu bar
    await windowManager.hide();
  });

  // ── Hotkey Manager ─────────────────────────────────────
  await hotKeyManager.unregisterAll();

  // ── Services ───────────────────────────────────────────
  final settings = SettingsService();
  await settings.init();

  await _purgeStaleDictationWavs();

  final audioService = AudioService();
  final vadService = VadService(audioService, settings);
  final transcriptionService = TranscriptionService(settings);
  
  // Shared single GrammarModelService instance to avoid double loading
  final grammarModelService = GrammarModelService(settings);
  final grammarService = GrammarService(settings, () => grammarModelService);
  final smartCommandService = SmartCommandService(
    () => grammarModelService,
    transcriptionService,
  );
  
  final accessibilityService = AccessibilityService();
  final trayService = TrayService();

  // Preload STT in the background so the first hotkey does not block on model
  // init / ONNX warm-up while the user is already speaking.
  unawaited(() async {
    final error = await transcriptionService.ensureLoaded();
    if (error == null) {
      grammarService.attachSttModel(transcriptionService.sharedGemmaModelForGrammar);
      debugPrint('[AuraScribe] ✅ STT preloaded (${transcriptionService.modelLabel})');
    } else {
      debugPrint('[AuraScribe] STT preload skipped: $error');
    }

    // Whisper / Nemotron STT: preload lightweight Gemma 3 270M for grammar + Smart Commands.
    // Gemma STT reuses its own multimodal model — no extra download.
    if (transcriptionService.sharedGemmaModelForGrammar == null) {
      try {
        await grammarModelService.ensureLoaded();
        debugPrint('[AuraScribe] ✅ Gemma 3 270M preloaded (grammar + Smart Commands)');
      } catch (e) {
        debugPrint('[AuraScribe] Gemma 270M preload skipped: $e');
      }
    }
  }());

  // ── Orchestrator ───────────────────────────────────────
  final orchestrator = DictationOrchestrator(
    audio: audioService,
    vad: vadService,
    transcription: transcriptionService,
    grammar: grammarService,
    accessibility: accessibilityService,
    tray: trayService,
    smartCommand: smartCommandService,
    settings: settings,
  );

  // ── Tray ───────────────────────────────────────────────
  await trayService.init();
  trayService.onMenuItemClick = (key) async {
    switch (key) {
      case 'toggle_recording':
        await orchestrator.toggle();
        break;
      case 'settings':
        await orchestrator.showSettings();
        break;
      case 'about':
        break;
      case 'quit':
        orchestrator.dispose();
        trayService.dispose();
        await trayManager.destroy();
        await windowManager.destroy();
        break;
    }
  };

  // ── Hotkey Service ─────────────────────────────────────
  final hotkeyService = HotkeyService(settings);
  await hotkeyService.init();
  hotkeyService.onTriggered = () => orchestrator.toggle();
  hotkeyService.onSmartCommandTriggered = () => orchestrator.triggerSmartCommand();

  // ── Run ────────────────────────────────────────────────
  runApp(AuraScribeApp(
    orchestrator: orchestrator,
    settings: settings,
    hotkeyService: hotkeyService,
    accessibility: accessibilityService,
    transcriptionService: transcriptionService,
    grammarService: grammarService,
  ));
}

/// Removes leftover dictation WAVs from prior runs (crash / force-quit).
Future<void> _purgeStaleDictationWavs() async {
  try {
    final dir = await getTemporaryDirectory();
    var removed = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('dictation_')) {
        await entity.delete();
        removed++;
      }
    }
    if (removed > 0) {
      debugPrint('[AuraScribe] Purged $removed stale dictation WAV(s)');
    }
  } catch (e) {
    debugPrint('[AuraScribe] WAV purge skipped: $e');
  }
}

