import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// All model weights, downloads and inference caches belong to this checkout.
/// Fail closed if it disappears; never silently use a home-directory cache.
class ProjectStorage {
  static late ProjectStorage instance;
  final Directory project;
  ProjectStorage(this.project);
  Directory get root => Directory(p.join(project.path, '.aurascribe'));
  Directory get models => Directory(p.join(root.path, 'models'));

  static Future<void> initialize({String? projectPath}) async {
    final path =
        projectPath ?? const String.fromEnvironment('AURASCRIBE_PROJECT_ROOT');
    final resolved = path.isNotEmpty
        ? path
        : await const MethodChannel('com.aurascribe/accessibility')
            .invokeMethod<String>('projectRoot');
    if (resolved == null ||
        !File(p.join(resolved, 'pubspec.yaml')).existsSync()) {
      throw StateError(
          'Project directory unavailable. Rebuild AuraScribe from its checkout.');
    }
    instance = ProjectStorage(
        Directory(await Directory(resolved).resolveSymbolicLinks()));
    await instance.directory('models');
    // flutter_gemma also asks path_provider for its compiled inference cache.
    // Redirect those plugin paths before initializing any model runtime.
    PathProviderPlatform.instance = _ProjectPaths(instance);
  }

  Future<Directory> directory(String relative) async {
    if (p.isAbsolute(relative) || p.split(relative).contains('..')) {
      throw ArgumentError.value(
          relative, 'relative', 'Must stay inside project storage');
    }
    if (!await File(p.join(project.path, 'pubspec.yaml')).exists()) {
      throw StateError(
          'Project directory unavailable; model storage is disabled.');
    }
    var current = project;
    for (final part in ['.aurascribe', ...p.split(relative)]) {
      final next = p.join(current.path, part);
      if (await FileSystemEntity.type(next, followLinks: false) ==
          FileSystemEntityType.link) {
        throw StateError(
            'Project storage cannot contain symbolic links: $next');
      }
      current = await Directory(next).create();
    }
    return current;
  }

  Future<int> modelBytes() async {
    final dir = await directory('models');
    var bytes = 0;
    await for (final entry in dir.list(recursive: true, followLinks: false)) {
      if (entry is File) bytes += await entry.length();
    }
    return bytes;
  }

  final Map<String, Future<String>> _downloads = {};
  final Map<String, http.Client> _clients = {};
  final Set<String> _cancelled = {};
  bool get hasActiveDownloads => _clients.isNotEmpty;
  void cancelDownloads() {
    _cancelled.addAll(_clients.keys);
    for (final client in _clients.values.toList()) {
      client.close();
    }
  }

  Future<String> download(
      {required String folder,
      required String name,
      required Uri url,
      String? token,
      void Function(String)? onProgress,
      int minBytes = 1,
      String? expectedSha256,
      int? expectedBytes}) {
    final key = '$folder/$name';
    return _downloads.putIfAbsent(
        key,
        () => _download(
                    folder: folder,
                    name: name,
                    url: url,
                    token: token,
                    onProgress: onProgress,
                    minBytes: minBytes,
                    expectedSha256: expectedSha256,
                    expectedBytes: expectedBytes)
                .whenComplete(() {
              _downloads.remove(key);
            }));
  }

  Future<String> _download(
      {required String folder,
      required String name,
      required Uri url,
      String? token,
      void Function(String)? onProgress,
      required int minBytes,
      String? expectedSha256,
      int? expectedBytes}) async {
    if (p.basename(name) != name) throw ArgumentError('Invalid filename');
    final dir = await directory('models/$folder');
    final file = File(p.join(dir.path, name));
    final receipt = File('${file.path}.json');
    final partial = File('${file.path}.part');
    for (final target in [file.path, receipt.path, partial.path]) {
      if (await FileSystemEntity.type(target, followLinks: false) ==
          FileSystemEntityType.link) {
        throw StateError('Refusing model file symlink: $target');
      }
    }
    if (await file.exists() && await receipt.exists()) {
      try {
        final data = jsonDecode(await receipt.readAsString()) as Map;
        final length = await file.length();
        if (data['url'] == url.toString() &&
            data['bytes'] == length &&
            length >= minBytes) {
          if (expectedBytes == null || length == expectedBytes) {
            if (expectedSha256 == null) return file.path;
            final digest =
                (await sha256.bind(file.openRead()).first).toString();
            if (digest == expectedSha256) return file.path;
          }
        }
      } catch (_) {/* Redownload incomplete/unrecognized installs. */}
    }
    final client = http.Client();
    final key = '$folder/$name';
    _clients[key] = client;
    IOSink? sink;
    try {
      final request = http.Request('GET', url);
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      final response =
          await client.send(request).timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) {
        throw HttpException('Model download HTTP ${response.statusCode}',
            uri: url);
      }
      sink = partial.openWrite();
      var received = 0;
      var lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 60))) {
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastUpdate).inMilliseconds > 180) {
          lastUpdate = now;
          final total = response.contentLength;
          onProgress?.call(total == null
              ? 'Downloading $name: ${(received / 1048576).toStringAsFixed(1)} MB'
              : 'Downloading $name: ${(received * 100 / total).toStringAsFixed(0)}%');
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (received < minBytes ||
          (response.contentLength != null &&
              received != response.contentLength)) {
        throw const HttpException(
            'Incomplete model download; retry to download again.');
      }
      if (expectedBytes != null && received != expectedBytes) {
        throw const HttpException(
            'Model size does not match the pinned catalog.');
      }
      if (expectedSha256 != null &&
          (await sha256.bind(partial.openRead()).first).toString() !=
              expectedSha256) {
        throw const HttpException(
            'Model checksum does not match the pinned catalog.');
      }
      if (_cancelled.contains(key)) {
        throw StateError('Model download cancelled.');
      }
      await partial.rename(file.path);
      await receipt.writeAsString(
          jsonEncode({'url': url.toString(), 'bytes': received}));
      return file.path;
    } finally {
      await sink?.close();
      client.close();
      _clients.remove(key);
      _cancelled.remove(key);
      if (await partial.exists()) await partial.delete();
    }
  }
}

class _ProjectPaths extends PathProviderPlatform {
  final ProjectStorage storage;
  _ProjectPaths(this.storage);
  Future<String?> _path(String name) async =>
      (await storage.directory(name)).path;
  @override
  Future<String?> getApplicationSupportPath() => _path('runtime');
  @override
  Future<String?> getApplicationCachePath() => _path('cache');
  @override
  Future<String?> getTemporaryPath() => _path('tmp');
  @override
  Future<String?> getLibraryPath() => _path('runtime');
  @override
  Future<String?> getApplicationDocumentsPath() => _path('documents');
  @override
  Future<String?> getDownloadsPath() => _path('downloads');
}
