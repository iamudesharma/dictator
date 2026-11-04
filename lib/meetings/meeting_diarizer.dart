import 'dart:ffi';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
// The public 1.13.2 wrapper leaks its temporary PCM allocation. Own the C call
// and every allocation here; do not patch the shared package checkout.
// ignore: implementation_imports
import 'package:sherpa_onnx/src/sherpa_onnx_bindings.dart';
import '../storage/project_storage.dart';

class SpeakerSpan {
  final double start, end;
  final int speaker;
  const SpeakerSpan(this.start, this.end, this.speaker);
}

class MeetingDiarizer {
  static const segmentationRevision =
      '9403a6902bb58e3d5ae8c7e77c3422de279db2e0';
  static const embeddingRevision = '0743f301363dec56491a490f6d6cbc9d67f9a3bf';
  Future<List<SpeakerSpan>> process(String wav, {int speakers = -1}) async {
    final segmentation = await ProjectStorage.instance.download(
        folder: 'diarization',
        name: 'segmentation.int8.onnx',
        url: Uri.parse(
            'https://huggingface.co/csukuangfj/sherpa-onnx-pyannote-segmentation-3-0/resolve/$segmentationRevision/model.int8.onnx'),
        minBytes: 1000000);
    final embedding = await ProjectStorage.instance.download(
        folder: 'diarization',
        name: 'titanet-small.onnx',
        url: Uri.parse(
            'https://huggingface.co/csukuangfj/speaker-embedding-models/resolve/$embeddingRevision/nemo_en_titanet_small.onnx'),
        minBytes: 1000000);
    return Isolate.run(
        () => _runDiarizer(wav, segmentation, embedding, speakers));
  }
}

List<SpeakerSpan> _runDiarizer(
    String wav, String segmentation, String embedding, int speakers) {
  const library = String.fromEnvironment('SHERPA_LIBRARY_DIR');
  sherpa.initBindings(library.isEmpty ? null : library);
  final diarizer = sherpa.OfflineSpeakerDiarization(
      sherpa.OfflineSpeakerDiarizationConfig(
          segmentation: sherpa.OfflineSpeakerSegmentationModelConfig(
              pyannote: sherpa.OfflineSpeakerSegmentationPyannoteModelConfig(
                  model: segmentation),
              numThreads: 2,
              debug: false),
          embedding: sherpa.SpeakerEmbeddingExtractorConfig(
              model: embedding, numThreads: 2, debug: false),
          clustering: sherpa.FastClusteringConfig(
              numClusters: speakers, threshold: 0.5)));
  Pointer<SherpaOnnxWave> wave = nullptr;
  Pointer<SherpaOnnxOfflineSpeakerDiarizationResult> result = nullptr;
  Pointer<SherpaOnnxOfflineSpeakerDiarizationSegment> segments = nullptr;
  try {
    final filename = wav.toNativeUtf8();
    try {
      wave = SherpaOnnxBindings.readWave!.call(filename);
    } finally {
      calloc.free(filename);
    }
    if (wave == nullptr ||
        wave.ref.sampleRate != diarizer.sampleRate ||
        wave.ref.numSamples == 0) {
      throw StateError('Diarization requires a nonempty 16 kHz WAV.');
    }
    // Use the native reader's PCM allocation directly; avoid a full Dart float
    // copy plus a second native float copy for an hour-long meeting.
    result = SherpaOnnxBindings.sherpaOnnxOfflineSpeakerDiarizationProcess!
        .call(diarizer.ptr, wave.ref.samples, wave.ref.numSamples);
    if (result == nullptr) throw StateError('Speaker diarization failed.');
    final count = SherpaOnnxBindings
        .sherpaOnnxOfflineSpeakerDiarizationResultGetNumSegments!
        .call(result);
    segments = SherpaOnnxBindings
        .sherpaOnnxOfflineSpeakerDiarizationResultSortByStartTime!
        .call(result);
    if (segments == nullptr) return [];
    return [
      for (var i = 0; i < count; i++)
        SpeakerSpan(segments[i].start, segments[i].end, segments[i].speaker)
    ];
  } finally {
    if (segments != nullptr) {
      SherpaOnnxBindings.sherpaOnnxOfflineSpeakerDiarizationDestroySegment!
          .call(segments);
    }
    if (result != nullptr) {
      SherpaOnnxBindings.sherpaOnnxOfflineSpeakerDiarizationDestroyResult!
          .call(result);
    }
    if (wave != nullptr) SherpaOnnxBindings.freeWave!.call(wave);
    diarizer.free();
  }
}
