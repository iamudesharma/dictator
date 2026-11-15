import '../output/output_pipeline.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../app/dictation_orchestrator.dart';
import '../transcription/transcription_service.dart';
import '../settings/settings_service.dart';
import '../history/history_service.dart';
import '../storage/project_storage.dart';
import '../audio/pcm_wave.dart';
import '../transcription/timed_transcript.dart';

/// Authenticated loopback-only control API. Disabled by default.
class ControlService {
  final DictationOrchestrator orchestrator;
  final TranscriptionService transcription;
  final SettingsService settings;
  ControlService(this.orchestrator, this.transcription, this.settings);
  HttpServer? _server;
  String? _token;
  File? _receipt;
  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
    final receipt = _receipt;
    _receipt = null;
    if (receipt != null && await receipt.exists()) {
      final saved = jsonDecode(await receipt.readAsString()) as Map;
      if (saved['token'] == _token) await receipt.delete();
    }
  }

  Future<void> configure() async {
    await _server?.close(force: true);
    _server = null;
    final directory = await ProjectStorage.instance.directory('control');
    final receipt = _receipt = File('${directory.path}/connection.json');
    if (await receipt.exists()) await receipt.delete();
    if (!settings.controlApi) return;
    await Process.run('/bin/chmod', ['700', directory.path]);
    _token = base64UrlEncode(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    );
    final server = _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    await receipt.writeAsString(
      jsonEncode({'port': server.port, 'token': _token}),
      flush: true,
    );
    await Process.run('/bin/chmod', ['600', receipt.path]);
    server.listen((request) => unawaited(_handle(request)));
  }

  Future<void> _handle(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    try {
      if (request.headers.value(HttpHeaders.authorizationHeader) !=
          'Bearer $_token') {
        request.response.statusCode = 401;
        request.response.write(
          jsonEncode({'error': 'Authentication required'}),
        );
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/meetings/events') {
        await _events(request.response);
        return;
      }
      final bytes = <int>[];
      await for (final chunk in request) {
        bytes.addAll(chunk);
        if (bytes.length > 65536) {
          throw const FormatException('Request exceeds 64 KiB');
        }
      }
      final body = bytes.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
      Object result;
      switch ('${request.method} ${request.uri.path}') {
        case 'GET /status':
          result = {
            'state': orchestrator.state.name,
            'activity': orchestrator.externalActivity,
            'model': transcription.modelLabel,
            'backend': transcription.computeBackend,
          };
        case 'GET /history':
          result = HistoryService.instance.entries
              .map((e) => e.toJson())
              .toList();
        case 'POST /dictations/start':
          if (!orchestrator.isAvailable) throw StateError('App is busy');
          await orchestrator.toggle(raw: body['raw'] == true);
          result = {'state': orchestrator.state.name};
        case 'POST /dictations/stop':
          if (orchestrator.state.name != 'recording') {
            throw StateError('No dictation is recording');
          }
          await orchestrator.toggle();
          result = {
            'state': orchestrator.state.name,
            'text': orchestrator.lastTranscript,
            'error': orchestrator.errorMessage,
          };
        case 'POST /dictations/cancel':
          await orchestrator.cancelDictation();
          result = {'cancelled': true};
        case 'POST /paste-last':
          await orchestrator.pasteLast();
          result = {'state': orchestrator.state.name};
        case 'POST /transcriptions':
          if (!orchestrator.isAvailable) throw StateError('App is busy');
          final path = body['path'] as String;
          orchestrator.externalActivity = 'API transcription';
          try {
            final wave = await PcmWave.open(path);
            final error = await transcription.ensureLoaded();
            if (error != null) throw StateError(error);
            final segments = <Map<String, dynamic>>[];
            final words = <Map<String, dynamic>>[];
            final chunks = <String>[];
            final timing = body['timestamps'] == true
                ? 'segment'
                : body['timestamps'] as String? ?? 'none';
            if (!['none', 'segment', 'word'].contains(timing)) {
              throw const FormatException(
                'timestamps must be none, segment or word',
              );
            }
            for (double start = 0; start < wave.seconds; start += 25) {
              final end = (start + 25).clamp(0, wave.seconds).toDouble();
              File? clip;
              try {
                TimedTranscript? timed;
                String text;
                if (transcription.supportsFileSlices) {
                  final first = (start * 16000).floor();
                  final last = (end * 16000).ceil().clamp(
                    first,
                    wave.dataBytes ~/ 2,
                  );
                  timed = await transcription.transcribeSlice(
                    path,
                    startSample: first,
                    sampleCount: last - first,
                    timestamps: timing,
                  );
                  text = timed.text;
                  if (timed.skippedSilence) continue;
                } else {
                  clip = File(
                    '${(await ProjectStorage.instance.directory('tmp')).path}/api-clip.wav',
                  );
                  if (!await wave.writeClip(clip, start, end)) continue;
                  timed = timing == 'none'
                      ? null
                      : await transcription.transcribeTimed(
                          clip.path,
                          timestamps: timing,
                        );
                  text =
                      timed?.text ?? await transcription.transcribe(clip.path);
                }
                if (timed != null) {
                  segments.addAll(timed.segments.map((v) => v.toJson(start)));
                  words.addAll(timed.words.map((v) => v.toJson(start)));
                }
                if (body['process'] == true) {
                  text = await orchestrator.processGlobalOutput(text);
                }
                if (body['instruction'] is String &&
                    (body['instruction'] as String).trim().isNotEmpty) {
                  text = await orchestrator.previewOutput(text, [
                    OutputStep(
                      OutputStepKind.instruction,
                      body['instruction'] as String,
                    ),
                  ]);
                }
                chunks.add(text);
              } finally {
                if (clip != null && await clip.exists()) await clip.delete();
              }
            }
            result = {
              'text': chunks.join(' '),
              'model': transcription.modelLabel,
              'backend': transcription.computeBackend,
              'duration': wave.seconds,
              if (timing != 'none') 'segments': segments,
              if (timing == 'word') 'words': words,
              'timestampPrecision': timing == 'none' ? 'none' : 'recognizer',
              'timestampsReferTo':
                  'original recognition before output processing',
            };
          } finally {
            orchestrator.externalActivity = null;
          }
        default:
          request.response.statusCode = 404;
          result = {'error': 'Unknown endpoint'};
      }
      request.response.write(jsonEncode(result));
    } catch (e) {
      request.response.statusCode = e is UnsupportedError
          ? 422
          : e is StateError
          ? 409
          : 400;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }

  Future<void> _events(HttpResponse response) async {
    response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final done = Completer<void>();
    Future<void> send(String value) async {
      try {
        response.write(value);
        await response.flush();
      } catch (_) {
        if (!done.isCompleted) done.complete();
      }
    }

    final subscription = orchestrator.meetings.completed.listen((id) {
      unawaited(
        send('event: meeting.transcribed\ndata: ${jsonEncode({'id': id})}\n\n'),
      );
    });
    final heartbeat = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(send(': keepalive\n\n')),
    );
    try {
      await send('retry: 1000\n\n');
      // Bound disconnected consumers; EventSource reconnects automatically.
      await Future.any([
        done.future,
        Future<void>.delayed(const Duration(minutes: 1)),
      ]);
    } finally {
      heartbeat.cancel();
      await subscription.cancel();
    }
  }
}
