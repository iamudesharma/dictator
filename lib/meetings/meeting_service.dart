import '../l10n/app_localizations.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../app/dictation_orchestrator.dart';
import '../audio/pcm_wave.dart';
import '../grammar/grammar_service.dart';
import '../storage/project_storage.dart';
import '../transcription/transcription_service.dart';
import 'meeting_diarizer.dart';
import 'browser_call.dart';
import 'opencode_notes.dart';
import 'package:path/path.dart' as p;
import '../settings/settings_service.dart';

class MeetingService extends ChangeNotifier {
  static const channel = MethodChannel('com.aurascribe/capture');
  final DictationOrchestrator orchestrator;
  final TranscriptionService transcription;
  final GrammarService grammar;
  final SettingsService? settings;
  MeetingService(this.orchestrator, this.transcription, this.grammar,
      {this.settings});
  final _completed = StreamController<String>.broadcast();
  Stream<String> get completed => _completed.stream;
  final _openCode = OpenCodeNotes();
  final Set<String> _dismissedCalls = {};
  final _browserCalls = BrowserCallCache();
  BrowserCall? detectedBrowserCall;
  Timer? _callMonitor;
  bool _checkingCall = false;
  String? _automaticCall;
  DateTime? _callMissing;
  String liveText = '';
  final Set<String> _liveDone = {};
  Future<void>? _liveJob;
  Future<void> resumeInterrupted() async {
    if (settings == null || !orchestrator.isAvailable) return;
    for (final directory in await list()) {
      final data = await metadata(directory);
      if (data['resumeTranscription'] != true) continue;
      if (data['processingEngine'] != settings!.sttEngineIndex ||
          data['processingGguf'] != settings!.ggufModel ||
          data['processingLanguage'] != settings!.language) {
        status = 'Interrupted meeting awaits its original model and language';
        notifyListeners();
        continue;
      }
      try {
        await transcribe(directory,
            diarize: data['processingDiarize'] == true, resume: true);
      } catch (e) {
        error = 'Meeting recovery: $e';
        notifyListeners();
      }
    }
  }

  Future<void> expireAudio(int days) async {
    if (days <= 0 || processing || recording || !orchestrator.isAvailable) {
      return;
    }
    final cutoff = DateTime.now().subtract(Duration(days: days));
    for (final directory in await list()) {
      final data = await metadata(directory);
      final date = DateTime.tryParse(data['startedAt'] as String? ?? '');
      if (date == null ||
          !date.isBefore(cutoff) ||
          data['state'] != 'transcribed') {
        continue;
      }
      for (final track in ['microphone', 'system']) {
        final file = File('${directory.path}/$track.wav');
        if (await file.exists()) await file.delete();
      }
      data['audioExpired'] = true;
      await _save(directory, data);
    }
    notifyListeners();
  }

