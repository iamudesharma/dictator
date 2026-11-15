import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../settings/settings_service.dart';
import '../storage/project_storage.dart';
import 'custom_model_store.dart';
import 'gguf_catalog.dart';
import 'model_metadata.dart';
import 'native/native_speech_session.dart';
import 'stt_backend.dart';
import 'timed_transcript.dart';

class GgufTranscriptionBackend
    implements SttBackend, TimedSttBackend, SlicedSttBackend {
  final SettingsService settings;
  GgufTranscriptionBackend(this.settings);
  String? _path, _architecture;
  bool _loading = false;
  String _status = '';
  VoidCallback? onProgress;
  NativeSpeechSession? _native;
  String get nativeBackend => _native?.backend ?? 'unloaded';
  Future<TimedTranscript>? _decode;
  String? _selected;
  static Future<String> library() async {
    final frameworks =
        '${File(Platform.resolvedExecutable).parent.parent.path}/Frameworks';
    final bundled = File(
      '$frameworks/aurascribe-native/libtranscribe.0.4.1.dylib',
    );
    if (await bundled.exists()) return bundled.path;
    final local = File(
      '${ProjectStorage.instance.root.path}/tools/native/libtranscribe.0.4.1.dylib',
    );
    if (await local.exists()) return local.path;
    throw StateError(
      'Build the native speech library with tool/build_transcribe_ffi.sh, then rebuild AuraScribe.',
    );
  }

  @override
  bool get isLoaded => _native != null && _selected == settings.ggufModel;
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
      final nativeLibrary = await library();
      await _native?.close();
      _native = null;
      final catalog = ggufCatalog
          .where((m) => m.id == settings.ggufModel)
          .firstOrNull;
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
          },
        );
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
      _native = await NativeSpeechSession.open(
        nativeLibrary,
        _path!,
        prewarm: _architecture == 'parakeet',
      );
      _selected = settings.ggufModel;
      _status =
          'Ready • ${_native!.backend} • model retained until idle unload';
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
  Future<String> transcribe(String audioPath) async =>
      (await transcribeTimed(audioPath, timestamps: 'none')).text;

  @override
  Future<TimedTranscript> transcribeTimed(
    String audioPath, {
    required String timestamps,
  }) {
    if (_decode != null) throw StateError('Speech runtime is busy.');
    if (!['none', 'segment', 'word'].contains(timestamps)) {
      throw ArgumentError('Invalid timestamp kind.');
    }
    return _decode = _transcribe(audioPath, timestamps).whenComplete(() {
      _decode = null;
    });
  }

  @override
  Future<TimedTranscript> transcribeSlice(
    String path, {
    required int startSample,
    required int sampleCount,
    required String timestamps,
    required bool skipSilence,
  }) {
    if (_decode != null) throw StateError('Speech runtime is busy.');
    if (!['none', 'segment', 'word'].contains(timestamps)) {
      throw ArgumentError('Invalid timestamp kind.');
    }
    return _decode =
        _transcribe(
          path,
          timestamps,
          startSample: startSample,
          sampleCount: sampleCount,
          skipSilence: skipSilence,
        ).whenComplete(() {
          _decode = null;
        });
  }

  Future<TimedTranscript> _transcribe(
    String audioPath,
    String timestamps, {
    int? startSample,
    int? sampleCount,
    bool skipSilence = false,
  }) async {
    if (!isLoaded) {
      final error = await load();
      if (error != null) throw StateError(error);
    }
    var language = speechModelMetadata[settings.ggufModel]?.runtimeLanguage(
      settings.language,
    );
    if (!speechModelMetadata.containsKey(settings.ggufModel)) {
      language = settings.language == 'auto' ? null : settings.language;
    }
    if (settings.ggufModel == 'nemotron_3_5_asr' && language != null) {
      language = nemotronLocales[language] ?? language;
    }
    if (_architecture == 'whisper' && language == 'fil') language = 'tl';
    if (startSample != null && sampleCount != null) {
      return _native!.transcribeSlice(
        audioPath,
        language,
        settings.decoderVocabulary,
        _architecture ?? '',
        timestamps,
        startSample: startSample,
        sampleCount: sampleCount,
        skipSilence: skipSilence,
      );
    }
    return _native!.transcribe(
      audioPath,
      language,
      settings.decoderVocabulary,
      _architecture ?? '',
      timestamps,
    );
  }

  @override
  Future<void> dispose() async {
    try {
      await _decode;
    } catch (_) {}
    await _native?.close();
    _native = null;
    _path = null;
    _selected = null;
  }
}
