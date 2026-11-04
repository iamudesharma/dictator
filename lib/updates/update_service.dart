import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../app/dictation_orchestrator.dart';
import '../settings/settings_service.dart';
import '../storage/project_storage.dart';

class AppRelease {
  final String version, notes, digest;
  final Uri url;
  final int size;
  const AppRelease(this.version, this.notes, this.url, this.size, this.digest);
  static int compare(String first, String second) {
    List<int> parts(String value) => value
        .replaceFirst(RegExp(r'^v'), '')
        .split('+')
        .first
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    final a = parts(first), b = parts(second);
    for (var i = 0; i < 3; i++) {
      final cmp = (i < a.length ? a[i] : 0).compareTo(i < b.length ? b[i] : 0);
      if (cmp != 0) return cmp;
    }
    return 0;
  }

  static AppRelease? parse(Map<String, dynamic> data, String current) {
    if (data['draft'] == true || data['prerelease'] == true) return null;
    final tag = data['tag_name'] as String? ?? '';
    if (!RegExp(r'^v?\d+\.\d+\.\d+(\+\d+)?$').hasMatch(tag) ||
        compare(tag, current) <= 0) {
      return null;
    }
    final assets = (data['assets'] as List? ?? []).cast<Map<String, dynamic>>();
    final asset = assets
        .where((a) =>
            (a['name'] as String? ?? '').startsWith('AuraScribe') &&
            (a['name'] as String? ?? '').endsWith('.dmg'))
        .firstOrNull;
    if (asset == null) {
      throw const FormatException('The release has no AuraScribe DMG asset.');
    }
    final url = Uri.parse(asset['browser_download_url'] as String);
    if (url.scheme != 'https' ||
        url.host != 'github.com' ||
        !url.path.startsWith('/iamudesharma/dictator/releases/download/')) {
      throw const FormatException('Unexpected update download location.');
    }
    return AppRelease(tag, data['body'] as String? ?? '', url,
        asset['size'] as int, asset['digest'] as String? ?? '');
  }
}

class UpdateService extends ChangeNotifier {
  static const channel = MethodChannel('com.aurascribe/updates');
  final SettingsService settings;
  final DictationOrchestrator orchestrator;
  UpdateService(this.settings, this.orchestrator);
  String currentVersion = '1.0.0', status = '', error = '';
  bool busy = false;
  AppRelease? release;
  File? downloaded;
  Timer? _timer, _pendingInstall;
  Future<void> configure() async {
    _timer?.cancel();
    currentVersion =
        await channel.invokeMethod<String>('version') ?? currentVersion;
    if (settings.automaticUpdates) {
      unawaited(check().catchError((Object e) {
        error = e.toString();
        _scheduleInstall();
        notifyListeners();
      }));
      _timer = Timer.periodic(const Duration(hours: 12), (_) {
        check().catchError((Object e) {
          error = e.toString();
          _scheduleInstall();
          notifyListeners();
        });
      });
    }
    _scheduleInstall();
    notifyListeners();
  }

  Future<void> check() async {
    if (busy) return;
    busy = true;
    error = '';
    status = 'Checking GitHub releases…';
    notifyListeners();
    final client = http.Client();
    try {
      final response = await client.get(
          Uri.parse(
              'https://api.github.com/repos/iamudesharma/dictator/releases/latest'),
          headers: {
            'Accept': 'application/vnd.github+json'
          }).timeout(const Duration(seconds: 30));
      if (response.statusCode == 404) {
        release = null;
        status = 'No published release is available yet.';
        return;
      }
      if (response.statusCode != 200) {
        throw HttpException('Update check HTTP ${response.statusCode}');
      }
      release = AppRelease.parse(
          Map<String, dynamic>.from(jsonDecode(response.body) as Map),
          currentVersion);
      status = release == null
          ? 'You are up to date.'
          : 'Update ${release!.version} is available.';
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      client.close();
      busy = false;
      notifyListeners();
    }
    if (release != null && settings.downloadUpdates) {
      await download();
      if (settings.installUpdates &&
          orchestrator.isAvailable &&
          !orchestrator.voiceFilter.running) {
        await install();
      }
    }
  }

  Future<void> download() async {
    final value = release;
    if (value == null || busy) return;
    if (!RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(value.digest)) {
      throw StateError(
          'This release has no SHA-256 asset digest. Publish the release with a digest before using in-app download.');
    }
    busy = true;
    error = '';
    notifyListeners();
    final client = http.Client();
    IOSink? sink;
    final directory = await ProjectStorage.instance.directory('updates');
    final temporary =
        File('${directory.path}/AuraScribe-${value.version}.dmg.part');
    try {
      final response = await client
          .send(http.Request('GET', value.url))
          .timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) {
        throw HttpException('Update download HTTP ${response.statusCode}');
      }
      if (value.size <= 0 || value.size > 2 * 1024 * 1024 * 1024) {
        throw const FormatException('Invalid update size.');
      }
      sink = temporary.openWrite();
      var received = 0;
      var lastProgress = DateTime.fromMillisecondsSinceEpoch(0);
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 60))) {
        received += chunk.length;
        if (received > value.size) {
          throw const FormatException('Update exceeds the published size.');
        }
        sink.add(chunk);
        if (DateTime.now().difference(lastProgress).inMilliseconds >= 180) {
          lastProgress = DateTime.now();
          status =
              'Downloading update: ${(received * 100 / value.size).round()}%';
          notifyListeners();
        }
      }
      await sink.close();
      sink = null;
      if (received != value.size ||
          (await sha256.bind(temporary.openRead()).first).toString() !=
              value.digest.substring(7).toLowerCase()) {
        throw const FormatException(
            'Update checksum or size does not match GitHub.');
      }
      downloaded =
          await temporary.rename(temporary.path.replaceFirst('.part', ''));
      status = 'Update downloaded and checksum verified.';
      _scheduleInstall();
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      await sink?.close();
      client.close();
      if (await temporary.exists()) await temporary.delete();
      busy = false;
      notifyListeners();
    }
  }

  void _scheduleInstall() {
    _pendingInstall?.cancel();
    if (!settings.installUpdates || downloaded == null) return;
    _pendingInstall = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (busy ||
          !orchestrator.isAvailable ||
          orchestrator.voiceFilter.running) {
        return;
      }
      _pendingInstall?.cancel();
      try {
        await install();
      } catch (e) {
        error = e.toString();
        notifyListeners();
      }
    });
  }

  Future<void> install() async {
    if (downloaded == null) {
      throw StateError('Download the verified update first.');
    }
    if (!orchestrator.isAvailable || orchestrator.voiceFilter.running) {
      throw StateError(
          'Finish all recordings and stop the voice filter before installing.');
    }
    busy = true;
    error = '';
    status = 'Verifying signed update…';
    notifyListeners();
    try {
      await channel.invokeMethod<void>('install', {
        'dmg': downloaded!.path,
        'workingDirectory':
            (await ProjectStorage.instance.directory('updates')).path
      });
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pendingInstall?.cancel();
    super.dispose();
  }
}
