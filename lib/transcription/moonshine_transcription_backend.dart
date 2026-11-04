import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import '../storage/project_storage.dart';
import 'stt_backend.dart';

/// Quantized Moonshine Tiny v1, using sherpa's documented CPU pipeline.
/// This is clip-based recognition, not the separate Moonshine Streaming model.
class MoonshineTranscriptionBackend implements SttBackend {
  MoonshineTranscriptionBackend({this.releaseAfterClip = false});
  final bool releaseAfterClip;
  Map<String, String>? _preparedPaths;
  String? _helper, _library;
  Process? _process;

  Future<String?> _helperPath() async {
    final resources = File(Platform.resolvedExecutable).parent.parent;
    final bundled = File('${resources.path}/Resources/aurascribe-moonshine');
    final local =
        File('${ProjectStorage.instance.root.path}/tools/aurascribe-moonshine');
    if (await bundled.exists()) return bundled.path;
    if (await local.exists()) return local.path;
    return null;
  }

  static const revision = 'bf2b762c076d8ea61e2af0b3851c9564fb77552e';
  static const baseUrl =
      'https://huggingface.co/csukuangfj/sherpa-onnx-moonshine-tiny-en-int8/resolve/$revision';
  Isolate? _worker;
  SendPort? _port;
  bool _loading = false;
  String _status = '';
  VoidCallback? onProgress;
  @override
  bool get isLoaded => _port != null || _preparedPaths != null;
  @override
  bool get isLoading => _loading;
  @override
  String get modelLabel => 'Moonshine Tiny INT8';
  @override
  String get statusMessage => _status;

  @override
  Future<String?> load() async {
    if (isLoaded) return null;
    _loading = true;
    try {
      final paths = <String, String>{};
      for (final name in [
        'preprocess.onnx',
        'encode.int8.onnx',
        'uncached_decode.int8.onnx',
        'cached_decode.int8.onnx',
        'tokens.txt',
        'LICENSE'
      ]) {
        paths[name] = await ProjectStorage.instance.download(
            folder: 'moonshine_tiny_int8',
            name: name,
            url: Uri.parse('$baseUrl/$name'),
            onProgress: (value) {
              _status = value;
              onProgress?.call();
            });
      }
      if (releaseAfterClip) {
        _helper = await _helperPath();
        if (_helper != null) {
          _preparedPaths = paths;
          const configured = String.fromEnvironment('SHERPA_LIBRARY_DIR');
          _library = configured.isNotEmpty
              ? configured
              : '${File(Platform.resolvedExecutable).parent.parent.path}/Frameworks';
          if (!await File('$_library/libsherpa-onnx-c-api.dylib').exists()) {
            _library =
                '${ProjectStorage.instance.project.path}/build/macos/Build/Products/Release/AuraScribe.app/Contents/Frameworks';
          }
          _status = 'Ready • model memory released after each clip';
          return null;
        }
      }
      _status = 'Loading Moonshine on CPU…';
      onProgress?.call();
      final ready = ReceivePort();
      try {
        _worker = await Isolate.spawn(_moonshineWorker, [
          ready.sendPort,
          paths,
          const String.fromEnvironment('SHERPA_LIBRARY_DIR')
        ]);
        final response = await ready.first.timeout(const Duration(minutes: 2));
        if (response is! SendPort) throw StateError(response.toString());
        _port = response;
      } catch (_) {
        _worker?.kill(priority: Isolate.immediate);
        _worker = null;
        rethrow;
      } finally {
        ready.close();
      }
      _status = '';
      return null;
    } catch (e) {
      _status = 'Moonshine could not load: $e';
      return _status;
    } finally {
      _loading = false;
      onProgress?.call();
    }
  }

  @override
  Future<String> transcribe(String audioPath) async {
    if (_preparedPaths != null) return _transcribeInProcess(audioPath);
    final port = _port;
    if (port == null) throw StateError('Moonshine is not loaded');
    final reply = ReceivePort();
    try {
      port.send([audioPath, reply.sendPort]);
      final response = await reply.first.timeout(const Duration(minutes: 2));
      if (response is Map && response['error'] != null) {
        throw StateError(response['error'] as String);
      }
      return response as String;
    } finally {
      reply.close();
      final file = File(audioPath);
      if (await file.exists()) await file.delete();
    }
  }

  Future<String> _transcribeInProcess(String audioPath) async {
    if (_process != null) throw StateError('Moonshine is busy');
    final folder = File(_preparedPaths!['tokens.txt']!).parent.path;
    final process = _process =
        await Process.start(_helper!, [_library!, folder, audioPath]);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    try {
      final code = await process.exitCode.timeout(const Duration(minutes: 2));
      final text = await output;
      final diagnostic = await errors;
      if (code != 0) {
        throw StateError(
            'Moonshine worker exited $code: ${diagnostic.length > 800 ? diagnostic.substring(0, 800) : diagnostic}');
      }
      return (jsonDecode(text) as Map)['text'] as String;
    } finally {
      process.kill();
      await process.exitCode;
      await Future.wait([output, errors]);
      _process = null;
      final file = File(audioPath);
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<void> dispose() async {
    _preparedPaths = null;
    final process = _process;
    if (process != null) {
      process.kill();
      await process.exitCode;
    }
    final port = _port;
    _port = null;
    if (port != null) {
      final done = ReceivePort();
      try {
        port.send([null, done.sendPort]);
        await done.first.timeout(const Duration(seconds: 10));
      } finally {
        done.close();
        _worker?.kill(priority: Isolate.immediate);
        _worker = null;
      }
    }
  }
}

/// Native decoding runs away from Flutter's UI isolate. Requests are serialized
/// so partial and final decodes cannot access a recognizer concurrently.
void _moonshineWorker(List<Object> args) async {
  final ready = args[0] as SendPort;
  final paths = args[1] as Map<String, String>;
  final library = args[2] as String;
  sherpa.OfflineRecognizer? recognizer;
  final commands = ReceivePort();
  SendPort? shutdown;
  try {
    sherpa.initBindings(library.isEmpty ? null : library);
    recognizer = sherpa.OfflineRecognizer(sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
            moonshine: sherpa.OfflineMoonshineModelConfig(
                preprocessor: paths['preprocess.onnx']!,
                encoder: paths['encode.int8.onnx']!,
                uncachedDecoder: paths['uncached_decode.int8.onnx']!,
                cachedDecoder: paths['cached_decode.int8.onnx']!),
            tokens: paths['tokens.txt']!,
            numThreads: 2,
            provider: 'cpu',
            debug: false)));
    ready.send(commands.sendPort);
    await for (final message in commands) {
      final request = message as List;
      final reply = request[1] as SendPort;
      if (request[0] == null) {
        shutdown = reply;
        break;
      }
      final stream = recognizer.createStream();
      try {
        final wave = sherpa.readWave(request[0] as String);
        if (wave.sampleRate <= 0 || wave.samples.isEmpty) {
          throw StateError('Invalid or empty WAV file');
        }
        stream.acceptWaveform(
            samples: wave.samples, sampleRate: wave.sampleRate);
        recognizer.decode(stream);
        reply.send(recognizer.getResult(stream).text.trim());
      } catch (e) {
        reply.send({'error': e.toString()});
      } finally {
        stream.free();
      }
    }
  } catch (e) {
    ready.send(e.toString());
  } finally {
    recognizer?.free();
    commands.close();
    shutdown?.send(true);
  }
}