  Future<void> configure() async {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'stopMeeting') await stop();
    });
    _callMonitor?.cancel();
    if (settings?.option('detectCalls') != true) return;
    _callMonitor = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_checkingCall) return;
      _checkingCall = true;
      try {
        final apps =
            await channel.invokeListMethod<dynamic>('activeCallApps') ?? [];
        _browserCalls
            .retainApplications(apps.map((a) => a['id'] as String).toSet());
        if (!apps.any((a) => a['id'] == detectedBrowserCall?.application) ||
            settings?.option('browserTabNaming', fallback: true) != true) {
          detectedBrowserCall = null;
        }
        _dismissedCalls.removeWhere((id) => !apps.any((a) => a['id'] == id));
        apps.removeWhere((a) => _dismissedCalls.contains(a['id']));
        if (_automaticCall != null && recording) {
          if (apps.any((a) => a['id'] == _automaticCall)) {
            _callMissing = null;
          } else if (settings?.option('stopWhenCallEnds') == true) {
            _callMissing ??= DateTime.now();
            if (DateTime.now().difference(_callMissing!).inSeconds >= 30) {
              await stop();
            }
          }
        } else if (!recording &&
            !processing &&
            orchestrator.isAvailable &&
            apps.isNotEmpty) {
          final id = apps.first['id'] as String;
          detectedBrowserCall = null;
          if (settings?.option('browserTabNaming', fallback: true) == true &&
              BrowserCall.browserIds.contains(id)) {
            final page = await channel
                    .invokeMapMethod<String, dynamic>('browserCallPage', {
                  'id': id,
                  'automation':
                      settings?.option('browserTabAutomation') == true,
                }) ??
                {};
            detectedBrowserCall =
                _browserCalls.update(id, page, DateTime.now());
          }
          status = detectedBrowserCall == null
              ? 'Microphone activity detected in ${apps.first['name']}'
              : 'Call detected: ${detectedBrowserCall!.title}';
          if (settings?.option('autoRecordCalls') == true) {
            await start(
                detectedBrowserCall?.title ?? '${apps.first['name']} meeting',
                detectedCall: detectedBrowserCall,
                automatic: true);
            _automaticCall = apps.first['id'] as String;
          }
          notifyListeners();
        }
      } catch (e) {
        error = 'Call detection: $e';
        notifyListeners();
      } finally {
        _checkingCall = false;
      }
    });
  }

  Future<void> _liveChunks(Map<dynamic, dynamic>? info) async {
    if (_liveJob != null || _current == null) return;
    final directory = _current!;
    final ready = (info?['ready'] as List? ?? []).cast<String>();
    for (final name in ready.where((n) => !_liveDone.contains(n))) {
      if (!RegExp(r'^live-(microphone|system)-\d+\.wav$').hasMatch(name)) {
        continue;
      }
      final job = () async {
        final loadError = await transcription.ensureLoaded();
        if (loadError != null) throw StateError(loadError);
        final text = await transcription.transcribe('${directory.path}/$name');
        if (text.trim().isNotEmpty) {
          liveText = '$liveText\n$text'.trim();
          await File('${directory.path}/live-transcript.md')
              .writeAsString(liveText, flush: true);
          if (settings?.option('liveChapters') == true) {
            final heading = await grammar.transform(text,
                'Give this meeting excerpt a short factual chapter heading.');
            await File('${directory.path}/chapters.md').writeAsString(
                '## $heading\n\n$text\n\n',
                mode: FileMode.append,
                flush: true);
          }
          notifyListeners();
        }
        _liveDone.add(name);
        await File('${directory.path}/$name').delete();
      }();
      _liveJob = job;
      try {
        await job;
      } finally {
        _liveJob = null;
      }
    }
  }

  bool recording = false, processing = false;
  String status = '', error = '';
  Directory? _current;
  Timer? _monitor;
  bool _cancel = false, _stopping = false, _polling = false;
  Future<List<Directory>> list() async {
    final root = await ProjectStorage.instance.directory('meetings');
    return (await root
        .list(followLinks: false)
        .where((e) =>
            e is Directory && File('${e.path}/meeting.json').existsSync())
        .cast<Directory>()
        .toList())
      ..sort((a, b) => b.path.compareTo(a.path));
  }

  Future<Map<String, dynamic>> metadata(Directory directory) async =>
      Map<String, dynamic>.from(jsonDecode(
          await File('${directory.path}/meeting.json').readAsString()) as Map);
  Future<void> _save(Directory directory, Map<String, dynamic> data) async {
    final file = File('${directory.path}/meeting.json'),
        temp = File('${directory.path}/meeting.json.tmp');
    await temp.writeAsString(const JsonEncoder.withIndent('  ').convert(data),
        flush: true);
    await temp.rename(file.path);
  }

  Future<void> importAudio() async {
    if (!orchestrator.isAvailable || processing || recording) {
      throw StateError('Finish the current task first.');
    }
    final source = await channel.invokeMethod<String>('chooseAudio');
    if (source == null) return;
    if (!orchestrator.isAvailable) {
      throw StateError('Finish the current audio task first.');
    }
    orchestrator.externalActivity = 'Importing meeting';
    processing = true;
    Directory? directory;
    try {
      directory = await ProjectStorage.instance.directory(
          'meetings/import-${DateTime.now().microsecondsSinceEpoch}');
      final result = await Process.run('/usr/bin/afconvert', [
        source,
        '${directory.path}/system.wav',
        '-f',
        'WAVE',
        '-d',
        'LEI16@16000',
        '-c',
        '1'
      ]);
      if (result.exitCode != 0) {
        throw StateError('Audio conversion failed: ${result.stderr}');
      }
      await PcmWave.open('${directory.path}/system.wav');
      await _save(directory, {
        'title': p.basenameWithoutExtension(source),
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        'state': 'recorded',
        'imported': true
      });
      status = 'Audio imported; ready to transcribe';
    } catch (_) {
      if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
      rethrow;
    } finally {
      processing = false;
      orchestrator.externalActivity = null;
      notifyListeners();
    }
  }

  Future<void> recoverInterrupted() async {
    for (final directory in await list()) {
      try {
        final data = await metadata(directory);
        if (['transcribing', 'starting', 'recording'].contains(data['state'])) {
          data['resumeTranscription'] = data['state'] == 'transcribing';
          data['state'] = 'interrupted';
          await _save(directory, data);
        }
      } catch (e) {
        error = 'Could not read ${p.basename(directory.path)}: $e';
      }
    }
  }

  static String subtitleTime(num value, {bool vtt = false}) {
    final ms = (value * 1000).round().clamp(0, 999999999);
    return '${(ms ~/ 3600000).toString().padLeft(2, '0')}:${(ms ~/ 60000 % 60).toString().padLeft(2, '0')}:${(ms ~/ 1000 % 60).toString().padLeft(2, '0')}${vtt ? '.' : ','}${(ms % 1000).toString().padLeft(3, '0')}';
  }

  Future<void> start(String title,
      {bool microphone = true,
      bool system = true,
      bool echoCancellation = true,
      BrowserCall? detectedCall,
      bool automatic = false}) async {
    if (recording || processing || !orchestrator.isAvailable) {
      throw StateError('Finish the current audio task first.');
    }
    orchestrator.externalActivity = 'Meeting recording';
    try {
      if (title.trim().isEmpty &&
          detectedCall == null &&
          settings?.option('browserTabNaming', fallback: true) == true) {
        // Resolve the current call again: stale monitoring state must not name a
        // manually started recording after the previous call ended.
        try {
          final apps =
              await channel.invokeListMethod<dynamic>('activeCallApps') ?? [];
          final browsers = apps
              .where((a) => BrowserCall.browserIds.contains(a['id']))
              .toList();
          if (browsers.length == 1) {
            final id = browsers.single['id'] as String;
            final page = await channel
                    .invokeMapMethod<String, dynamic>('browserCallPage', {
                  'id': id,
                  'automation':
                      settings?.option('browserTabAutomation') == true,
                }) ??
                {};
            detectedCall = BrowserCall.fromPage(id, page);
          }
        } catch (_) {/* Naming is best effort; recording remains available. */}
      }
      final effectiveTitle = title.trim().isNotEmpty
          ? title.trim()
          : detectedCall?.title ?? tr('Meeting');
      final id = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
      final directory = await ProjectStorage.instance.directory('meetings/$id');
      _current = directory;
      liveText = '';
      _liveDone.clear();
      _automaticCall = null;
      _callMissing = null;
      await _save(directory, {
        'title': effectiveTitle,
        'titleSource': !automatic && title.trim().isNotEmpty
            ? 'user'
            : detectedCall != null
                ? 'browser'
                : 'default',
        if (detectedCall != null) 'call': detectedCall.toMetadata(),
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        'state': 'starting',
        'microphone': microphone,
        'system': system,
        'echoCancellation': echoCancellation,
        'microphoneId': orchestrator.effectiveMicrophoneId,
        'live': settings?.option('liveMeetings') == true ||
            settings?.option('liveChapters') == true
      });
      await channel.invokeMethod<void>('meetingStart', {
        'directory': directory.path,
        'microphone': microphone,
        'system': system,
        'echoCancellation': echoCancellation,
        'microphoneId': orchestrator.effectiveMicrophoneId,
        'live': settings?.option('liveMeetings') == true ||
            settings?.option('liveChapters') == true
      });
      final started = await metadata(directory);
      started['state'] = 'recording';
      await _save(directory, started);
      recording = true;
      error = '';
      status = 'Recording microphone and system tracks locally';
      if (settings?.option('meetingCapsule') == true) {
        await channel.invokeMethod<void>('showMeetingCapsule',
            {'title': effectiveTitle, 'stop': tr('Stop')});
      }
      notifyListeners();
      final captureStarted = DateTime.now();
      _monitor = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (_polling || !recording) return;
        _polling = true;
        try {
          if (DateTime.now().difference(captureStarted).inMinutes >= 60) {
            await stop();
            return;
          }
          final info =
              await channel.invokeMapMethod<String, dynamic>('meetingStatus');
          await _liveChunks(info);
          if (info?['running'] == false ||
              (info?['error'] as String? ?? '').isNotEmpty) {
            await stop();
          }
        } catch (e) {
          error = e.toString();
          notifyListeners();
        } finally {
          _polling = false;
        }
      });
    } catch (e) {
      _monitor?.cancel();
      try {
        await channel.invokeMethod<void>('meetingStop');
      } catch (_) {}
      recording = false;
      orchestrator.externalActivity = null;
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!recording || _stopping) return;
    _stopping = true;
    _monitor?.cancel();
    if (_automaticCall != null) _dismissedCalls.add(_automaticCall!);
    try {
      await channel.invokeMethod<void>('hideMeetingCapsule');
      final info =
          await channel.invokeMapMethod<String, dynamic>('meetingStop') ?? {};
      await _liveJob;
      final directory = _current!;
      final data = await metadata(directory);
      data.addAll({
        'endedAt': DateTime.now().toUtc().toIso8601String(),
        'state': 'recorded',
        'capture': info
      });
      await _save(directory, data);
      error = info['error'] as String? ?? '';
      status = 'Recording saved';
      _automaticCall = null;
      await File('${directory.path}/recording-finished.json').writeAsString(
          jsonEncode({
            'event': 'recording.finished',
            'time': DateTime.now().toUtc().toIso8601String()
          }),
          flush: true);
    } finally {
      _stopping = false;
      recording = false;
      orchestrator.externalActivity = null;
      notifyListeners();
    }
  }

  void cancelProcessing() {
    _cancel = true;
    _openCode.cancel();
    status = 'Stopping after the current segment';
    notifyListeners();
  }

  Future<void> transcribe(Directory directory,
      {bool diarize = false, int speakers = -1, bool resume = false}) async {
    if (recording || processing || !orchestrator.isAvailable) {
      throw StateError('Finish the current audio task first.');
    }
    processing = true;
    _cancel = false;
    error = '';
    orchestrator.externalActivity = 'Meeting transcription';
    notifyListeners();
    final segments = <Map<String, dynamic>>[];
    try {
      final loadError = await transcription.ensureLoaded();
      if (loadError != null) throw StateError(loadError);
      final data = await metadata(directory),
          capture = data['capture'] as Map? ?? {};
      if (!await File('${directory.path}/microphone.wav').exists() &&
          !await File('${directory.path}/system.wav').exists()) {
        throw StateError(
            'Meeting audio is missing or has expired. Existing transcripts are preserved.');
      }
      final checkpoint = File('${directory.path}/transcript.partial.json');
      if (resume && await checkpoint.exists()) {
        if (data['processingModel'] != transcription.modelLabel ||
            data['processingDiarize'] != diarize) {
          throw StateError(
              'Resume with the original speech model and speaker setting, or start a new transcription.');
        }
        segments.addAll((jsonDecode(await checkpoint.readAsString()) as List)
            .map((e) => Map<String, dynamic>.from(e as Map)));
      }
      data['state'] = 'transcribing';
      data['processingModel'] = transcription.modelLabel;
      data['processingEngine'] = settings?.sttEngineIndex;
      data['processingGguf'] = settings?.ggufModel;
      data['processingLanguage'] = settings?.language;
      data['processingDiarize'] = diarize;
      await _save(directory, data);
      final starts = Map<String, dynamic>.from(capture['starts'] as Map? ?? {});
      final times = starts.values.whereType<num>().toList();
      final baseline = times.isEmpty
          ? 0.0
          : times.reduce((a, b) => a < b ? a : b).toDouble();
      for (final track in ['microphone', 'system']) {
        final source = File('${directory.path}/$track.wav');
        if (!await source.exists()) continue;
        final wave = await PcmWave.open(source.path);
        status = diarize && track == 'system'
            ? 'Identifying speakers…'
            : 'Transcribing $track…';
        notifyListeners();
        final spans = diarize && track == 'system'
            ? await MeetingDiarizer().process(source.path, speakers: speakers)
            : [SpeakerSpan(0, wave.seconds, 0)];
        final offset =
            ((starts[track] as num?)?.toDouble() ?? baseline) - baseline;
        for (final span in spans) {
          for (var start = span.start; start < span.end; start += 25) {
            if (_cancel) {
              throw StateError(
                  'Meeting processing stopped. Recorded audio remains available.');
            }
            final end = (start + 25).clamp(start, span.end).toDouble();
            if (resume &&
                segments.any((s) =>
                    s['track'] == track &&
                    ((s['start'] as num) - start - offset).abs() < .01 &&
                    ((s['end'] as num) - end - offset).abs() < .01)) {
              continue;
            }
            final clip = File(
                '${(await ProjectStorage.instance.directory('tmp')).path}/meeting-clip.wav');
            if (!await wave.writeClip(clip, start, end)) continue;
            try {
              final text = await transcription.transcribe(clip.path);
              if (text.trim().isNotEmpty) {
                segments.add({
                  'start': start + offset,
                  'end': end + offset,
                  'speaker': track == 'microphone'
                      ? 'You'
                      : diarize
                          ? 'Speaker ${span.speaker + 1}'
                          : 'Remote audio',
                  'text': text,
                  'track': track
                });
              }
            } finally {
              if (await clip.exists()) await clip.delete();
            }
            await File('${directory.path}/transcript.partial.json')
                .writeAsString(jsonEncode(segments), flush: true);
            status =
                'Transcribing $track: ${end.round()} / ${wave.seconds.round()} seconds';
            notifyListeners();
          }
        }
      }
      segments.sort((a, b) => (a['start'] as num).compareTo(b['start'] as num));
      await File('${directory.path}/transcript.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert(segments),
          flush: true);
      await File('${directory.path}/transcript.md').writeAsString(
          segments
              .map((s) =>
                  '[${(s['start'] as num).toStringAsFixed(1)}s] ${s['speaker']}: ${s['text']}')
              .join('\n\n'),
          flush: true);
      await File('${directory.path}/transcript.srt').writeAsString(
          [
            for (var i = 0; i < segments.length; i++)
              '${i + 1}\n${subtitleTime(segments[i]['start'] as num)} --> ${subtitleTime(segments[i]['end'] as num)}\n${segments[i]['speaker']}: ${segments[i]['text']}\n'
          ].join('\n'),
          flush: true);
      await File('${directory.path}/transcript.vtt').writeAsString(
          'WEBVTT\n\n${segments.map((s) => '${subtitleTime(s['start'] as num, vtt: true)} --> ${subtitleTime(s['end'] as num, vtt: true)}\n${s['speaker']}: ${s['text']}\n').join('\n')}',
          flush: true);
      data['state'] = 'transcribed';
      data['resumeTranscription'] = false;
      data['model'] = transcription.modelLabel;
      data['diarization'] = diarize;
      await _save(directory, data);
      await _exportNamed(directory, data);
      _completed.add(p.basename(directory.path));
      status = 'Meeting transcript saved';
    } catch (e) {
      if (segments.isNotEmpty) {
        await File('${directory.path}/transcript.partial.json')
            .writeAsString(jsonEncode(segments), flush: true);
      }
      final saved = await metadata(directory);
      saved['state'] = 'interrupted';
      saved['error'] = e.toString();
      await _save(directory, saved);
      error = e.toString();
      rethrow;
    } finally {
      processing = false;
      orchestrator.externalActivity = null;
      notifyListeners();
    }
  }

  Future<void> notes(Directory directory, {String provider = 'local'}) async {
    if (!orchestrator.isAvailable || recording || processing) {
      throw StateError('Finish the current audio task first.');
    }
    processing = true;
    _cancel = false;
    orchestrator.externalActivity = 'Meeting notes';
    notifyListeners();
    try {
      final text = await File('${directory.path}/transcript.md').readAsString();
      if (provider == 'off') {
        throw StateError('Choose a meeting summary provider first.');
      }
      if (provider == 'opencode') {
        final result = await _openCode.generate(
            directory, settings?.decoderVocabulary ?? '');
        await File('${directory.path}/notes.md')
            .writeAsString(result, flush: true);
        final data = await metadata(directory);
        if (data['titleSource'] != 'user') {
          data['title'] = result
              .split('\n')
              .first
              .replaceFirst(RegExp(r'^#+\s*'), '')
              .trim();
          data['titleSource'] = 'summary';
        }
        await _save(directory, data);
        await _exportNamed(directory, data);
        status = 'OpenCode meeting notes saved';
        return;
      }
      var sections = <String>[];
      for (var i = 0; i < text.length; i += 2500) {
        if (_cancel) {
          throw StateError(
              'Meeting notes processing stopped; the transcript is preserved.');
        }
        sections.add(await grammar.transform(
            text.substring(i, (i + 2500).clamp(0, text.length)),
            'Summarize the meeting excerpt in at most 60 words. Preserve decisions, action items and explicit owners. Do not invent facts. Preferred spellings: ${settings?.decoderVocabulary ?? ''}'));
      }
      while (sections.join('\n').length > 3000) {
        final next = <String>[];
        for (var i = 0; i < sections.length; i += 3) {
          if (_cancel) {
            throw StateError(
                'Meeting notes processing stopped; the transcript is preserved.');
          }
          next.add(await grammar.transform(
              sections.sublist(i, (i + 3).clamp(0, sections.length)).join('\n'),
              'Merge these meeting summaries into at most 80 words. Keep only stated facts, decisions and action items.'));
        }
        if (next.join('\n').length >= sections.join('\n').length) {
          throw StateError(
              'The text model could not condense these notes. The transcript is preserved.');
        }
        sections = next;
      }
      final result = await grammar.transform(sections.join('\n'),
          'Produce meeting notes with a concise summary, decisions and action items. Use only stated facts; leave owners or dates unspecified when unknown.');
      await File('${directory.path}/notes.md')
          .writeAsString(result, flush: true);
      final metadataValue = await metadata(directory);
      if (metadataValue['titleSource'] != 'user') {
        metadataValue['title'] = await grammar.transform(result,
            'Return a concise factual meeting title of at most eight words.');
        metadataValue['titleSource'] = 'summary';
      }
      await _save(directory, metadataValue);
      await _exportNamed(directory, metadataValue);
      status = 'Meeting notes saved';
    } finally {
      processing = false;
      orchestrator.externalActivity = null;
      notifyListeners();
    }
  }

  Future<void> rename(Directory directory, String title) async {
    if (recording || processing) {
      throw StateError('Finish the current meeting task first.');
    }
    final data = await metadata(directory);
    if (title.trim().isEmpty) throw ArgumentError('Enter a meeting title.');
    data['title'] = title.trim();
    data['titleSource'] = 'user';
    await _save(directory, data);
    await _exportNamed(directory, data);
    notifyListeners();
  }

  /// macOS limits a filename to 255 UTF-8 bytes, not 255 Unicode characters.
  /// Leave room for the timestamp and suffix while keeping the full UI title.
  static String exportTitle(String rawTitle) {
    final clean =
        rawTitle.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f\x7f]'), '-').trim();
    var bytes = 0;
    final runes = <int>[];
    for (final rune in clean.runes) {
      final size = utf8.encode(String.fromCharCode(rune)).length;
      if (bytes + size > 180) break;
      runes.add(rune);
      bytes += size;
    }
    return runes.isEmpty ? 'Meeting' : String.fromCharCodes(runes);
  }

  Future<void> _exportNamed(
      Directory directory, Map<String, dynamic> data) async {
    final title = exportTitle(data['title'] as String? ?? 'Meeting');
    final date = (data['startedAt'] as String? ?? '')
        .replaceAll(RegExp(r'[^0-9T-]'), '-');
    final name = '${date.substring(0, date.length.clamp(0, 40))}-$title';
    final previous = data['exportName'] as String?;
    for (final suffix in ['', '-notes']) {
      final source = File(
          '${directory.path}/${suffix.isEmpty ? 'transcript' : 'notes'}.md');
      if (!await source.exists()) continue;
      final link = suffix.isEmpty
          ? '[Meeting notes](${Uri.encodeComponent('$name-notes.md')})'
          : '[Transcript](${Uri.encodeComponent('$name.md')})';
      await File('${directory.path}/$name$suffix.md').writeAsString(
          '# ${data['title']}\n\n$link\n\n${await source.readAsString()}',
          flush: true);
      if (previous != null &&
          previous != name &&
          p.basename(previous) == previous) {
        final old = File('${directory.path}/$previous$suffix.md');
        if (await old.exists()) await old.delete();
      }
    }
    data['exportName'] = name;
    await _save(directory, data);
  }

  Future<void> trash(Directory directory) async {
    if (recording || processing) {
      throw StateError(
          'Stop recording or processing before moving recordings to Trash.');
    }
    await channel.invokeMethod<void>('trash', directory.path);
    notifyListeners();
  }

  Future<void> applyRetention(int days) async {
    if (days <= 0 || recording || processing || !orchestrator.isAvailable) {
      return;
    }
    final cutoff = DateTime.now().subtract(Duration(days: days));
    for (final directory in await list()) {
      final file = File('${directory.path}/meeting.json');
      if (!await file.exists()) continue;
      final saved = await metadata(directory);
      final date = DateTime.tryParse(saved['startedAt'] as String? ?? '');
      if (date != null && date.isBefore(cutoff)) await trash(directory);
    }
  }

  @override
  void dispose() {
    _monitor?.cancel();
    _callMonitor?.cancel();
    _openCode.cancel();
    unawaited(_completed.close());
    super.dispose();
  }
}
