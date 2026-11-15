import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../../audio/pcm_wave.dart';
import '../timed_transcript.dart';
import 'transcribe_bindings.g.dart';

/// One isolate owns one native model and session. Calls are serialized there;
/// no native pointer crosses an isolate boundary or a platform channel.
class NativeSpeechSession {
  final ReceivePort _replies = ReceivePort();
  final _pending = <int, Completer<Object?>>{};
  final _ready = Completer<SendPort>();
  Isolate? _isolate;
  SendPort? _commands;
  int _next = 0;
  bool _closed = false;
  String backend = '';

  NativeSpeechSession._() {
    _replies.listen((message) {
      if (message is SendPort) {
        _ready.complete(message);
        return;
      }
      if (message is Map) {
        final pending = _pending.remove(message['id']);
        if (message['error'] != null) {
          pending?.completeError(
            message['unsupported'] == true
                ? UnsupportedError(message['error'] as String)
                : StateError(message['error'] as String),
          );
        } else {
          pending?.complete(message['value']);
        }
      } else {
        final error = StateError('Native speech isolate exited: $message');
        if (!_ready.isCompleted) _ready.completeError(error);
        for (final p in _pending.values) {
          p.completeError(error);
        }
        _pending.clear();
        _commands = null;
      }
    });
  }
  static Future<NativeSpeechSession> open(
    String library,
    String model, {
    bool prewarm = false,
  }) async {
    final client = NativeSpeechSession._();
    try {
      client._isolate = await Isolate.spawn(
        _serve,
        [client._replies.sendPort, library],
        onError: client._replies.sendPort,
        errorsAreFatal: true,
      );
      client._commands = await client._ready.future;
      client.backend = await client._request('load', {
        'path': model,
        'prewarm': prewarm,
      }) as String;
      return client;
    } catch (_) {
      await client.close();
      rethrow;
    }
  }

  Future<Object?> _request(String operation, Map<String, Object?> data) {
    if (_closed || _commands == null) {
      return Future.error(StateError('Native speech session is closed'));
    }
    final id = _next++, result = Completer<Object?>();
    _pending[id] = result;
    _commands!.send({'id': id, 'operation': operation, ...data});
    return result.future;
  }

  Future<TimedTranscript> transcribe(
    String path,
    String? language,
    String vocabulary,
    String architecture,
    String timestamps,
  ) async {
    final wave = await PcmWave.open(path);
    final text = <String>[],
        segments = <TranscriptSpan>[],
        words = <TranscriptSpan>[];
    final total = wave.dataBytes ~/ 2;
    for (var offset = 0; offset < total; offset += 400000) {
      final count = (total - offset).clamp(0, 400000);
      final value = await _request('run', {
        'path': path,
        'start': offset,
        'count': count,
        'language': language,
        'vocabulary': vocabulary,
        'architecture': architecture,
        'timestamps': timestamps,
      }) as Map;
      backend = value['backend'] as String;
      if ((value['text'] as String).isNotEmpty) {
        text.add(value['text'] as String);
      }
      void append(String key, List<TranscriptSpan> target) {
        for (final row in value[key] as List) {
          target.add(
            TranscriptSpan(
              (row[0] as double) + offset / 16000,
              (row[1] as double) + offset / 16000,
              row[2] as String,
            ),
          );
        }
      }

      append('segments', segments);
      append('words', words);
    }
    return TimedTranscript(text.join(' '), segments: segments, words: words);
  }

  Future<TimedTranscript> transcribeSlice(
    String path,
    String? language,
    String vocabulary,
    String architecture,
    String timestamps, {
    required int startSample,
    required int sampleCount,
    required bool skipSilence,
  }) async {
    final value = await _request('run', {
      'path': path,
      'start': startSample,
      'count': sampleCount,
      'language': language,
      'vocabulary': vocabulary,
      'architecture': architecture,
      'timestamps': timestamps,
      'skipSilence': skipSilence,
    }) as Map;
    backend = value['backend'] as String;
    List<TranscriptSpan> spans(String key) => [
      for (final row in value[key] as List)
        TranscriptSpan(row[0] as double, row[1] as double, row[2] as String),
    ];
    return TimedTranscript(
      value['text'] as String,
      segments: spans('segments'),
      words: spans('words'),
      skippedSilence: value['skippedSilence'] == true,
    );
  }

