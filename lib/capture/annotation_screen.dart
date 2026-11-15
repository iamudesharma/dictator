import '../l10n/app_localizations.dart';

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../app/dictation_orchestrator.dart';
import 'annotation_service.dart';

class AnnotationScreen extends StatefulWidget {
  final DictationOrchestrator orchestrator;
  const AnnotationScreen({super.key, required this.orchestrator});
  @override
  State<AnnotationScreen> createState() => _AnnotationScreenState();
}

class _AnnotationScreenState extends State<AnnotationScreen> {
  late final service = widget.orchestrator.annotations;
  final notes = TextEditingController();
  final boundary = GlobalKey();
  ImageProvider? _preview;
  String? _previewPath;
  ImageProvider _previewFor(String path) {
    if (_previewPath != path) {
      _preview?.evict();
      _previewPath = path;
      // Export already renders this 320 logical-pixel panel at pixelRatio 2.
      _preview = ResizeImage(FileImage(File(path)), height: 640);
    }
    return _preview!;
  }

  double get _ratio =>
      (service.data['imageWidth'] as num? ?? 960) /
      (service.data['imageHeight'] as num? ?? 640);
  List<Directory> _captures = [];
  List<Offset> _points = [];
  String? _error;
  bool _busy = false;
  String _tool = 'pen';
  @override
  void initState() {
    super.initState();
    service.addListener(_refresh);
    _refresh();
  }

  void _refresh() {
    if (!mounted) return;
    notes.text = service.data['notes'] as String? ?? '';
    service.list().then((values) {
      if (mounted) setState(() => _captures = values);
    });
  }

