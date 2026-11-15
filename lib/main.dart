import 'shared/dictation_state.dart';
import 'diagnostics/story_catalog.dart';
import 'l10n/app_localizations.dart';
import 'shared/stt_engine.dart';
import 'memory/memory_pressure_observer.dart';
import 'memory/model_memory_policy.dart';
import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
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
  await AppLocalizations.instance
      .initialize(preference: settings.interfaceLanguage);
  settings.addListener(() {
    if (AppLocalizations.instance.preference != settings.interfaceLanguage) {
      AppLocalizations.instance.setPreference(settings.interfaceLanguage);
    }
  });
  SoundService.volume = settings.soundVolume;

  HistoryService.instance.retentionDays = settings.historyRetentionDays;
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

  const lifecycle = MethodChannel('com.aurascribe/window');
  lifecycle.setMethodCallHandler((call) async {
    if (call.method == 'openStory') {
      final story = AppStory.fromLink(call.arguments as String? ?? '');
      if (story != null) await orchestrator.openStory(story.id);
      return story != null;
    }
    if (call.method == 'showSettings') await orchestrator.showSettings();
    if (call.method == 'closeSettings') await orchestrator.hideSettingsWindow();
  });
  await lifecycle.invokeMethod<void>(
      'configure', settings.option('quitClosesWindow'));
  final pendingStory = await lifecycle.invokeMethod<String>('takePendingStory');
  final startupStory = AppStory.fromLink(pendingStory ?? '');
  if (startupStory != null) await orchestrator.openStory(startupStory.id);
  await orchestrator.updates.configure();
  await orchestrator.control.configure();
  await orchestrator.meetings.recoverInterrupted();
  await orchestrator.meetings.configure();
  await orchestrator.meetings.applyRetention(settings.meetingRetentionDays);
  await orchestrator.meetings.expireAudio(
      int.tryParse(settings.optionText('meetingAudioDays', '0')) ?? 0);

  // ── Tray ───────────────────────────────────────────────
  trayService.model = transcriptionService.modelLabel;
  transcriptionService.addListener(() {
    trayService.model = transcriptionService.modelLabel;
    trayService.refresh();
  });
  await trayService.init();
  AppLocalizations.instance
      .addListener(() => orchestrator.refreshPreferences());
  late final HotkeyService hotkeyService;
  trayService.onMenuItemClick = (key) async {
    if (key.startsWith('recent:')) {
      final index = int.tryParse(key.substring(7));
      final entries = HistoryService.instance.entries;
      if (index != null && index < entries.length) {
        await Clipboard.setData(ClipboardData(text: entries[index].text));
      }
      return;
    }
    switch (key) {
      case 'pause':
        await orchestrator.setPaused(!orchestrator.paused);
        break;
      case 'paste_last':
        await orchestrator.pasteLast();
        break;
      case 'meeting':
        if (orchestrator.meetings.recording) {
          await orchestrator.meetings.stop();
        } else {
          orchestrator.settingsPage = 7;
          await orchestrator.showSettings();
        }
        break;
      case 'capture':
        orchestrator.settingsPage = 9;
        await orchestrator.showSettings();
        break;
      case 'model':
      case 'models':
        orchestrator.settingsPage = 1;
        await orchestrator.showSettings();
        break;
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
        await orchestrator.cancelDictation();
        await hotkeyService.suspendForRecorder();
        hotkeyService.dispose();
        await lifecycle.invokeMethod<void>('allowTermination');
        if (orchestrator.voiceFilter.running) {
          await orchestrator.voiceFilter.stop();
        }
        if (orchestrator.meetings.recording) await orchestrator.meetings.stop();
        WidgetsBinding.instance.removeObserver(memoryObserver);
        memoryPolicy.dispose();
        await orchestrator.control.close();
        if (orchestrator.annotations.recordingPath != null) {
          await orchestrator.annotations.toggleScreenRecording();
        }
        if (orchestrator.annotations.replayEnabled) {
          await orchestrator.annotations.toggleReplay();
        }
        orchestrator.dispose();
        trayService.dispose();
        await trayManager.destroy();
        await windowManager.destroy();
        break;
    }
  };

  // ── Hotkey Service ─────────────────────────────────────
  hotkeyService = HotkeyService(settings);
  await hotkeyService.init();
  orchestrator.addListener(() {
    unawaited(hotkeyService.setPaused(orchestrator.paused));
    unawaited(hotkeyService.updateRecording(
        orchestrator.state != DictationState.idle &&
            orchestrator.state != DictationState.error));
    unawaited(hotkeyService.setCancelEnabled(
        orchestrator.state == DictationState.recording ||
            orchestrator.isPreparing));
  });
  hotkeyService.onConfigurationChanged =
      () => trayService.updateState(orchestrator.state);
  hotkeyService.onTriggered = () => orchestrator.toggle();
  hotkeyService.onRawTriggered = () => orchestrator.toggle(raw: true);
  hotkeyService.onHoldStarted = () => orchestrator.startHeldDictation();
  hotkeyService.onHoldEnded = () => orchestrator.stopHeldDictation();
  hotkeyService.onTerminal = () => orchestrator.toggle(terminal: true);
  hotkeyService.onTypedText = () => orchestrator.processTypedText();
  hotkeyService.onReplay = () async {
    try {
      await orchestrator.annotations.saveReplay();
    } catch (e) {
      orchestrator.settingsPage = 9;
      await orchestrator.showSettings();
    }
  };
  hotkeyService.onCancel = () => orchestrator.cancelDictation();
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

  unawaited(orchestrator.meetings.resumeInterrupted());

  // ── Run ────────────────────────────────────────────────
  runApp(AuraScribeApp(
    orchestrator: orchestrator,
    settings: settings,
    hotkeyService: hotkeyService,
    accessibility: accessibilityService,
    transcriptionService: transcriptionService,
    grammarService: grammarService,
  ));
  if (!settings.option('onboardingComplete') ||
      const bool.fromEnvironment('AURASCRIBE_SHOW_SETTINGS')) {
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
