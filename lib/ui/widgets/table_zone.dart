/// A named place on the table: the stock, the discard pile, the mortos, and the
/// stretch of felt you lay new melds on.
///
/// A zone is a frame with a name at the top and a state at the bottom, and it
/// lights up mint exactly when it is somewhere you may play. The play area is
/// dashed because nothing is there yet — it is the one zone that is a space
/// rather than a pile.
library;

import 'dart:math' as math;

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

  /// Places the caption beside the stack area on a landscape table rail.
  final bool horizontalText;

  /// Reference card width used by the proportional frame and plus glyph.
  /// The default makes the radius the same 14px used by the fixed stage.
  final double zoneCardWidth;

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
    this.horizontalText = false,
    this.zoneCardWidth = 87.5,
  }) : assert(zoneCardWidth > 0);

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final radius = zoneCardWidth * 0.16;
    final borderWidth = math.max(1.75, p.cardBorderW * 1.3);
    // The clamp stops the invitation mark overwhelming either the smallest
    // slot or a generously sized future fluid layout.
    final plusFontSize = (zoneCardWidth * 0.44).clamp(16.0, 30.0);
    // Gold marks the one hot state that ends the round; every other legal
    // destination lights up mint, same as before the restyle.
    final accent = terminal ? p.gold : p.mint;

    return Semantics(
      label: '$label, $foot',
      button: onTap != null,
      child: Hoverable(
        onTap: onTap,
        builder: (hovered) {
          final lit = hot || (hovered && onTap != null);
          final borderColor = dashed
              ? (lit ? accent : p.line)
              : (lit ? accent : Colors.transparent);
          // A discard that ends the round gets a warmer, goldwash fill
          // instead of the ordinary mint highlight.
          final litBackground = terminal ? p.goldWash : p.panelHot;
          final labelFontSize = 9.0;
          final labelTracking = labelFontSize * (dashed ? 0.14 : 0.17);
          final valueTracking = labelFontSize * 0.04;
          final labelText = Text(
            label,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: mono(
              labelFontSize,
              tracking: labelTracking,
              color: lit && dashed ? accent : p.ashDim,
            ).copyWith(fontWeight: FontWeight.w500),
          );
          final footText = Text(
            foot,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: mono(
              labelFontSize,
              tracking: valueTracking,
              color: lit ? accent : p.ash,
            ).copyWith(fontWeight: FontWeight.w500),
          );
          final plus = ExcludeSemantics(
            child: Text(
              '+',
              style: mono(
                plusFontSize,
                color: lit ? accent : p.ashDim,
              ).copyWith(fontWeight: FontWeight.w600, height: 1),
            ),
          );

          return AnimatedContainer(
            duration: Motion.of(context, Motion.quick),
            decoration: BoxDecoration(
              // A transparent resting border keeps the frame's footprint
              // stable when it becomes a legal drop target.
              color: lit ? litBackground : Colors.transparent,
              borderRadius: BorderRadius.circular(radius),
              border: dashed
                  ? null
                  : Border.all(color: borderColor, width: borderWidth),
            ),
            foregroundDecoration: dashed
                ? _DashedBorder(
                    color: borderColor,
                    strokeWidth: borderWidth,
                    radius: radius,
                  )
                : null,
            // A zone's caption is allowed out over the felt: "click to discard"
            // is wider than the pile, and shrinking the pile to fit a sentence
            // that is only there sometimes would move the table around.
            child: Stack(
              clipBehavior: Clip.none,
              children: horizontalText
                  ? [
                      Positioned.fill(
                        child: Row(
                          children: [
                            Expanded(
                              child: dashed
                                  ? Center(child: plus)
                                  : const SizedBox.shrink(),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 11),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    labelText,
                                    const SizedBox(height: 4),
                                    footText,
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ]
                  : [
                      if (dashed) Positioned.fill(child: Center(child: plus)),
                      Positioned(left: 11, top: 8, child: labelText),
                      Positioned(left: 11, bottom: 6, child: footText),
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
