import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_to_text/audio/pause_compactor.dart';
import 'package:voice_to_text/audio/pcm_wave.dart';
import 'package:voice_to_text/output/spoken_text.dart';
import 'package:voice_to_text/output/output_pipeline.dart';
import 'package:voice_to_text/settings/settings_search.dart';
import 'package:voice_to_text/shared/wav_header_helper.dart';
import 'package:voice_to_text/transcription/gguf_catalog.dart';
import 'package:voice_to_text/transcription/model_metadata.dart';
import 'package:voice_to_text/transcription/timed_transcript.dart';

void main() {
  test('catalog languages cover every pinned model and preserve hint semantics',
      () {
    expect(ggufCatalog.every((m) => speechModelMetadata.containsKey(m.id)),
        isTrue);
    expect(speechModelMetadata['granite_speech_5']!.supports('ja'), isTrue);
    expect(
        speechModelMetadata['granite_speech_5']!.runtimeLanguage('ja'), isNull);
    expect(speechModelMetadata['parakeet_v3']!.runtimeLanguage('de'), isNull);
    expect(speechModelMetadata['ivrit_whisper']!.runtimeLanguage('en'), 'he');
    expect(speechModelMetadata['qwen']!.runtimeLanguage('fil'), 'fil');
    expect(speechModelMetadata['qwen']!.benchmark!['metric'], 'CER');
    expect(speechModelMetadata['orukeet']!.benchmark!['value'], 1.86);
    expect(speechLanguages.length, greaterThan(90));
  });
  test(
      'timing parser preserves recognizer boundaries and rejects missing timing',
      () {
    const output =
        'text: hello world\nsegments: 1\n  [  0.20 ->  1.50] hello world\nwords: 2\n  [  0.20 ->  0.65] hello\n  [  0.80 ->  1.50] world\ntimings: 12 ms\n';
    final result = TimedTranscript.fromRuntime('hello world', output, 'word');
    expect(result.segments.single.start, .2);
    expect(result.words.last.toJson(25)['end'], 26.5);
    expect(() => TimedTranscript.fromRuntime('hello', 'text: hello', 'word'),
        throwsUnsupportedError);
  });
  test(
      'spoken commands retain paragraph breaks, punctuation and word boundaries',
      () {
    expect(
        SpokenText.apply(
            'um Hello comma world new paragraph open quote yes close quote',
            formatting: true,
            symbols: true,
            fillers: true),
        'Hello, world\n\n“yes”');
    expect(
        SpokenText.apply('hello hashtag release underscore one', symbols: true),
        'hello #release_one');
    expect(
        SpokenText.apply('umbrella uh-huh', fillers: true), 'umbrella uh-huh');
    expect(SpokenText.apply('new line', formatting: true, language: 'fr'),
        'new line');
  });
  test('profiles preserve independent speech and output options', () {
    const profile = OutputProfile('mail', [],
        speechModel: 'apple', language: 'fr', includeDefault: false);
    final restored = OutputProfile.fromJson(profile.toJson());
    expect(restored.speechModel, 'apple');
    expect(restored.language, 'fr');
    expect(restored.includeDefault, false);
    expect(searchSettings('clipboard').map((e) => e.page), contains(2));
    expect(searchSettings('mouse').map((e) => e.page), contains(0));
  });
  test('pause compaction keeps speech and short pauses, bounds long silence',
      () async {
    final directory = await Directory.systemTemp.createTemp('aura-pauses-');
    addTearDown(() => directory.delete(recursive: true));
    final pcm = Uint8List(32000 * 5);
    final view = ByteData.sublistView(pcm);
    // One second of speech, three seconds of silence, one second of speech.
    for (var i = 0; i < pcm.length; i += 2) {
      if (i < 32000 || i >= 128000) {
        view.setInt16(i, i % 4 == 0 ? 2000 : -2000, Endian.little);
      }
    }
    final source = File('${directory.path}/source.wav');
    await source
        .writeAsBytes([...WavHeaderHelper.buildHeader(pcm.length), ...pcm]);
    final output = File('${directory.path}/output.wav');
    await compactPauses(source.path, output);
    final result = await PcmWave.open(output.path);
    expect(result.seconds, closeTo(2.4, .02));
    expect((await PcmWave.open(source.path)).seconds, 5);
    final compacted = await output.readAsBytes();
    expect(compacted.sublist(result.dataOffset, result.dataOffset + 32000),
        pcm.sublist(0, 32000));
  });
}
