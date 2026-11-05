// Opt-in VM instrumentation: aggregate counts and class/field names only.
// Never writes object contents, credentials, audio or a full heap dump.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

Future<Map<String, Object?>> captureHeapCounts(
    {bool retainingPath = false}) async {
  final info = await developer.Service.getInfo();
  final uri = info.serverUri;
  final isolate = developer.Service.getIsolateId(Isolate.current);
  if (uri == null || isolate == null) {
    throw StateError('Run with --enable-vmservice');
  }
  final socket = await WebSocket.connect(
      uri.replace(scheme: 'ws', path: '${uri.path}ws').toString());
  var serial = 0;
  final pending = <int, Completer<Map<String, dynamic>>>{};
  final subscription = socket.listen((message) {
    final response = jsonDecode(message as String) as Map<String, dynamic>;
    final completer = pending.remove(response['id']);
    if (completer != null) completer.complete(response);
  });
  Future<Map<String, dynamic>> rpc(
      String method, Map<String, Object?> params) async {
    final id = ++serial;
    final response = Completer<Map<String, dynamic>>();
    pending[id] = response;
    socket.add(jsonEncode(
        {'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}));
    final value = await response.future.timeout(const Duration(seconds: 20));
    if (value['error'] != null) {
      throw StateError('VM profile request failed: $method');
    }
    return value['result'] as Map<String, dynamic>;
  }

  try {
    final profile =
        await rpc('getAllocationProfile', {'isolateId': isolate, 'gc': true});
    const watched = {
      '_SettingsScreenState',
      '_PlaygroundScreenState',
      '_MeetingsScreenState',
      '_AnnotationScreenState',
      'TextEditingController',
      'PcmSpool'
    };
    final report = <String, Object?>{
      'memoryUsage': profile['memoryUsage'],
      'classes': {
        for (final row in profile['members'] as List)
          if (watched.contains((row['class'] as Map)['name']))
            (row['class'] as Map)['name'] as String: {
              'instancesCurrent': row['instancesCurrent'],
              'bytesCurrent': row['bytesCurrent'],
            },
      }
    };
    if (retainingPath) {
      final states = (profile['members'] as List)
          .where((row) => row['class']['name'] == '_SettingsScreenState');
      if (states.isNotEmpty) {
        final instances = await rpc('getInstances', {
          'isolateId': isolate,
          'objectId': states.first['class']['id'],
          'limit': 1
        });
        report['settingsInstanceCount'] = instances['totalCount'];
        final samples =
            (instances['instances'] ?? instances['samples']) as List? ?? [];
        if (samples.isNotEmpty) {
          final path = await rpc('getRetainingPath', {
            'isolateId': isolate,
            'targetId': samples.first['id'],
            'limit': 250
          });
          report['retainingRoot'] = path['gcRootType'];
          report['retainingClasses'] = [
            for (final row in path['elements'] as List? ?? [])
              {
                'name': row['value']?['name'],
                'class':
                    row['value']?['class']?['name'] ?? row['value']?['type'],
                'field': row['parentField'] is Map
                    ? row['parentField']['name']
                    : row['parentField'],
              }
          ];
        }
      }
    }
    return report;
  } finally {
    await subscription.cancel();
    await socket.close();
  }
}
