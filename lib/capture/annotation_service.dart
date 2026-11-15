import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../app/dictation_orchestrator.dart';
import '../storage/project_storage.dart';

class AnnotationService extends ChangeNotifier {
  static const channel = MethodChannel('com.aurascribe/capture');
  final DictationOrchestrator orchestrator;
  AnnotationService(this.orchestrator);
  String error = '';
  Directory? current;
  Map<String, dynamic> data = {};
  Future<void> _pending = Future.value();
  Future<List<Directory>> list() async =>
      (await (await ProjectStorage.instance.directory('captures'))
          .list(followLinks: false)
          .where((e) =>
              e is Directory && File('${e.path}/screenshot.png').existsSync())
          .cast<Directory>()
          .toList())
        ..sort((a, b) => b.path.compareTo(a.path));
  Future<void> capture({bool window = false}) async {
    if (!orchestrator.isAvailable) {
      throw StateError('Finish the current audio task first.');
    }
    orchestrator.externalActivity = 'Screen capture';
    Directory? directory;
    try {
      directory = await ProjectStorage.instance
          .directory('captures/${DateTime.now().millisecondsSinceEpoch}');
      final file = '${directory.path}/screenshot.png';
      final captured = await channel.invokeMethod<bool>(
              window ? 'captureWindow' : 'captureRegion', file) ??
          false;
      if (!captured) {
        await directory.delete(recursive: true);
        return;
      }
      error = '';
      current = directory;
      final size =
          await channel.invokeMapMethod<String, dynamic>('imageSize', file);
      data = {
        'imageWidth': size?['width'] ?? 960,
        'imageHeight': size?['height'] ?? 640,
        'notes': '',
        'strokes': <dynamic>[],
        'createdAt': DateTime.now().toUtc().toIso8601String()
      };
      await _imageInfo();
      await save();
      await channel.invokeMethod<void>('copyImage', file);
      notifyListeners();
    } catch (e) {
      if (directory != null &&
          !await File('${directory.path}/screenshot.png').exists()) {
        await directory.delete(recursive: true);
      }
      error = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      orchestrator.externalActivity = null;
    }
  }

  static const replayChannel = MethodChannel('com.aurascribe/replay');
  bool replayEnabled = false;
  Future<void> _replayPending = Future.value();
  Future<void> _replay(Future<void> Function() action) =>
      _replayPending = _replayPending.catchError((_) {}).then((_) async {
        try {
          await action();
          error = '';
        } catch (e) {
          error = e.toString();
          rethrow;
        } finally {
          notifyListeners();
        }
      });
  Future<void> toggleReplay() => _replay(() async {
        if (replayEnabled) {
          await replayChannel.invokeMethod<void>('stop');
          replayEnabled = false;
        } else {
          final folder =
              await ProjectStorage.instance.directory('captures/replay-buffer');
          await replayChannel.invokeMethod<void>('start', folder.path);
          replayEnabled = true;
        }
        notifyListeners();
      });

  Future<void> saveReplay() => _replay(() async {
        if (!replayEnabled) {
          throw StateError('Enable screen replay before saving it.');
        }
        final folder = await ProjectStorage.instance.directory(
            'captures/replay-${DateTime.now().microsecondsSinceEpoch}');
        final path = '${folder.path}/last-15-seconds.mov';
        await replayChannel.invokeMethod<void>('save', path);
        lastRecordingPath = path;
        notifyListeners();
      });

  String? recordingPath, lastRecordingPath;
  Future<void> toggleScreenRecording() async {
    if (recordingPath != null) {
      await channel.invokeMethod<void>('stopScreenRecording');
      lastRecordingPath = recordingPath;
      recordingPath = null;
    } else {
      final directory = await ProjectStorage.instance
          .directory('captures/video-${DateTime.now().microsecondsSinceEpoch}');
      final path = '${directory.path}/recording.mov';
      await channel.invokeMethod<void>('startScreenRecording', path);
      recordingPath = path;
    }
    notifyListeners();
  }

  Future<void> _imageInfo() async {
    if (current == null) return;
    final info = await channel.invokeMapMethod<String, dynamic>(
        'imageSize', '${current!.path}/screenshot.png');
    if (info != null) {
      data['imageWidth'] = info['width'];
      data['imageHeight'] = info['height'];
    }
  }

  Future<void> select(Directory directory) async {
    await _pending;
    final file = File('${directory.path}/annotation.json');
    data = await file.exists()
        ? Map<String, dynamic>.from(
            jsonDecode(await file.readAsString()) as Map)
        : {'notes': '', 'strokes': <dynamic>[]};
    current = directory;
    await _imageInfo();
    notifyListeners();
  }

  Future<void> save() {
    final directory = current;
    if (directory == null) return Future.value();
    final snapshot = const JsonEncoder.withIndent('  ').convert(data);
    _pending = _pending.catchError((_) {}).then((_) async {
      final temp = File('${directory.path}/annotation.json.tmp');
      await temp.writeAsString(snapshot, flush: true);
      await temp.rename('${directory.path}/annotation.json');
    });
    return _pending;
  }

  Future<void> dictate() async {
    final directory = current;
    if (directory == null) {
      throw StateError('Capture or select an image first.');
    }
    await orchestrator.dictateTo((text) async {
      await _pending;
      final file = File('${directory.path}/annotation.json');
      final saved = Map<String, dynamic>.from(
          jsonDecode(await file.readAsString()) as Map);
      saved['notes'] = '${saved['notes'] ?? ''}\n$text'.trim();
      await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(saved),
          flush: true);
      if (current?.path == directory.path) {
        data = saved;
        notifyListeners();
      }
    });
  }

  Future<void> recognizeText() async {
    final directory = current;
    if (directory == null) return;
    final text = await channel.invokeMethod<String>(
            'recognizeText', '${directory.path}/screenshot.png') ??
        '';
    data['notes'] = '${data['notes'] ?? ''}\n$text'.trim();
    await save();
    notifyListeners();
  }
}
