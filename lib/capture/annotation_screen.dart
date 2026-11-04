import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  List<Directory> _captures = [];
  List<Offset> _points = [];
  String? _error;
  bool _busy = false;
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

  List<List<Offset>> get strokes => (service.data['strokes'] as List? ?? [])
      .map((stroke) => (stroke as List)
          .map(
              (v) => Offset((v[0] as num).toDouble(), (v[1] as num).toDouble()))
          .toList())
      .toList();
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text(
            'Capture a region, mark it up and add written or dictated notes. Screenshots, drawings and OCR stay in this project.',
            style: TextStyle(height: 1.6)),
        const SizedBox(height: 16),
        if (_error != null || service.error.isNotEmpty)
          Text(_error ?? service.error,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        Wrap(spacing: 8, children: [
          FilledButton.icon(
              onPressed: _busy ? null : () => _run(service.capture),
              icon: const Icon(Icons.screenshot_monitor),
              label: const Text('Capture region')),
          TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        await AnnotationService.channel
                            .invokeMethod<bool>('requestScreenAccess');
                      }),
              child: const Text('Screen permission'))
        ]),
        if (_captures.isNotEmpty)
          DropdownButton<String>(
              isExpanded: true,
              value: service.current?.path,
              hint: const Text('Select a capture'),
              items: _captures
                  .map((d) => DropdownMenuItem(
                      value: d.path,
                      child: Text(
                          d.uri.pathSegments.where((p) => p.isNotEmpty).last)))
                  .toList(),
              onChanged: (path) {
                if (path != null) _run(() => service.select(Directory(path)));
              }),
        if (service.current != null) ...[
          const SizedBox(height: 16),
          RepaintBoundary(
              key: boundary,
              child: ColoredBox(
                  color: Colors.white,
                  child: Column(children: [
                    LayoutBuilder(
                        builder: (context, constraints) => GestureDetector(
                            onPanStart: (event) => setState(() => _points = [
                                  Offset(
                                      event.localPosition.dx /
                                          constraints.maxWidth,
                                      event.localPosition.dy / 320)
                                ]),
                            onPanUpdate: (event) => setState(() => _points.add(
                                Offset(
                                    (event.localPosition.dx /
                                            constraints.maxWidth)
                                        .clamp(0, 1),
                                    (event.localPosition.dy / 320)
                                        .clamp(0, 1)))),
                            onPanEnd: (_) {
                              final values =
                                  service.data['strokes'] as List? ?? [];
                              values.add(
                                  _points.map((p) => [p.dx, p.dy]).toList());
                              service.data['strokes'] = values;
                              setState(() => _points = []);
                              service.save();
                            },
                            child: SizedBox(
                                height: 320,
                                width: double.infinity,
                                child: CustomPaint(
                                    foregroundPainter:
                                        _InkPainter([...strokes, _points]),
                                    child: Image(
                                        image: _previewFor(
                                            '${service.current!.path}/screenshot.png'),
                                        fit: BoxFit.contain))))),
                    if ((service.data['notes'] as String? ?? '').isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(service.data['notes'] as String,
                              style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 14,
                                  height: 1.5))),
                  ]))),
          const SizedBox(height: 12),
          TextField(
              controller: notes,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'Capture notes'),
              onChanged: (value) {
                service.data['notes'] = value;
                service.save();
                setState(() {});
              }),
          Wrap(spacing: 8, children: [
            TextButton(
                onPressed: _busy ? null : () => _run(service.dictate),
                child: Text(widget.orchestrator.isAvailable
                    ? 'Dictate note'
                    : 'Stop dictation')),
            TextButton(
                onPressed: _busy ? null : () => _run(service.recognizeText),
                child: const Text('Extract text (OCR)')),
            TextButton(
                onPressed: () => _run(() async {
                      final values = service.data['strokes'] as List? ?? [];
                      if (values.isNotEmpty) values.removeLast();
                      service.data['strokes'] = values;
                      await service.save();
                    }),
                child: const Text('Undo stroke')),
            TextButton(
                onPressed: () => _run(() async {
                      final image = await (boundary.currentContext!
                              .findRenderObject() as RenderRepaintBoundary)
                          .toImage(pixelRatio: 2);
                      try {
                        final bytes = await image.toByteData(
                            format: ui.ImageByteFormat.png);
                        await File('${service.current!.path}/annotated.png')
                            .writeAsBytes(bytes!.buffer.asUint8List());
                      } finally {
                        image.dispose();
                      }
                      await Process.run('open',
                          ['-R', '${service.current!.path}/annotated.png']);
                    }),
                child: const Text('Export annotated PNG')),
          ]),
        ],
      ]);
}

class _InkPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _InkPainter(this.strokes);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFDD3E32)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
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
