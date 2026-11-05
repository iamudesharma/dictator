import 'dart:convert';
import 'dart:io';
import '../storage/project_storage.dart';

class PersonalCommand {
  final String id, name, instruction;
  const PersonalCommand(this.id, this.name, this.instruction);
  factory PersonalCommand.fromJson(Map<String, dynamic> value) =>
      PersonalCommand(value['id'] as String, value['name'] as String,
          value['instruction'] as String);
  Map<String, String> toJson() =>
      {'id': id, 'name': name, 'instruction': instruction};
}

class PersonalCommandStore {
  Future<File> get file async => File(
      '${(await ProjectStorage.instance.directory('output')).path}/commands.json');
  Future<List<PersonalCommand>> read() async {
    final source = await file;
    if (!await source.exists()) return [];
    try {
      final commands = (jsonDecode(await source.readAsString()) as List)
          .map((v) =>
              PersonalCommand.fromJson(Map<String, dynamic>.from(v as Map)))
          .toList();
      validate(commands);
      return commands;
    } catch (e) {
      throw FormatException(
          'Personal commands could not be read. Fix commands.json: $e');
    }
  }

  static void validate(List<PersonalCommand> commands) {
    final ids = <String>{};
    for (final command in commands) {
      if (command.id.isEmpty ||
          !ids.add(command.id) ||
          command.name.trim().isEmpty ||
          command.instruction.trim().isEmpty) {
        throw const FormatException(
            'Commands need unique IDs, names and instructions.');
      }
    }
  }

  Future<void> save(List<PersonalCommand> commands) async {
    validate(commands);
    final target = await file;
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(
        const JsonEncoder.withIndent('  ')
            .convert(commands.map((c) => c.toJson()).toList()),
        flush: true);
    await temp.rename(target.path);
  }
}
