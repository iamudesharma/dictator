import 'package:flutter_test/flutter_test.dart';
import 'package:voice_to_text/output/output_pipeline.dart';

void main() {
  test('resolves default and app order with opt-out', () {
    const profiles = [
      OutputProfile('*', [OutputStep(OutputStepKind.lowercase)]),
      OutputProfile('mail', [OutputStep(OutputStepKind.uppercase)]),
      OutputProfile('terminal', [], includeDefault: false)
    ];
    expect(PipelineStore.resolve(profiles, 'mail').map((s) => s.kind),
        [OutputStepKind.lowercase, OutputStepKind.uppercase]);
    expect(PipelineStore.resolve(profiles, 'terminal'), isEmpty);
    expect(PipelineStore.resolve(profiles, 'unknown').length, 1);
  });
  test('ordered transforms run once and fail closed on empty output', () async {
    final calls = <String>[];
    final processor = OutputProcessor((text, instruction) async {
      calls.add(text);
      return '$text translated';
    });
    final result = await processor.process('AURA SCRIBE', const [
      OutputStep(OutputStepKind.lowercase),
      OutputStep(OutputStepKind.replacements, 'aura scribe = AuraScribe'),
      OutputStep(OutputStepKind.translate, 'Hindi')
    ]);
    expect(result, 'AuraScribe translated');
    expect(calls, ['AuraScribe']);
    await expectLater(
        OutputProcessor((_, __) async => '')
            .process('text', const [OutputStep(OutputStepKind.cleanup)]),
        throwsStateError);
  });
}
