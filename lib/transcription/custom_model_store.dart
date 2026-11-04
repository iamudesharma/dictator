import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../storage/project_storage.dart';

class CustomSpeechModel {
  final String id, name, architecture, filename;
  const CustomSpeechModel(this.id, this.name, this.architecture, this.filename);
  Map<String, String> toJson() => {
        'id': id,
        'name': name,
        'architecture': architecture,
        'filename': filename
      };
  factory CustomSpeechModel.fromJson(Map<String, dynamic> data) =>
      CustomSpeechModel(data['id'] as String, data['name'] as String,
          data['architecture'] as String, data['filename'] as String);
}

class CustomModelStore {
  Future<Directory> get directory =>
      ProjectStorage.instance.directory('models/imports');
  Future<File> get _index async => File('${(await directory).path}/index.json');
  Future<List<CustomSpeechModel>> read() async {
    final file = await _index;
    if (!await file.exists()) return [];
    return (jsonDecode(await file.readAsString()) as List)
        .map((v) =>
            CustomSpeechModel.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList();
  }

  Future<CustomSpeechModel> importFile(String sourcePath) async {
    final source = File(sourcePath);
    final header = await GgufHeader.inspect(source);
    if (!{
      'parakeet',
      'whisper',
      'qwen3_asr',
      'sensevoice',
      'cohere_asr',
      'gigaam',
      'moonshine',
      'moonshine_streaming'
    }.contains(header['general.architecture'])) {
      throw const FormatException(
          'This GGUF architecture is not a supported speech model.');
    }
    final hash = (await sha256.bind(source.openRead()).first).toString();
    final model = CustomSpeechModel(
        'custom-$hash',
        header['general.name'] ?? source.uri.pathSegments.last,
        header['general.architecture']!,
        '$hash.gguf');
    final target = File('${(await directory).path}/${model.filename}');
    if (await FileSystemEntity.type(target.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FileSystemException(
          'A model import cannot overwrite a symbolic link.');
    }
    if (!await target.exists()) {
      final temporary = File('${target.path}.part');
      await source.openRead().pipe(temporary.openWrite());
      if ((await sha256.bind(temporary.openRead()).first).toString() != hash) {
        await temporary.delete();
        throw const FileSystemException('Source model changed during import.');
      }
      await temporary.rename(target.path);
    }
    final models = await read();
    models.removeWhere((m) => m.id == model.id);
    models.add(model);
    final index = await _index, temp = File('${(await _index).path}.tmp');
    await temp.writeAsString(jsonEncode(models.map((m) => m.toJson()).toList()),
        flush: true);
    await temp.rename(index.path);
    return model;
  }

  Future<String> path(CustomSpeechModel model) async {
    if (!RegExp(r'^[a-f0-9]{64}\.gguf$').hasMatch(model.filename)) {
      throw const FormatException('Invalid custom-model filename.');
    }
    final file = File('${(await directory).path}/${model.filename}');
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FileSystemException(
          'Imported model path is a symbolic link.');
    }
    return file.path;
  }
}

/// Reads bounded metadata only; never maps or materializes the model weights.
class GgufHeader {
  static Future<Map<String, String>> inspect(File file) async {
    final reader = await file.open();
    try {
      Future<int> integer(int bytes) async {
        final raw = await reader.read(bytes);
        if (raw.length != bytes) {
          throw const FormatException('Truncated GGUF metadata.');
        }
        var value = 0;
        for (var i = 0; i < bytes; i++) {
          value |= raw[i] << (8 * i);
        }
        return value;
      }

      Future<String> string() async {
        final count = await integer(8);
        if (count < 0 || count > 1048576) {
          throw const FormatException('GGUF string exceeds the import limit.');
        }
        final raw = await reader.read(count);
        if (raw.length != count) {
          throw const FormatException('Truncated GGUF string.');
        }
        return utf8.decode(raw);
      }

      Future<void> skip(int type, [int depth = 0]) async {
        if (depth > 3) {
          throw const FormatException(
              'Nested GGUF metadata exceeds the import limit.');
        }
        if (type == 8) {
          final size = await integer(8);
          if (size < 0 || size > 16777216) {
            throw const FormatException('Invalid GGUF string.');
          }
          await reader.setPosition(await reader.position() + size);
          return;
        }
        if (type == 9) {
          final item = await integer(4), count = await integer(8);
          if (count < 0 || count > 2000000) {
            throw const FormatException('GGUF array exceeds the import limit.');
          }
          for (var i = 0; i < count; i++) {
            await skip(item, depth + 1);
          }
          return;
        }
        const sizes = {
          0: 1,
          1: 1,
          2: 2,
          3: 2,
          4: 4,
          5: 4,
          6: 4,
          7: 1,
          10: 8,
          11: 8,
          12: 8
        };
        final size = sizes[type];
        if (size == null) {
          throw const FormatException('Unknown GGUF value type.');
        }
        await reader.setPosition(await reader.position() + size);
      }

      if (await integer(4) != 0x46554747) {
        throw const FormatException('Choose a GGUF speech-model file.');
      }
      if (!{2, 3}.contains(await integer(4))) {
        throw const FormatException('Unsupported GGUF version.');
      }
      await integer(8);
      final count = await integer(8);
      if (count < 0 || count > 100000) {
        throw const FormatException('Invalid GGUF metadata count.');
      }
      final values = <String, String>{};
      for (var i = 0; i < count; i++) {
        final key = await string(), type = await integer(4);
        if (type == 8 &&
            {'general.name', 'general.architecture', 'stt.variant'}
                .contains(key)) {
          values[key] = await string();
          if (values.keys.toSet().containsAll(
              {'general.name', 'general.architecture', 'stt.variant'})) {
            break;
          }
        } else {
          await skip(type);
        }
      }
      if (await reader.position() > await reader.length()) {
        throw const FormatException('Truncated GGUF metadata.');
      }
      return values;
    } finally {
      await reader.close();
    }
  }
}
