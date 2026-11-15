import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';

Future<String> hash(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();
Future<void> main(List<String> args) async {
  final watch = Stopwatch()..start();
  final digest = await hash(args.single);
  stdout.writeln('inline hash: ${watch.elapsedMilliseconds} ms');
  watch.reset();
  final isolated = await Isolate.run(() => hash(args.single));
  stdout.writeln(
      'isolated hash: ${watch.elapsedMilliseconds} ms; same digest: ${digest == isolated}');
}
