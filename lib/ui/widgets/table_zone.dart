/// A named place on the table: the stock, the discard pile, the mortos, and the
/// stretch of felt you lay new melds on.
///
/// A zone is a frame with a name at the top and a state at the bottom, and it
/// lights up mint exactly when it is somewhere you may play. The play area is
/// dashed because nothing is there yet — it is the one zone that is a space
/// rather than a pile.
library;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'controls.dart';

class TableZone extends StatelessWidget {
  final String label;
  final String foot;
  final Palette palette;

  /// A legal destination right now.
  final bool hot;

  /// Drawn dashed — the play area.
  final bool dashed;

  /// Going out: the one hot state that is gold, because it ends the round.
  final bool terminal;

  final VoidCallback? onTap;

  const TableZone({
    super.key,
    required this.label,
    required this.foot,
    required this.palette,
    this.hot = false,
    this.dashed = false,
    this.terminal = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final accent = terminal ? p.gold : p.mint;

    return Semantics(
      label: '$label, $foot',
      button: onTap != null,
      child: Hoverable(
        onTap: onTap,
        builder: (hovered) {
          final lit = hot || (hovered && onTap != null);
          final border = lit ? accent : p.line;
          final width = hot ? 2.0 : 1.0;
          return AnimatedContainer(
            duration: Motion.of(context, Motion.quick),
            decoration: BoxDecoration(
              // The play area has nothing in it, so it has nothing to shade —
              // until it is somewhere you may drop what you are holding.
              color: dashed
                  ? (lit ? p.panelHot : Colors.transparent)
                  : (lit ? p.panelHot : p.panel),
              borderRadius: BorderRadius.circular(14),
              border: dashed ? null : Border.all(color: border, width: width),
              boxShadow: hot ? p.glowShadow(blur: dashed ? 16 : 14) : null,
            ),
            foregroundDecoration: dashed
                ? _DashedBorder(color: border, strokeWidth: width, radius: 14)
                : null,
            // A zone's caption is allowed out over the felt: "click to discard"
            // is wider than the pile, and shrinking the pile to fit a sentence
            // that is only there sometimes would move the table around.
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 11,
                  top: 8,
                  child: Text(
                    label,
                    softWrap: false,
                    style: mono(9, color: lit && dashed ? accent : p.ashDim),
                  ),
                ),
                Positioned(
                  left: 11,
                  bottom: 6,
                  child: Text(
                    foot,
                    softWrap: false,
                    style: mono(9, color: lit ? accent : p.ash),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A dashed rounded rectangle. Flutter's [Border] has no dash pattern, so the
/// play area's outline is painted rather than decorated.
class _DashedBorder extends Decoration {
  final Color color;
  final double strokeWidth;
  final double radius;

  const _DashedBorder({
    required this.color,
    required this.strokeWidth,
    required this.radius,
  });

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _DashedPainter(this);
}

class _DashedPainter extends BoxPainter {
  final _DashedBorder spec;
  _DashedPainter(this.spec);

  static const double _dash = 6;
  static const double _gap = 5;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final size = cfg.size;
    if (size == null) return;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            offset.dx + spec.strokeWidth / 2,
            offset.dy + spec.strokeWidth / 2,
            size.width - spec.strokeWidth,
            size.height - spec.strokeWidth,
          ),
          Radius.circular(spec.radius),
        ),
      );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = spec.strokeWidth
      ..color = spec.color;

    for (final metric in outline.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = distance + _dash;
        canvas.drawPath(
          metric.extractPath(
            distance,
            end < metric.length ? end : metric.length,
          ),
          paint,
        );
        distance = end + _gap;
      }
    }
  }
}
