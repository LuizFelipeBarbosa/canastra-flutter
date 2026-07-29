/// Suit pips, drawn rather than typed.
///
/// ♠♥♦♣ are the one part of a card that absolutely must render, and no font we
/// can bundle guarantees them on every platform — the display face has no suit
/// glyphs at all, and falling back to a system font puts four different-looking
/// pips on four platforms. Painting them keeps the cards identical everywhere
/// and lets the shapes match the geometry of the rest of the design.
library;

import 'package:flutter/material.dart';

import '../../engine/cards.dart';

class SuitPip extends StatelessWidget {
  final int suit;
  final double size;
  final Color color;

  const SuitPip({
    super.key,
    required this.suit,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _SuitPainter(suit: suit, color: color),
    ),
  );
}

class _SuitPainter extends CustomPainter {
  final int suit;
  final Color color;

  const _SuitPainter({required this.suit, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(_path(suit, size), paint);
  }

  static Path _path(int suit, Size s) {
    final w = s.width;
    final h = s.height;
    switch (suit) {
      case Suit.diamonds:
        return Path()
          ..moveTo(w * 0.5, h * 0.04)
          ..lineTo(w * 0.90, h * 0.5)
          ..lineTo(w * 0.5, h * 0.96)
          ..lineTo(w * 0.10, h * 0.5)
          ..close();

      case Suit.hearts:
        return Path()
          ..moveTo(w * 0.5, h * 0.95)
          ..cubicTo(w * -0.10, h * 0.52, w * 0.10, h * 0.02, w * 0.5, h * 0.28)
          ..cubicTo(w * 0.90, h * 0.02, w * 1.10, h * 0.52, w * 0.5, h * 0.95)
          ..close();

      case Suit.spades:
        final body = Path()
          ..moveTo(w * 0.5, h * 0.05)
          ..cubicTo(w * 1.10, h * 0.46, w * 0.90, h * 0.86, w * 0.5, h * 0.66)
          ..cubicTo(w * 0.10, h * 0.86, w * -0.10, h * 0.46, w * 0.5, h * 0.05)
          ..close();
        return Path.combine(PathOperation.union, body, _stem(w, h));

      default: // clubs
        final r = w * 0.21;
        final clover = Path()
          ..addOval(
            Rect.fromCircle(center: Offset(w * 0.5, h * 0.24), radius: r),
          )
          ..addOval(
            Rect.fromCircle(center: Offset(w * 0.24, h * 0.56), radius: r),
          )
          ..addOval(
            Rect.fromCircle(center: Offset(w * 0.76, h * 0.56), radius: r),
          );
        return Path.combine(PathOperation.union, clover, _stem(w, h));
    }
  }

  /// The tapered stem shared by spades and clubs.
  static Path _stem(double w, double h) => Path()
    ..moveTo(w * 0.42, h * 0.98)
    ..cubicTo(w * 0.50, h * 0.80, w * 0.50, h * 0.72, w * 0.48, h * 0.55)
    ..lineTo(w * 0.52, h * 0.55)
    ..cubicTo(w * 0.50, h * 0.72, w * 0.50, h * 0.80, w * 0.58, h * 0.98)
    ..close();

  @override
  bool shouldRepaint(covariant _SuitPainter old) =>
      old.suit != suit || old.color != color;
}
