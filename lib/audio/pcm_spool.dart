import 'dart:io';
import 'dart:typed_data';
import '../shared/wav_header_helper.dart';

/// Appends bounded PCM directly to disk. A partial decoder sees an immutable
/// prefix copied in 64 KiB blocks, never the full recording in a Dart list.
class PcmSpool {
  PcmSpool._(this.file, this._writer, this.maxBytes);
  final File file;
  final RandomAccessFile _writer;
  final int maxBytes;
  int bytes = 0;
  bool _closed = false;

  static Future<PcmSpool> create(Directory directory, int maxSeconds) async {
    await directory.create(recursive: true);
    final file = File(
        '${directory.path}/dictation-${DateTime.now().microsecondsSinceEpoch}.wav');
    final writer = await file.open(mode: FileMode.write);
    try {
      await writer.writeFrom(WavHeaderHelper.buildHeader(0));
      return PcmSpool._(file, writer, maxSeconds.clamp(1, 3600) * 32000);
    } catch (_) {
      await writer.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  /// Small synchronous writes avoid an unbounded asynchronous write queue when
  /// storage is slower than the microphone. No fsync occurs on each chunk.
  bool append(Uint8List chunk) {
    if (_closed) throw StateError('PCM spool is closed');
    final count = chunk.length.clamp(0, maxBytes - bytes);
    if (count > 0) {
      _writer.writeFromSync(chunk, 0, count);
      bytes += count;
    }
    return bytes == maxBytes;
  }

  Future<File> snapshot(File target) async {
    if (_closed) throw StateError('PCM spool is closed');
    if (target.absolute.path == file.absolute.path) {
      throw ArgumentError('Snapshot must use a separate file');
    }
    final length = bytes & ~1; // Snapshot only complete 16-bit samples.
    // The file is unbuffered; new chunks may append, but cannot change this
    // prefix. Separate handles leave the writer's append position untouched.
    final source = await file.open();
    RandomAccessFile? output;
    var complete = false;
    try {
      output = await target.open(mode: FileMode.write);
      await output.writeFrom(WavHeaderHelper.buildHeader(length));
      await source.setPosition(44);
      var remaining = length;
      while (remaining > 0) {
        final block = await source.read(remaining.clamp(0, 65536));
        if (block.isEmpty) {
          throw const FileSystemException('Incomplete PCM spool');
        }
        await output.writeFrom(block);
        remaining -= block.length;
      }
      complete = true;
      return target;
    } finally {
      await source.close();
      await output?.close();
      if (!complete && await target.exists()) await target.delete();
    }
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _writer.close();
    if (await file.exists()) await file.delete();
  }
}
