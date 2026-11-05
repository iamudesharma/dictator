import 'shared/stt_engine.dart';
import 'memory/memory_pressure_observer.dart';
import 'memory/model_memory_policy.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'storage/project_storage.dart';
import 'shared/sound_service.dart';
import 'history/history_service.dart';
import 'app/dictation_orchestrator.dart';
import 'audio/audio_service.dart';
import 'audio/audio_output_service.dart';
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

  await ProjectStorage.initialize();
  await const MethodChannel('com.aurascribe/accessibility').invokeMethod<void>(
      'setProjectRoot', ProjectStorage.instance.project.path);
  await AudioOutputService().end();

  // ── Window Manager ─────────────────────────────────────
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);
  const WindowOptions windowOptions = WindowOptions(
    size: Size(960, 720),
    center: true,
    backgroundColor: Color(0xFF1C1C1E),
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'AuraScribe Settings',
    minimumSize: Size(680, 520),
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
  SoundService.volume = settings.soundVolume;

  await HistoryService.instance.init();
  await _purgeStaleDictationWavs();

  final audioService = AudioService(settings);
  final vadService = VadService(audioService, settings);
  late TranscriptionService transcriptionService;
  late GrammarService grammarService;
  final memoryPolicy = ModelMemoryPolicy(
    unload: () async {
      await grammarService.releaseIdleResources();
      await transcriptionService.releaseIdleResources();
    },
    enabled: settings.unloadIdleModels,
    delay: Duration(seconds: settings.modelIdleSeconds),
    onError: (error, stack) => debugPrint('Idle model cleanup failed: $error'),
  );
  final memoryObserver = MemoryPressureObserver(memoryPolicy);
  WidgetsBinding.instance.addObserver(memoryObserver);
  transcriptionService = TranscriptionService(settings, memory: memoryPolicy);

  // Shared single GrammarModelService instance to avoid double loading
  final grammarModelService = GrammarModelService(settings);
  grammarService = GrammarService(settings, () => grammarModelService,
      memory: memoryPolicy, sharedModelProvider: () async {
    if (transcriptionService.activeEngine != SttEngine.gemma) return null;
    final error = await transcriptionService.ensureLoaded();
    if (error != null) throw StateError(error);
    return transcriptionService.sharedGemmaModelForGrammar;
  });
  final smartCommandService = SmartCommandService(
    () => grammarModelService,
    transcriptionService,
  );

  final accessibilityService = AccessibilityService();
  final trayService = TrayService(settings: settings);

  // Preload STT in the background so the first hotkey does not block on model
  // init / ONNX warm-up while the user is already speaking.
  if (settings.preloadModel) {
    unawaited(() async {
      final error = await transcriptionService.ensureLoaded();
      if (error == null) {
        grammarService
            .attachSttModel(transcriptionService.sharedGemmaModelForGrammar);
        debugPrint(
            '[AuraScribe] ✅ STT preloaded (${transcriptionService.modelLabel})');
      } else {
        debugPrint('[AuraScribe] STT preload skipped: $error');
      }
    }());
  }

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

  await orchestrator.updates.configure();
  await orchestrator.meetings.applyRetention(settings.meetingRetentionDays);

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
        await const MethodChannel('com.aurascribe/accessibility')
            .invokeMethod<void>('showAbout');
        break;
      case 'stop_background_audio':
        if (orchestrator.meetings.recording) await orchestrator.meetings.stop();
        if (orchestrator.voiceFilter.running) {
          await orchestrator.voiceFilter.stop();
        }
        break;
      case 'quit':
        if (orchestrator.voiceFilter.running) {
          await orchestrator.voiceFilter.stop();
        }
        if (orchestrator.meetings.recording) await orchestrator.meetings.stop();
        WidgetsBinding.instance.removeObserver(memoryObserver);
        memoryPolicy.dispose();
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
  hotkeyService.onConfigurationChanged =
      () => trayService.updateState(orchestrator.state);
  hotkeyService.onTriggered = () => orchestrator.toggle();
  hotkeyService.onRawTriggered = () => orchestrator.toggle(raw: true);
  hotkeyService.onHoldStarted = () => orchestrator.startHeldDictation();
  hotkeyService.onHoldEnded = () => orchestrator.stopHeldDictation();
  hotkeyService.onPasteLast = () => orchestrator.pasteLast();
  hotkeyService.onCapture = () async {
    try {
      await orchestrator.annotations.capture();
    } catch (_) {}
    orchestrator.settingsPage = 9;
    await orchestrator.showSettings();
  };
  hotkeyService.onSmartCommandTriggered =
      () => orchestrator.triggerSmartCommand();

  // ── Run ────────────────────────────────────────────────
  runApp(AuraScribeApp(
    orchestrator: orchestrator,
    settings: settings,
    hotkeyService: hotkeyService,
    accessibility: accessibilityService,
    transcriptionService: transcriptionService,
    grammarService: grammarService,
  ));
  if (const bool.fromEnvironment('AURASCRIBE_SHOW_SETTINGS')) {
    await orchestrator.showSettings();
  }
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
    // Dedicated PCM spools may survive a crash. Only expire old files here,
    // so a second developer launch cannot remove another process's recording.
    final pcm = await ProjectStorage.instance.directory('tmp/pcm');
    await for (final file in pcm.list()) {
      if (file is File &&
          DateTime.now().difference(await file.lastModified()).inHours >= 24) {
        await file.delete();
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