  Future<void> close() async {
    if (_closed) return;
    try {
      if (_commands != null) await _request('close', {});
    } finally {
      _closed = true;
      _isolate?.kill(priority: Isolate.beforeNextEvent);
      _replies.close();
    }
  }
}

Future<void> _serve(List<Object> args) async {
  final reply = args[0] as SendPort;
  final commands = ReceivePort();
  reply.send(commands.sendPort);
  _Engine? engine;
  await for (final message in commands) {
    final command = message as Map;
    try {
      Object? value;
      switch (command['operation']) {
        case 'load':
          engine = _Engine(args[1] as String);
          value = engine.load(
            command['path'] as String,
            prewarm: command['prewarm'] == true,
          );
        case 'run':
          value = await engine!.run(command);
        case 'close':
          engine?.close();
          engine = null;
      }
      reply.send({'id': command['id'], 'value': value});
    } catch (error) {
      reply.send({
        'id': command['id'],
        'error': error.toString(),
        'unsupported': error is UnsupportedError,
      });
    }
    if (command['operation'] == 'close') {
      commands.close();
      break;
    }
  }
}

class _Engine {
  final TranscribeBindings api;
  final TranscribeBindings audioApi;
  Pointer<transcribe_model> model = nullptr;
  Pointer<transcribe_session> session = nullptr;
  _Engine(String library)
    : api = TranscribeBindings(DynamicLibrary.open(library)),
      audioApi = TranscribeBindings(
        DynamicLibrary.open(
          '${File(library).parent.path}/libaurascribe_audio.dylib',
        ),
      ) {
    final version = api.transcribe_version().cast<Utf8>().toDartString();
    if (version != '0.4.1') {
      throw StateError('Native speech ABI mismatch: $version');
    }
    _check(api.transcribe_init_backends_default());
  }
  void _check(transcribe_status status) {
    if (status != transcribe_status.TRANSCRIBE_OK) {
      throw StateError(
        'Native speech: ${api.transcribe_status_string(status.value).cast<Utf8>().toDartString()} ($status)',
      );
    }
  }

