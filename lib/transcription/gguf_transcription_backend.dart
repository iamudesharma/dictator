import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../settings/settings_service.dart';
import '../storage/project_storage.dart';
import 'custom_model_store.dart';
import 'gguf_catalog.dart';
import 'stt_backend.dart';

class GgufTranscriptionBackend implements SttBackend {
  final SettingsService settings;
  GgufTranscriptionBackend(this.settings);
  String? _path, _architecture;
  bool _loading = false;
  String _status = '';
  VoidCallback? onProgress;
  Process? _process;
  Future<String>? _decode;
  String? _selected;
  static Future<String> executable() async {
    final bundled = File(
        '${File(Platform.resolvedExecutable).parent.parent.path}/Resources/aurascribe-transcribe');
    if (await bundled.exists()) return bundled.path;
    final local = File(
        '${ProjectStorage.instance.root.path}/tools/aurascribe-transcribe');
    if (await local.exists()) return local.path;
    throw StateError(
        'Build the speech runtime with tool/build_transcribe_runtime.sh, then rebuild the Mac app.');
  }

  @override
  bool get isLoaded => _path != null && _selected == settings.ggufModel;
  @override
  bool get isLoading => _loading;
  @override
  String get modelLabel =>
      ggufCatalog.where((m) => m.id == settings.ggufModel).firstOrNull?.name ??
      'Imported speech model';
  @override
  String get statusMessage => _status;
  @override
  Future<String?> load() async {
    if (isLoaded) return null;
    _loading = true;
    onProgress?.call();
    try {
      await executable();
      final catalog =
          ggufCatalog.where((m) => m.id == settings.ggufModel).firstOrNull;
      if (catalog != null) {
        _path = await ProjectStorage.instance.download(
            folder: 'gguf/${catalog.id}',
            name: catalog.filename,
            url: catalog.url,
            expectedSha256: catalog.sha256,
            expectedBytes: catalog.bytes,
            onProgress: (value) {
              _status = value;
              onProgress?.call();
            });
        _architecture = catalog.architecture;
      } else {
        final imported = (await CustomModelStore().read())
            .where((m) => m.id == settings.ggufModel)
            .firstOrNull;
        if (imported == null) {
          throw StateError('The selected imported model is missing.');
        }
        _path = await CustomModelStore().path(imported);
        _architecture = imported.architecture;
        if (!await File(_path!).exists()) {
          throw StateError('The imported model file is missing.');
        }
      }
      if (!(_path!.endsWith('.bin'))) await GgufHeader.inspect(File(_path!));
      _selected = settings.ggufModel;
      _status = 'Prepared for local inference';
      return null;
    } catch (e) {
      _path = null;
      _status = e.toString();
      return _status;
    } finally {
      _loading = false;
      onProgress?.call();
    }
  }

  @override
  Future<String> transcribe(String audioPath) {
    if (_decode != null) throw StateError('Speech runtime is busy.');
    return _decode = _transcribe(audioPath).whenComplete(() {
      _decode = null;
    });
  }

  Future<String> _transcribe(String audioPath) async {
    if (!isLoaded) {
      final error = await load();
      if (error != null) throw StateError(error);
    }
    final args = [
      '-m',
      _path!,
      '-q',
      '--threads',
      '2',
      '--backend',
      'cpu',
      '-l',
      settings.language,
      '--n-ctx',
      '2048'
    ];
    if (settings.decoderVocabulary.trim().isNotEmpty) {
      if (_architecture == 'parakeet') {
        args.addAll([
          '--vocabulary',
          settings.decoderVocabulary
              .split('\n')
              .where((s) => s.trim().isNotEmpty)
              .join(',')
        ]);
      }
      if (_architecture == 'whisper') {
        args.addAll([
          '--initial-prompt',
          settings.decoderVocabulary.replaceAll('\n', ', ')
        ]);
      }
    }
    final resultFile = File(
        '${(await ProjectStorage.instance.directory('tmp')).path}/runtime-result-${DateTime.now().microsecondsSinceEpoch}.txt');
    args.addAll(['-o', resultFile.path, audioPath]);
    final process = _process = await Process.start(await executable(), args);
    final output = process.stdout.transform(utf8.decoder).join();
    final error = process.stderr.transform(utf8.decoder).join();
    try {
      final code = await process.exitCode.timeout(const Duration(minutes: 5));
      final result = await output, diagnostic = await error;
      if (code != 0) {
        throw StateError(
            'Speech runtime exited $code: ${diagnostic.length > 1200 ? diagnostic.substring(diagnostic.length - 1200) : diagnostic}');
      }
      if (!await resultFile.exists()) {
        throw StateError('Speech runtime returned no transcript file: $result');
      }
      return (await resultFile.readAsString()).trim();
    } finally {
      process.kill();
      if (await resultFile.exists()) await resultFile.delete();
      _process = null;
    }
  }

  @override
  Future<void> dispose() async {
    _process?.kill();
    try {
      await _decode;
    } catch (_) {}
    _path = null;
    _selected = null;
  }
}
