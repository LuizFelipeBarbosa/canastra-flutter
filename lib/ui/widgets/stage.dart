/// The table, and the room it sits in.
///
/// Every screen is laid out at one fixed size and then scaled to fit, the way a
/// real table does not rearrange itself when you stand further back. That makes
/// the whole design one coordinate space — a card at (620, 596) is at (620, 596)
/// on every display — which is what lets the table be positioned absolutely
/// instead of negotiated by a dozen nested flexes.
///
/// It never scales *up*: past life size the table stops growing and the room
/// around it gets bigger instead.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme.dart';

/// The one coordinate space the whole app is drawn in.
const Size kStage = Size(1240, 790);

class Stage extends StatelessWidget {
  final Palette palette;

  /// Positioned children, in stage coordinates.
  final List<Widget> children;

  const Stage({super.key, required this.palette, required this.children});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: palette.shell,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.min(
          math.min(
            constraints.maxWidth / kStage.width,
            constraints.maxHeight / kStage.height,
          ),
          1,
        );
        if (constraints.maxHeight > constraints.maxWidth && scale < 0.5) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                context.copy.rotatePrompt,
                textAlign: TextAlign.center,
                style: T.title(18, color: palette.ash),
              ),
            ),
          );
        }
        return Center(
          child: FittedBox(
            // Exactly min(w / 1240, h / 790, 1).
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: kStage.width,
              height: kStage.height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: groundGradient(palette)),
                  child: CustomPaint(
                    painter: AzulejoPainter(ink: palette.motifInk),
                    child: Stack(children: children),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// An Athos Bulcão-style azulejo field: one quarter-circle arc per tile, rotated
/// by a hash of the tile's position so the field reads as hand-laid rather than
/// tiled. It sits at very low contrast — it should be felt more than seen, and
/// must never compete with a card.
class AzulejoPainter extends CustomPainter {
  static const double tile = 56;
  final Color ink;

  const AzulejoPainter({required this.ink});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = ink;

    final cols = (size.width / tile).ceil() + 1;
    final rows = (size.height / tile).ceil() + 1;

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        // Deterministic pseudo-rotation: no RNG, so the field never shimmers
        // between frames or differs across devices.
        final quarter = ((col * 7 + row * 13) ~/ 3 + col * row) % 4;
        canvas.save();
        canvas.translate(col * tile + tile / 2, row * tile + tile / 2);
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
  bool shouldRepaint(covariant AzulejoPainter old) => old.ink != ink;
}

/// The monogram: a filled azulejo quarter-tile with the buraco punched through
/// it, and a mint ring around the void. One shape carries both halves of the
/// name — the tile is the table, the hole is the game.
class BrandMark extends StatelessWidget {
  final double size;
  final Palette palette;

  /// The ring reads thin at small sizes, so the table's smaller mark asks for
  /// a heavier one.
  final double ring;

  const BrandMark({
    super.key,
    required this.size,
    required this.palette,
    this.ring = 5,
  });

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _MarkPainter(palette: palette, ring: ring),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  final Palette palette;
  final double ring;

  const _MarkPainter({required this.palette, required this.ring});

  /// The mark is drawn in a 120-unit box and scaled to whatever it is given.
  static const double _box = 120;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _box, size.height / _box);

    const corner = Offset(12, 12);
    const radius = 96.0;
    final tile = Path()
      ..moveTo(corner.dx, corner.dy)
      ..lineTo(corner.dx + radius, corner.dy)
      ..arcTo(
        Rect.fromCircle(center: corner, radius: radius),
        0,
        math.pi / 2,
        false,
      )
      ..close();
    canvas.drawPath(tile, Paint()..color = palette.markFill);

    const hole = Offset(54, 50);
    const holeRadius = 19.0;
    canvas.drawCircle(hole, holeRadius, Paint()..color = palette.markVoid);
    canvas.drawCircle(
      hole,
      holeRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring
        ..color = palette.mint,
    );
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) =>
      old.palette != palette || old.ring != ring;
}

/// The wordmark beside the monogram.
class BrandWord extends StatelessWidget {
  final Palette palette;
  final double size;

  const BrandWord({super.key, required this.palette, this.size = 26});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'BURACO',
        style: T.display(size, tracking: -1, color: palette.text, height: 0.95),
      ),
      Text(
        'LIVRE',
        style: mono(
          size * (10 / 26),
          color: palette.mint,
          tracking: size * (5.2 / 26),
          height: 1.2,
        ),
      ),
    ],
  );
}
