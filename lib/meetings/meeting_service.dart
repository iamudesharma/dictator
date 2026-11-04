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

class MeetingService extends ChangeNotifier {
  static const channel = MethodChannel('com.aurascribe/capture');
  final DictationOrchestrator orchestrator;
  final TranscriptionService transcription;
  final GrammarService grammar;
  MeetingService(this.orchestrator, this.transcription, this.grammar);
  bool recording = false, processing = false;
  String status = '', error = '';
  Directory? _current;
  Timer? _monitor;
  bool _cancel = false, _stopping = false, _polling = false;
  Future<List<Directory>> list() async {
    final root = await ProjectStorage.instance.directory('meetings');
    return (await root
        .list(followLinks: false)
        .where((e) => e is Directory)
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

  Future<void> start(String title,
      {bool microphone = true,
      bool system = true,
      bool echoCancellation = true}) async {
    if (recording || processing || !orchestrator.isAvailable) {
      throw StateError('Finish the current audio task first.');
    }
    orchestrator.externalActivity = 'Meeting recording';
    try {
      final id = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
      final directory = await ProjectStorage.instance.directory('meetings/$id');
      _current = directory;
      await _save(directory, {
        'title': title.trim().isEmpty ? 'Meeting' : title.trim(),
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        'state': 'starting',
        'microphone': microphone,
        'system': system,
        'echoCancellation': echoCancellation,
        'microphoneId': orchestrator.effectiveMicrophoneId
      });
      await channel.invokeMethod<void>('meetingStart', {
        'directory': directory.path,
        'microphone': microphone,
        'system': system,
        'echoCancellation': echoCancellation,
        'microphoneId': orchestrator.effectiveMicrophoneId
      });
      recording = true;
      error = '';
      status = 'Recording microphone and system tracks locally';
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
    try {
      final info =
          await channel.invokeMapMethod<String, dynamic>('meetingStop') ?? {};
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
    } finally {
      _stopping = false;
      recording = false;
      orchestrator.externalActivity = null;
      notifyListeners();
    }
  }

  void cancelProcessing() {
    _cancel = true;
    status = 'Stopping after the current segment';
    notifyListeners();
  }

  Future<void> transcribe(Directory directory,
      {bool diarize = false, int speakers = -1}) async {
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
      data['state'] = 'transcribed';
      data['model'] = transcription.modelLabel;
      data['diarization'] = diarize;
      await _save(directory, data);
      status = 'Meeting transcript saved';
    } catch (e) {
      if (segments.isNotEmpty) {
        await File('${directory.path}/transcript.partial.json')
            .writeAsString(jsonEncode(segments), flush: true);
      }
      error = e.toString();
      rethrow;
    } finally {
      processing = false;
      orchestrator.externalActivity = null;
      notifyListeners();
    }
  }

  Future<void> notes(Directory directory) async {
    if (!orchestrator.isAvailable || recording || processing) {
      throw StateError('Finish the current audio task first.');
    }
    processing = true;
    _cancel = false;
    orchestrator.externalActivity = 'Meeting notes';
    notifyListeners();
    try {
      final text = await File('${directory.path}/transcript.md').readAsString();
      var sections = <String>[];
      for (var i = 0; i < text.length; i += 2500) {
        if (_cancel) {
          throw StateError(
              'Meeting notes processing stopped; the transcript is preserved.');
        }
        sections.add(await grammar.transform(
            text.substring(i, (i + 2500).clamp(0, text.length)),
            'Summarize the meeting excerpt in at most 60 words. Preserve decisions, action items and explicit owners. Do not invent facts.'));
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
      status = 'Meeting notes saved';
    } finally {
      processing = false;
      orchestrator.externalActivity = null;
      notifyListeners();
    }
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
    if (days <= 0 || recording || processing) return;
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
    super.dispose();
  }
}
