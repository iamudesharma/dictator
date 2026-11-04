import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_to_text/storage/project_storage.dart';
import 'package:voice_to_text/meetings/meeting_diarizer.dart';

void main() {
  test('native diarization identifies multiple speakers in public fixture',
      () async {
    await ProjectStorage.initialize(projectPath: Directory.current.path);
    final wav = await ProjectStorage.instance.download(
        folder: 'benchmark-fixtures',
        name: 'four-speakers.wav',
        url: Uri.parse(
            'https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/0-four-speakers-zh.wav'));
    final spans = await MeetingDiarizer().process(wav, speakers: 4);
    expect(spans, isNotEmpty);
    expect(spans.map((s) => s.speaker).toSet().length, greaterThanOrEqualTo(2));
    expect(spans.every((s) => s.start >= 0 && s.end > s.start), isTrue);
    // ignore: avoid_print
    print(
        'Native diarization: ${spans.length} segments, ${spans.map((s) => s.speaker).toSet().length} speakers');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
