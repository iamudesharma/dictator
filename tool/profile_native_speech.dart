// Opt-in native policy probe. Uses already-installed project-local fixtures.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:voice_to_text/audio/pcm_wave.dart';
import 'package:voice_to_text/transcription/native/transcribe_bindings.g.dart';

Future<void> main(List<String> args) async {
  final threads = int.parse(args[0]), rotate = args[1] == 'rotate';
  final iterations = int.parse(args[2]);
  if (args.length > 3 && args[3] == 'interactive') {
    final setQos = DynamicLibrary.process()
        .lookupFunction<Int32 Function(Uint32, Int32), int Function(int, int)>(
          'pthread_set_qos_class_self_np',
        );
    if (setQos(0x21, 0) != 0) throw StateError('QoS failed');
  }
  final root = Directory.current.path;
  final source = '$root/.aurascribe/benchmarks/metal-comparison/sample.wav';
  final reference = File(
    '$root/.aurascribe/benchmarks/metal-comparison/reference.txt',
  ).readAsStringSync().trim();
  final wave = await PcmWave.open(source);
  final memoryLibrary = File(
    '$root/.aurascribe/tools/libmetal-memory-probe.dylib',
  );
  final metalBytes = memoryLibrary.existsSync()
      ? DynamicLibrary.open(memoryLibrary.path)
            .lookupFunction<Uint64 Function(), int Function()>(
              'aurascribe_profile_metal_bytes',
            )
      : null;
  final api = TranscribeBindings(
    DynamicLibrary.open(
      '$root/.aurascribe/tools/native/libtranscribe.0.4.1.dylib',
    ),
  );
  final audio = TranscribeBindings(
    DynamicLibrary.open(
      '$root/.aurascribe/tools/native/libaurascribe_audio.dylib',
    ),
  );
  void check(transcribe_status status) {
    if (status != transcribe_status.TRANSCRIBE_OK) throw StateError('$status');
  }

  using((arena) {
    check(api.transcribe_init_backends_default());
    final params = arena<transcribe_model_load_params>();
    api.transcribe_model_load_params_init(params);
    params.ref.backendAsInt =
        transcribe_backend_request.TRANSCRIBE_BACKEND_METAL.value;
    final modelOut = arena<Pointer<transcribe_model>>();
    check(
      api.transcribe_model_load_file(
        '$root/.aurascribe/models/gguf/parakeet_unified_english/parakeet-unified-en-0.6b-Q8_0.gguf'
            .toNativeUtf8(allocator: arena)
            .cast(),
        params,
        modelOut,
      ),
    );
    final model = modelOut.value;
    Pointer<transcribe_session> session = nullptr;
    final options = arena<transcribe_session_params>();
    api.transcribe_session_params_init(options);
    options.ref.n_threads = threads;
    options.ref.n_ctx = 2048;
    final sessionOut = arena<Pointer<transcribe_session>>();
    final run = arena<transcribe_run_params>();
    api.transcribe_run_params_init(run);
    run.ref.language = 'en'.toNativeUtf8(allocator: arena).cast();
    final count = wave.dataBytes ~/ 2,
        samples = arena<Float>(wave.dataBytes ~/ 2);
    if (audio.aurascribe_pcm_read(
          source.toNativeUtf8(allocator: arena).cast(),
          wave.dataOffset,
          count,
          samples,
          0,
        ) !=
        0) {
      throw StateError('PCM failed');
    }
    final modelBytes = metalBytes?.call();
    final timings = <double>[];
    try {
      for (var i = 0; i < iterations; i++) {
        final watch = Stopwatch()..start();
        if (session == nullptr) {
          check(api.transcribe_session_init(model, options, sessionOut));
          session = sessionOut.value;
        }
        check(api.transcribe_run(session, samples, count, run));
        final text = api
            .transcribe_full_text(session)
            .cast<Utf8>()
            .toDartString()
            .trim();
        if (text != reference) throw StateError('Transcription changed');
        if (rotate) {
          api.transcribe_session_free(session);
          session = nullptr;
        }
        timings.add(watch.elapsedMicroseconds / 1e6);
      }
      stdout.writeln(
        jsonEncode({
          'threads': threads,
          'rotate': rotate,
          'seconds': timings,
          'peakRssBytes': ProcessInfo.maxRss,
          'currentRssBytes': ProcessInfo.currentRss,
          'pid': pid,
          'modelMetalBytes': modelBytes,
          'afterRunMetalBytes': metalBytes?.call(),
          'allTextMatches': true,
        }),
      );
      if (args.contains('hold')) stdin.readLineSync();
    } finally {
      if (session != nullptr) api.transcribe_session_free(session);
      api.transcribe_model_free(model);
    }
  });
}
