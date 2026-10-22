/// crop_screen.dart — choose part of a screenshot. Drag inside the box to
/// move it, drag a corner or edge to resize it. Pops the box in fractions
/// (0-1) of the picture, or null.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

class CropScreen extends StatefulWidget {
  final Uint8List image;
  const CropScreen({super.key, required this.image});

  @override
  State<CropScreen> createState() => _CropScreenState();
}

enum _Grip { move, tl, tr, bl, br, l, r, t, b }

class _CropScreenState extends State<CropScreen> {
  static const _minSize = 0.04; // of the picture
  static const _gripReach = 28.0; // logical px around a corner or edge

  Size? _size; // picture size in pixels
  Rect _box = const Rect.fromLTRB(0.15, 0.15, 0.85, 0.85);
  _Grip? _grip;

  @override
  void initState() {
    super.initState();
    decodeImageFromList(widget.image).then((img) {
      if (mounted) setState(() => _size = Size(img.width.toDouble(), img.height.toDouble()));
    });
  }

  _Grip _gripAt(Offset p, Rect box) {
    bool near(double a, double b) => (a - b).abs() < _gripReach;
    final l = near(p.dx, box.left), r = near(p.dx, box.right);
    final t = near(p.dy, box.top), b = near(p.dy, box.bottom);
    final inX = p.dx > box.left - _gripReach && p.dx < box.right + _gripReach;
    final inY = p.dy > box.top - _gripReach && p.dy < box.bottom + _gripReach;
    if (t && l) return _Grip.tl;
    if (t && r) return _Grip.tr;
    if (b && l) return _Grip.bl;
    if (b && r) return _Grip.br;
    if (l && inY) return _Grip.l;
    if (r && inY) return _Grip.r;
    if (t && inX) return _Grip.t;
    if (b && inX) return _Grip.b;
    return _Grip.move;
  }

  void _drag(Offset delta, Size area) {
    final dx = delta.dx / area.width, dy = delta.dy / area.height;
    var b = _box;
    double clampX(double v) => v.clamp(0.0, 1.0);
    switch (_grip) {
      case _Grip.move:
        final nx = (b.left + dx).clamp(0.0, 1 - b.width), ny = (b.top + dy).clamp(0.0, 1 - b.height);
        b = Rect.fromLTWH(nx, ny, b.width, b.height);
      case _Grip.tl:
        b = Rect.fromLTRB(math.min(clampX(b.left + dx), b.right - _minSize),
            math.min(clampX(b.top + dy), b.bottom - _minSize), b.right, b.bottom);
      case _Grip.tr:
        b = Rect.fromLTRB(b.left, math.min(clampX(b.top + dy), b.bottom - _minSize),
            math.max(clampX(b.right + dx), b.left + _minSize), b.bottom);
      case _Grip.bl:
        b = Rect.fromLTRB(math.min(clampX(b.left + dx), b.right - _minSize), b.top, b.right,
            math.max(clampX(b.bottom + dy), b.top + _minSize));
      case _Grip.br:
        b = Rect.fromLTRB(b.left, b.top, math.max(clampX(b.right + dx), b.left + _minSize),
            math.max(clampX(b.bottom + dy), b.top + _minSize));
      case _Grip.l:
        b = Rect.fromLTRB(math.min(clampX(b.left + dx), b.right - _minSize), b.top, b.right, b.bottom);
      case _Grip.r:
        b = Rect.fromLTRB(b.left, b.top, math.max(clampX(b.right + dx), b.left + _minSize), b.bottom);
      case _Grip.t:
        b = Rect.fromLTRB(b.left, math.min(clampX(b.top + dy), b.bottom - _minSize), b.right, b.bottom);
      case _Grip.b:
        b = Rect.fromLTRB(b.left, b.top, b.right, math.max(clampX(b.bottom + dy), b.top + _minSize));
      case null:
        return;
    }
    setState(() => _box = b);
  }

  @override
  Widget build(BuildContext context) {
    final size = _size;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        title: Text('Crop', style: display(fontSize: 19)),
        actions: [
          TextButton(
            onPressed: () => setState(() => _box = const Rect.fromLTRB(0, 0, 1, 1)),
            child: const Text('Reset'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kAccent, foregroundColor: kOnAccent),
              onPressed: size == null ? null : () => Navigator.pop(context, _box),
              child: const Text('Crop'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: size == null
            ? const Center(child: CircularProgressIndicator(color: kAccent))
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: size.width / size.height,
                    child: LayoutBuilder(builder: (context, c) {
                      final area = c.biggest;
                      final box = Rect.fromLTRB(_box.left * area.width, _box.top * area.height,
                          _box.right * area.width, _box.bottom * area.height);
                      return GestureDetector(
                        onPanStart: (d) {
                          _grip = _gripAt(d.localPosition, box);
                          HapticFeedback.selectionClick();
                        },
                        onPanUpdate: (d) => _drag(d.delta, area),
                        onPanEnd: (_) => _grip = null,
                        child: Stack(fit: StackFit.expand, children: [
                          Image.memory(widget.image, fit: BoxFit.fill),
                          CustomPaint(painter: _BoxPainter(box)),
                        ]),
                      );
                    }),
                  ),
                ),
              ),
      ),
    );
  }
}

class _BoxPainter extends CustomPainter {
  final Rect box;
  _BoxPainter(this.box);

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.6);
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRect(box)),
      dim,
    );
    canvas.drawRect(
      box,
      Paint()
        ..color = kAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Rule of thirds, faint.
    final thirds = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = box.left + box.width * i / 3, y = box.top + box.height * i / 3;
      canvas.drawLine(Offset(x, box.top), Offset(x, box.bottom), thirds);
      canvas.drawLine(Offset(box.left, y), Offset(box.right, y), thirds);
    }
    // Corner grips.
    final grip = Paint()
      ..color = kAccent
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const len = 16.0;
    for (final (c, sx, sy) in [
      (box.topLeft, 1.0, 1.0),
      (box.topRight, -1.0, 1.0),
      (box.bottomLeft, 1.0, -1.0),
      (box.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(c, c + Offset(len * sx, 0), grip);
      canvas.drawLine(c, c + Offset(0, len * sy), grip);
    }
  }

  @override
  bool shouldRepaint(_BoxPainter old) => old.box != box;
}
