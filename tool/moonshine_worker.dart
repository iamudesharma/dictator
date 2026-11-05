// Standalone AOT worker. All model paths are supplied by AuraScribe's verified
// project storage; this executable never downloads files or opens a microphone.
import 'dart:convert';
import 'dart:io';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln(
        'Expected native-library directory, model directory and WAV path');
    exitCode = 64;
    return;
  }
  sherpa.OfflineRecognizer? recognizer;
  sherpa.OfflineStream? stream;
  try {
    final watch = Stopwatch()..start();
    sherpa.initBindings(args[0]);
    final folder = args[1];
    recognizer = sherpa.OfflineRecognizer(sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
            moonshine: sherpa.OfflineMoonshineModelConfig(
                preprocessor: '$folder/preprocess.onnx',
                encoder: '$folder/encode.int8.onnx',
                uncachedDecoder: '$folder/uncached_decode.int8.onnx',
                cachedDecoder: '$folder/cached_decode.int8.onnx'),
            tokens: '$folder/tokens.txt',
            numThreads: 2,
            provider: 'cpu',
            debug: false)));
    final loadMs = watch.elapsedMilliseconds;
    final wave = sherpa.readWave(args[2]);
    if (wave.sampleRate <= 0 || wave.samples.isEmpty) {
      throw const FormatException('Invalid WAV');
    }
    stream = recognizer.createStream();
    stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
    watch.reset();
    recognizer.decode(stream);
    stdout.writeln(jsonEncode({
      'text': recognizer.getResult(stream).text.trim(),
      'loadMs': loadMs,
      'decodeMs': watch.elapsedMilliseconds,
      'peakRssBytes': ProcessInfo.maxRss
    }));
  } catch (error) {
    stderr.writeln('Moonshine inference failed: $error');
    exitCode = 1;
  } finally {
    stream?.free();
    recognizer?.free();
  }
}
