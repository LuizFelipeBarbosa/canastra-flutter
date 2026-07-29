/// A meld on the table, and the seal it earns at seven cards.
///
/// The seal is the signature moment of this game: making a canastra is what a
/// whole round is spent working toward, so it gets stamped on, at an angle, the
/// instant it happens — gold for limpa (no wilds), pink for suja. The colour is
/// the same one the app uses for wilds everywhere else, so the reason a
/// canastra is only worth half shows up in the badge itself.
library;

import 'package:flutter/material.dart';

import '../../game/move_index.dart';
import '../../engine/cards.dart';
import '../../multiplayer/table_view.dart';
import '../theme.dart';
import 'playing_card.dart';
import 'suit_pip.dart';

class MeldStrip extends StatefulWidget {
  final MeldView meld;
  final double cardWidth;

  /// The selected card can legally be added here.
  final bool isTarget;
  final VoidCallback? onTap;

  const MeldStrip({
    super.key,
    required this.meld,
    this.cardWidth = 42,
    this.isTarget = false,
    this.onTap,
  });

  @override
  State<MeldStrip> createState() => _MeldStripState();
}

class _MeldStripState extends State<MeldStrip>
    with SingleTickerProviderStateMixin {
  // Built eagerly rather than lazily: a `late final` controller whose first
  // read is dispose() would create a ticker against an already-deactivated
  // element, which is exactly what happens to a meld that never becomes a
  // canastra.
  late final AnimationController _seal;

  @override
  void initState() {
    super.initState();
    _seal = AnimationController(
      vsync: this,
      duration: Motion.stamp,
      value: widget.meld.isCanastra ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(MeldStrip old) {
    super.didUpdateWidget(old);
    if (widget.meld.isCanastra && !old.meld.isCanastra) {
      if (Motion.reduced(context)) {
        _seal.value = 1;
      } else {
        _seal.forward(from: 0);
      }
    } else if (!widget.meld.isCanastra && old.meld.isCanastra) {
      _seal.value = 0;
    }
  }

  @override
  void dispose() {
    _seal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meld = widget.meld;
    final w = widget.cardWidth;
    final overlap = w * 0.42;
    final stripWidth = w + overlap * (meld.size - 1);
    final accent = meld.isClean ? C.limpa : C.coringa;

    return Semantics(
      label:
          '${meldLabel(meld)}, ${meld.size} cards'
          '${meld.isCanastra ? ', canastra' : ''}',
      button: widget.onTap != null,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.quick),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(
              alpha: widget.isTarget ? 0.10 : 0.22,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isTarget
                  ? C.mint
                  : meld.isCanastra
                  ? accent.withValues(alpha: 0.55)
                  : C.line,
              width: widget.isTarget ? 2 : 1,
            ),
            boxShadow: widget.isTarget
                ? [
                    BoxShadow(
                      color: C.mint.withValues(alpha: 0.30),
                      blurRadius: 12,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: stripWidth,
                height: w / kCardAspect,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < meld.cards.length; i++)
                      Positioned(
                        left: i * overlap,
                        child: PlayingCard(
                          card: meld.cards[i],
                          width: w,
                          asWild: meld.wildIndices.contains(i),
                        ),
                      ),
                    if (meld.isCanastra)
                      Positioned(
                        right: -w * 0.18,
                        top: -w * 0.14,
                        child: _CanastraSeal(
                          progress: _seal,
                          clean: meld.isClean,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // The strip lives in a horizontally scrolling shelf, so this row
              // has no width to flex into unless it is given the strip's.
              SizedBox(
                width: stripWidth,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        meldLabel(meld),
                        overflow: TextOverflow.ellipsis,
                        style: T.mono(10, color: C.ash),
                      ),
                    ),
                    // A run is named by its range plus its suit; repeating a
                    // full card here read as part of the range ("2-42").
                    if (meld.isSequence) ...[
                      const SizedBox(width: 4),
                      SuitPip(
                        suit: meld.suit!,
                        size: 9,
                        color: kRedSuits.contains(meld.suit)
                            ? C.suitRed
                            : C.ash,
                      ),
                    ],
                    const SizedBox(width: 8),
                    Text(
                      '${meld.points}',
                      style: T.mono(
                        10,
                        color: meld.isCanastra ? accent : C.ashDim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CanastraSeal extends StatelessWidget {
  final Animation<double> progress;
  final bool clean;

  const _CanastraSeal({required this.progress, required this.clean});

  @override
  Widget build(BuildContext context) {
    final accent = clean ? C.limpa : C.coringa;
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) {
        // Slams down and overshoots slightly, like a rubber stamp.
        final t = Curves.elasticOut.transform(progress.value.clamp(0, 1));
        return Opacity(
          opacity: progress.value.clamp(0, 1),
          child: Transform.rotate(
            angle: -0.22,
            child: Transform.scale(
              scale: 0.6 + 0.4 * t + (1 - t) * 0.9,
              child: child,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: C.night,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: accent, width: 1.6),
        ),
        child: Text(clean ? 'LIMPA' : 'SUJA', style: T.mono(9, color: accent)),
      ),
    );
  }
}
