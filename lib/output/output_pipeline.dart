import 'dart:convert';
import 'dart:io';
import '../storage/project_storage.dart';

enum OutputStepKind {
  cleanup,
  replacements,
  translate,
  instruction,
  lowercase,
  uppercase
}

class OutputStep {
  final OutputStepKind kind;
  final String value;
  const OutputStep(this.kind, [this.value = '']);
  factory OutputStep.fromJson(Map<String, dynamic> json) => OutputStep(
      OutputStepKind.values.byName(json['kind'] as String),
      json['value'] as String? ?? '');
  Map<String, String> toJson() => {'kind': kind.name, 'value': value};
}

class OutputProfile {
  final String application;
  final List<OutputStep> steps;
  final bool includeDefault;
  const OutputProfile(this.application, this.steps,
      {this.includeDefault = true});
  factory OutputProfile.fromJson(Map<String, dynamic> json) => OutputProfile(
      json['application'] as String,
      (json['steps'] as List)
          .map((s) => OutputStep.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList(),
      includeDefault: json['includeDefault'] as bool? ?? true);
  Map<String, dynamic> toJson() => {
        'application': application,
        'includeDefault': includeDefault,
        'steps': steps.map((s) => s.toJson()).toList()
      };
}

class PipelineStore {
  Future<File> get file async => File(
      '${(await ProjectStorage.instance.directory('output')).path}/pipelines.json');
  Future<List<OutputProfile>> read() async {
    final source = await file;
    if (!await source.exists()) return [];
    try {
      final profiles = (jsonDecode(await source.readAsString()) as List)
          .map((p) =>
              OutputProfile.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList();
      validate(profiles);
      return profiles;
    } catch (e) {
      throw FormatException(
          'Output pipelines could not be read. Fix pipelines.json in the project output folder: $e');
    }
  }

  static void validate(List<OutputProfile> profiles) {
    final applications = <String>{};
    for (final profile in profiles) {
      if (profile.application.isEmpty ||
          !applications.add(profile.application)) {
        throw const FormatException('Each application must appear once.');
      }
      if (profile.steps.length > 20) {
        throw const FormatException(
            'Use no more than 20 steps per application.');
      }
      for (final step in profile.steps) {
        if ({
              OutputStepKind.translate,
              OutputStepKind.instruction,
              OutputStepKind.replacements
            }.contains(step.kind) &&
            step.value.trim().isEmpty) {
          throw FormatException('${step.kind.name} needs a value.');
        }
      }
    }
  }

  Future<void> save(List<OutputProfile> profiles) async {
    validate(profiles);
    final target = await file;
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(
        const JsonEncoder.withIndent('  ')
            .convert(profiles.map((p) => p.toJson()).toList()),
        flush: true);
    await temp.rename(target.path);
  }

  static List<OutputStep> resolve(
      List<OutputProfile> profiles, String application) {
    final general = profiles.where((p) => p.application == '*').firstOrNull;
    final specific = profiles
        .where((p) => p.application == application && application != '*')
        .firstOrNull;
    return [
      if (specific?.includeDefault != false) ...?general?.steps,
      ...?specific?.steps
    ];
  }
}

typedef LocalTransform = Future<String> Function(
    String text, String instruction);

class OutputProcessor {
  final LocalTransform transform;
  const OutputProcessor(this.transform);
  Future<String> process(String text, List<OutputStep> steps) async {
    for (final step in steps) {
      text = switch (step.kind) {
        OutputStepKind.cleanup => await transform(text,
            'Correct spelling, punctuation and grammar. Preserve the meaning and language.'),
        OutputStepKind.replacements => replaceWords(text, step.value),
        OutputStepKind.translate => await transform(text,
            'Translate the following text into ${step.value}. Preserve its meaning.'),
        OutputStepKind.instruction => await transform(text, step.value),
        OutputStepKind.lowercase => text.toLowerCase(),
        OutputStepKind.uppercase => text.toUpperCase(),
      };
      if (text.trim().isEmpty) {
        throw StateError(
            'An output step returned no text; nothing was pasted.');
      }
    }
    return text;
  }

  static String replaceWords(String text, String rules) {
    for (final line in rules.split('\n')) {
      final split = line.indexOf('=');
      if (split <= 0) continue;
      final from = line.substring(0, split).trim(),
          to = line.substring(split + 1).trim();
      if (from.isEmpty || to.isEmpty) continue;
      text = text.replaceAllMapped(
          RegExp('(?<![a-zA-Z0-9_])${RegExp.escape(from)}(?![a-zA-Z0-9_])',
              caseSensitive: false),
          (_) => to);
    }
    return text;
  }
}
