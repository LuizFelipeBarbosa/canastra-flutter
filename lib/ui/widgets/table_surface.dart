/// The table itself.
///
/// The motif is an Athos Bulcão-style azulejo field: one quarter-circle arc per
/// tile, rotated by a hash of the tile's position so the field reads as
/// hand-laid rather than tiled. It sits at very low contrast — it should be
/// felt more than seen, and must never compete with a card.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

class TableSurface extends StatelessWidget {
  final Widget child;
  const TableSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: RadialGradient(
        center: Alignment(0, -0.35),
        radius: 1.1,
        colors: [C.tableHi, C.table, C.night],
        stops: [0.0, 0.55, 1.0],
      ),
    ),
    child: CustomPaint(painter: _AzulejoPainter(), child: child),
  );
}

class _AzulejoPainter extends CustomPainter {
  static const double tile = 56;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.white.withValues(alpha: 0.035);

    final cols = (size.width / tile).ceil() + 1;
    final rows = (size.height / tile).ceil() + 1;

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        // Deterministic pseudo-rotation: no RNG, so the field never shimmers
        // between frames or differs across devices.
        final quarter = ((col * 7 + row * 13) ~/ 3 + col * row) % 4;
        final origin = Offset(col * tile, row * tile);
        canvas.save();
        canvas.translate(origin.dx + tile / 2, origin.dy + tile / 2);
        canvas.rotate(quarter * math.pi / 2);
        canvas.drawArc(
          Rect.fromCircle(center: Offset(-tile / 2, -tile / 2), radius: tile),
          0,
          math.pi / 2,
          false,
          paint,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AzulejoPainter oldDelegate) => false;
}