  @override
  void dispose() {
    service.removeListener(_refresh);
    _preview?.evict();
    notes.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _export() async {
    final codec = await ui.instantiateImageCodec(
      await File('${service.current!.path}/screenshot.png').readAsBytes(),
    );
    final source = (await codec.getNextFrame()).image;
    codec.dispose();
    final size = Size(source.width.toDouble(), source.height.toDouble());
    final note = service.data['notes'] as String? ?? '';
    final text = TextPainter(
      text: TextSpan(
        text: note,
        style: TextStyle(
          color: const Color(0xff17171a),
          fontSize: (source.width / 65).clamp(14, 36),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 40);
    final extra = note.isEmpty ? 0 : text.height.ceil() + 40;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawImage(source, Offset.zero, Paint());
    _InkPainter(
      strokes,
      service.data['shapes'] as List? ?? [],
    ).paint(canvas, size);
    if (extra > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, size.height, size.width, extra.toDouble()),
        Paint()..color = const Color(0xfff4f4f6),
      );
      text.paint(canvas, Offset(20, size.height + 20));
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(source.width, source.height + extra);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final path = '${service.current!.path}/annotated.png';
      await File(path).writeAsBytes(bytes!.buffer.asUint8List());
      return path;
    } finally {
      text.dispose();
      source.dispose();
      image.dispose();
      picture.dispose();
    }
  }

  List<List<Offset>> get strokes => (service.data['strokes'] as List? ?? [])
      .map(
        (stroke) => (stroke as List)
            .map(
              (v) => Offset((v[0] as num).toDouble(), (v[1] as num).toDouble()),
            )
            .toList(),
      )
      .toList();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        tr("Capture, annotate, and add notes."),
        style: const TextStyle(height: 1.6),
      ),
      const SizedBox(height: 16),
      if (_error != null || service.error.isNotEmpty)
        Text(
          _error ?? service.error,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      Wrap(
        spacing: 8,
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : () => _run(service.capture),
            icon: const Icon(Icons.screenshot_monitor),
            label: Text(tr("Capture region")),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(() => service.capture(window: true)),
            child: Text(tr("Capture window")),
          ),
          TextButton(
            onPressed: _busy ? null : () => _run(service.toggleScreenRecording),
            child: Text(
              service.recordingPath == null
                  ? tr("Record screen")
                  : tr("Stop screen recording"),
            ),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                    await AnnotationService.channel.invokeMethod<bool>(
                      'requestScreenAccess',
                    );
                  }),
            child: Text(tr("Screen permission")),
          ),
        ],
      ),
      SwitchListTile(
        title: Text(tr("Screen replay buffer")),
        subtitle: Text(tr("Keep 15 seconds of screen video. No audio.")),
        value: service.replayEnabled,
        onChanged: _busy ? null : (_) => _run(service.toggleReplay),
      ),
      if (service.replayEnabled)
        TextButton(
          onPressed: _busy ? null : () => _run(service.saveReplay),
          child: Text(tr("Save last 15 seconds")),
        ),
      if (service.lastRecordingPath != null)
        TextButton(
          onPressed: () =>
              Process.run('open', ['-R', service.lastRecordingPath!]),
          child: Text(tr("Reveal saved screen recording")),
        ),
      if (_captures.isNotEmpty)
        DropdownButton<String>(
          isExpanded: true,
          value: service.current?.path,
          hint: Text(tr("Select a capture")),
          items: _captures
              .map(
                (d) => DropdownMenuItem(
                  value: d.path,
                  child: Text(
                    d.uri.pathSegments.where((p) => p.isNotEmpty).last,
                  ),
                ),
              )
              .toList(),
          onChanged: (path) {
            if (path != null) _run(() => service.select(Directory(path)));
          },
        ),
      if (service.current != null) ...[
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final tool in ['pen', 'arrow', 'box', 'text', 'crop'])
              ChoiceChip(
                label: Text(tr(tool)),
                selected: _tool == tool,
                onSelected: (_) => setState(() => _tool = tool),
              ),
          ],
        ),
        RepaintBoundary(
          key: boundary,
          child: ColoredBox(
            color: Colors.white,
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    onTapDown: (event) async {
                      if (_tool != 'text') return;
                      String value = '';
                      final text = await showDialog<String>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(tr("Annotation text")),
                          content: TextField(
                            autofocus: true,
                            onChanged: (text) => value = text,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(tr("Cancel")),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, value),
                              child: Text(tr("Add")),
                            ),
                          ],
                        ),
                      );
                      if (text == null || text.trim().isEmpty || !mounted) {
                        return;
                      }
                      final shapes = service.data['shapes'] as List? ?? [];
                      shapes.add({
                        'kind': 'text',
                        'text': text,
                        'a': [
                          event.localPosition.dx / constraints.maxWidth,
                          event.localPosition.dy /
                              (constraints.maxWidth / _ratio),
                        ],
                      });
                      service.data['shapes'] = shapes;
                      await service.save();
                      setState(() {});
                    },
                    onPanStart: (event) => setState(
                      () => _points = [
                        Offset(
                          event.localPosition.dx / constraints.maxWidth,
                          event.localPosition.dy /
                              (constraints.maxWidth / _ratio),
                        ),
                      ],
                    ),
                    onPanUpdate: (event) => setState(
                      () => _points.add(
                        Offset(
                          (event.localPosition.dx / constraints.maxWidth).clamp(
                            0,
                            1,
                          ),
                          (event.localPosition.dy /
                                  (constraints.maxWidth / _ratio))
                              .clamp(0, 1),
                        ),
                      ),
                    ),
                    onPanEnd: (_) {
                      final values = service.data['strokes'] as List? ?? [];
                      if (_points.isEmpty) return;
                      if (_tool == 'crop') {
                        final a = _points.first, b = _points.last;
                        _run(() async {
                          await AnnotationService.channel.invokeMethod<void>(
                            'cropImage',
                            {
                              'path': '${service.current!.path}/screenshot.png',
                              'x': math.min(a.dx, b.dx),
                              'y': math.min(a.dy, b.dy),
                              'width': (a.dx - b.dx).abs(),
                              'height': (a.dy - b.dy).abs(),
                            },
                          );
                          final size = await AnnotationService.channel
                              .invokeMapMethod<String, dynamic>(
                                'imageSize',
                                '${service.current!.path}/screenshot.png',
                              );
                          service.data['imageWidth'] = size?['width'];
                          service.data['imageHeight'] = size?['height'];
                          _preview?.evict();
                          _previewPath = null;
                          service.data['strokes'] = [];
                          service.data['shapes'] = [];
                          await service.save();
                        });
                      } else if (_tool == 'pen') {
                        values.add(_points.map((p) => [p.dx, p.dy]).toList());
                      } else {
                        final shapes = service.data['shapes'] as List? ?? [];
                        shapes.add({
                          'kind': _tool,
                          'a': [_points.first.dx, _points.first.dy],
                          'b': [_points.last.dx, _points.last.dy],
                        });
                        service.data['shapes'] = shapes;
                      }
                      service.data['strokes'] = values;
                      setState(() => _points = []);
                      service.save();
                    },
                    child: SizedBox(
                      height: constraints.maxWidth / _ratio,
                      width: double.infinity,
                      child: CustomPaint(
                        foregroundPainter: _InkPainter([
                          ...strokes,
                          _points,
                        ], service.data['shapes'] as List? ?? []),
                        child: Image(
                          image: _previewFor(
                            '${service.current!.path}/screenshot.png',
                          ),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
                if ((service.data['notes'] as String? ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      service.data['notes'] as String,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: notes,
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(labelText: tr("Capture notes")),
          onChanged: (value) {
            service.data['notes'] = value;
            service.save();
            setState(() {});
          },
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: _busy ? null : () => _run(service.dictate),
              child: Text(
                widget.orchestrator.isAvailable
                    ? tr("Dictate note")
                    : tr("Stop dictation"),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : () => _run(service.recognizeText),
              child: Text(tr("Extract text (OCR)")),
            ),
            TextButton(
              onPressed: () => _run(() async {
                final values = service.data['strokes'] as List? ?? [];
                final shapes = service.data['shapes'] as List? ?? [];
                if (shapes.isNotEmpty) {
                  shapes.removeLast();
                  service.data['shapes'] = shapes;
                } else if (values.isNotEmpty) {
                  values.removeLast();
                }
                service.data['strokes'] = values;
                await service.save();
              }),
              child: Text(tr("Undo stroke")),
            ),
            TextButton(
              onPressed: () => _run(() async {
                await _export();
                await Process.run('open', [
                  '-R',
                  '${service.current!.path}/annotated.png',
                ]);
              }),
              child: Text(tr("Export annotated PNG")),
            ),
            for (final action in ['copyImage', 'shareImage'])
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        final path = await _export();
                        await AnnotationService.channel.invokeMethod<void>(
                          action,
                          path,
                        );
                      }),
                child: Text(
                  action == 'copyImage' ? tr("Copy image") : tr("Send to…"),
                ),
              ),
          ],
        ),
      ],
    ],
  );
}

