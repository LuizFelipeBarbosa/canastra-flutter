/// The table, and the room it sits in.
///
/// The table is laid out at one fixed size and then scaled to fit, the way a real
/// table does not rearrange itself when you stand further back. That makes it one
/// coordinate space — a card at (620, 596) is at (620, 596) on every display —
/// which is what lets it be positioned absolutely instead of negotiated by a dozen
/// nested flexes. It never scales *up*: past life size the table stops growing and
/// the room around it gets bigger instead.
///
/// There are two such spaces, because a phone held upright is not a short wide
/// display: [kStageLandscape] and [kStagePortrait]. A viewport gets whichever one
/// it can show at a readable size, and since a card keeps its identity across the
/// switch, rotating the device glides the whole table into its other arrangement
/// rather than rebuilding it.
///
/// Everything that is *not* the table — setting up a game, signing in, the
/// leaderboard — has no absolute geometry to protect, so it sits in a [Room]: the
/// same felt, but the sheet flows and scrolls at life size. Scaling a form would
/// only shrink its text and its tap targets, and inside a scaled box the soft
/// keyboard shrinks the viewport and with it the whole screen.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The coordinate space the table is drawn in on a display wider than it is tall.
const Size kStageLandscape = Size(1240, 790);

/// The coordinate space the table is drawn in on a phone held upright.
///
/// 420 is the width at which a fifteen-card hand still fans above the design's own
/// readability floor of a quarter of a card. 840 makes the aspect match a phone's
/// *safe* area rather than its whole screen, so the stage fills the display
/// instead of letterboxing above and below the notch.
const Size kStagePortrait = Size(420, 840);

/// Which stage a viewport gets, and how big it is.
class StageMetrics {
  final Size size;
  final bool portrait;

  const StageMetrics({required this.size, required this.portrait});

  /// Portrait exactly when the landscape stage would be too small to read.
  ///
  /// That is the rule the rotate prompt used to apply, answered now with a layout
  /// instead of an instruction — so every viewport that renders landscape today
  /// still renders landscape, at the same scale, by construction.
  factory StageMetrics.of(BoxConstraints constraints) {
    final landscapeScale = math.min(
      constraints.maxWidth / kStageLandscape.width,
      constraints.maxHeight / kStageLandscape.height,
    );
    final portrait =
        constraints.maxHeight > constraints.maxWidth && landscapeScale < 0.5;
    return StageMetrics(
      size: portrait ? kStagePortrait : kStageLandscape,
      portrait: portrait,
    );
  }
}

extension StageContext on BuildContext {
  /// Which stage this screen is on, read from the window rather than from a
  /// [LayoutBuilder] — for the screens that need to drop a column on a phone
  /// without owning the constraints themselves.
  StageMetrics get stage =>
      StageMetrics.of(BoxConstraints.tight(MediaQuery.sizeOf(this)));
}

class Stage extends StatelessWidget {
  final Palette palette;

  /// Positioned children, in the coordinates of the stage the viewport got.
  final List<Widget> Function(StageMetrics) children;

  const Stage({super.key, required this.palette, required this.children});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: palette.shell,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final metrics = StageMetrics.of(constraints);
        final table = FittedBox(
          // Exactly min(w / width, h / height, 1).
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: metrics.size.width,
            height: metrics.size.height,
            child: ClipRRect(
              // A portrait stage nearly fills the display, so there is no island
              // for its corners to be rounded against.
              borderRadius: BorderRadius.circular(metrics.portrait ? 0 : 6),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: groundGradient(palette),
                      ),
                      child: CustomPaint(
                        painter: AzulejoPainter(ink: palette.motifInk),
                      ),
                    ),
                  ),
                  Stack(children: children(metrics)),
                ],
              ),
            ),
          ),
        );
        // The insets are only load-bearing in portrait, where the stage runs
        // edge to edge. Applying them in landscape would shrink a phone's table
        // for a notch it already clears.
        return Center(child: metrics.portrait ? SafeArea(child: table) : table);
      },
    ),
  );
}

/// The room the table sits in, for every screen that is not the table.
///
/// In landscape it is the [Stage] with the screen floated on it, unchanged. In
/// portrait the felt goes full-bleed behind the safe area and the screen scrolls
/// at life size — there is no island to sit on when the stage nearly fills the
/// display, and a form is the one thing that must not be scaled.
class Room extends StatelessWidget {
  final Palette palette;
  final Widget child;

  const Room({super.key, required this.palette, required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!StageMetrics.of(constraints).portrait) {
        return Stage(
          palette: palette,
          children: (_) => [Positioned.fill(child: child)],
        );
      }
      return DecoratedBox(
        decoration: BoxDecoration(gradient: groundGradient(palette)),
        child: CustomPaint(
          painter: AzulejoPainter(ink: palette.motifInk),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, safe) => SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  // Tall enough to centre a short screen, free to grow past the
                  // fold when the content is long.
                  constraints: BoxConstraints(
                    minHeight: math.max(0, safe.maxHeight - 32),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      );
    },
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