  String _modelPath = '';
  bool _cpu = false;
  String load(String path, {bool forceCpu = false, bool prewarm = false}) =>
      using((arena) {
        _modelPath = path;
        _cpu = forceCpu;
        final params = arena<transcribe_model_load_params>();
        api.transcribe_model_load_params_init(params);
        params.ref.backendAsInt = forceCpu
            ? transcribe_backend_request.TRANSCRIBE_BACKEND_CPU.value
            : transcribe_backend_request.TRANSCRIBE_BACKEND_METAL.value;
        final out = arena<Pointer<transcribe_model>>();
        var code = api.transcribe_model_load_file(
          path.toNativeUtf8(allocator: arena).cast(),
          params,
          out,
        );
        if (code == transcribe_status.TRANSCRIBE_ERR_BACKEND && !forceCpu) {
          _cpu = true;
          params.ref.backendAsInt =
              transcribe_backend_request.TRANSCRIBE_BACKEND_CPU.value;
          code = api.transcribe_model_load_file(
            path.toNativeUtf8(allocator: arena).cast(),
            params,
            out,
          );
        }
        _check(code);
        model = out.value;
        try {
          final settings = arena<transcribe_session_params>();
          api.transcribe_session_params_init(settings);
          settings.ref.n_threads = 2;
          settings.ref.n_ctx = 2048;
          final context = arena<Pointer<transcribe_session>>();
          _check(api.transcribe_session_init(model, settings, context));
          session = context.value;
          if (prewarm) {
            final silence = arena<Float>(8000);
            silence.asTypedList(8000).fillRange(0, 8000, 0);
            final run = arena<transcribe_run_params>();
            api.transcribe_run_params_init(run);
            // Prime encoder/Metal pipelines while the microphone is already
            // capturing. A rejected warm-up is harmless; real inference retains
            // its normal status handling and CPU backend recovery.
            api.transcribe_run(session, silence, 8000, run);
          }
          return api
              .transcribe_model_backend(model)
              .cast<Utf8>()
              .toDartString();
        } catch (_) {
          close();
          rethrow;
        }
      });
  Future<Map<String, Object>> run(Map command) async {
    final wave = await PcmWave.open(command['path'] as String);
    final start = command['start'] as int, count = command['count'] as int;
    if (start < 0 ||
        count <= 0 ||
        count > 400000 ||
        (start + count) * 2 > wave.dataBytes) {
      throw const FormatException('Invalid native audio slice');
    }
    return using<Map<String, Object>>((arena) {
      final samples = arena<Float>(count);
      final read = audioApi.aurascribe_pcm_read(
        wave.path.toNativeUtf8(allocator: arena).cast(),
        wave.dataOffset + start * 2,
        count,
        samples,
        command['skipSilence'] == true ? 1 : 0,
      );
      if (read < 0) {
        throw const FormatException('Incomplete or unreadable PCM data');
      }
      if (read == 1) {
        return <String, Object>{
          'skippedSilence': true,
          'text': '',
          'segments': <List<Object>>[],
          'words': <List<Object>>[],
          'backend': api
              .transcribe_model_backend(model)
              .cast<Utf8>()
              .toDartString(),
        };
      }
      final params = arena<transcribe_run_params>();
      api.transcribe_run_params_init(params);
      final requested = command['timestamps'] as String;
      params.ref.timestampsAsInt = switch (requested) {
        'segment' => 2,
        'word' => 3,
        _ => 0,
      };
      final language = command['language'] as String?;
      if (language != null) {
        params.ref.language = language.toNativeUtf8(allocator: arena).cast();
      }
      final terms = (command['vocabulary'] as String)
          .split('\n')
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .toList();
      if (command['architecture'] == 'parakeet' && terms.isNotEmpty) {
        final vocabulary = arena<Pointer<Char>>(terms.length);
        for (var i = 0; i < terms.length; i++) {
          vocabulary[i] = terms[i].toNativeUtf8(allocator: arena).cast();
        }
        params.ref.vocabulary = vocabulary;
        params.ref.n_vocabulary = terms.length;
      }
      if (command['architecture'] == 'whisper' && terms.isNotEmpty) {
        params.ref.prompt = terms
            .join(', ')
            .toNativeUtf8(allocator: arena)
            .cast();
      }
      var code = api.transcribe_run(session, samples, count, params);
      if (code == transcribe_status.TRANSCRIBE_ERR_BACKEND && !_cpu) {
        close();
        load(_modelPath, forceCpu: true);
        code = api.transcribe_run(session, samples, count, params);
      }
      _check(code);
      final text = api
          .transcribe_full_text(session)
          .cast<Utf8>()
          .toDartString()
          .trim();
      final segments = <List<Object>>[], words = <List<Object>>[];
      final precision = api.transcribe_returned_timestamp_kind(session).value;
      if (precision >= 2) {
        final row = arena<transcribe_segment>();
        api.transcribe_segment_init(row);
        for (var i = 0; i < api.transcribe_n_segments(session); i++) {
          _check(api.transcribe_get_segment(session, i, row));
          segments.add([
            row.ref.t0_ms / 1000,
            row.ref.t1_ms / 1000,
            row.ref.text.cast<Utf8>().toDartString(),
          ]);
        }
      }
      if (precision >= 3) {
        final row = arena<transcribe_word>();
        api.transcribe_word_init(row);
        for (var i = 0; i < api.transcribe_n_words(session); i++) {
          _check(api.transcribe_get_word(session, i, row));
          words.add([
            row.ref.t0_ms / 1000,
            row.ref.t1_ms / 1000,
            row.ref.text.cast<Utf8>().toDartString(),
          ]);
        }
      }
      if (text.isNotEmpty &&
          (requested == 'word' && words.isEmpty ||
              requested == 'segment' && segments.isEmpty)) {
        throw UnsupportedError(
          'This model did not return $requested timestamps.',
        );
      }
      return {
        'text': text,
        'segments': segments,
        'words': words,
        'backend': api
            .transcribe_model_backend(model)
            .cast<Utf8>()
            .toDartString(),
      };
    });
  }

  void close() {
    if (session != nullptr) {
      api.transcribe_session_free(session);
      session = nullptr;
    }
    if (model != nullptr) {
      api.transcribe_model_free(model);
      model = nullptr;
    }
  }
}