class _InkPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List shapes;
  _InkPainter(this.strokes, this.shapes);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFDD3E32)
      ..strokeWidth = math.max(1, size.width / 220)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final shape in shapes) {
      Offset point(String key) => Offset(
        (shape[key][0] as num).toDouble() * size.width,
        (shape[key][1] as num).toDouble() * size.height,
      );
      final a = point('a');
      if (shape['kind'] == 'text') {
        final text = TextPainter(
          text: TextSpan(
            text: shape['text'] as String,
            style: TextStyle(
              color: const Color(0xFFDD3E32),
              fontSize: size.width / 35,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: math.max(1, size.width - a.dx));
        text.paint(canvas, a);
        text.dispose();
        continue;
      }
      final b = point('b');
      if (shape['kind'] == 'box') {
        canvas.drawRect(Rect.fromPoints(a, b), paint);
      } else {
        canvas.drawLine(a, b, paint);
        final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
        for (final side in [-1, 1]) {
          canvas.drawLine(
            b,
            b -
                Offset(
                      math.cos(angle + side * .5),
                      math.sin(angle + side * .5),
                    ) *
                    14,
            paint,
          );
        }
      }
    }
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final path = Path()
        ..moveTo(stroke.first.dx * size.width, stroke.first.dy * size.height);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx * size.width, point.dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _InkPainter oldDelegate) => true;
}
