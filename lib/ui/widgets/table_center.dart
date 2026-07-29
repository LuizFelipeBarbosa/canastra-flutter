/// The middle of the table: the stock, the discard pile and the mortos.
///
/// These three are where a turn begins and ends, so they sit together and glow
/// when you may use them. The pile shows its whole contents on demand because
/// every card in it arrived face up — hiding it would withhold public
/// information rather than protect anything.
library;

import 'package:flutter/material.dart';

import '../../engine/cards.dart';
import '../theme.dart';
import 'playing_card.dart';

class TableCenter extends StatelessWidget {
  final int stockCount;
  final List<CardId> trash;
  final List<int> mortoSizes;
  final List<bool> mortoTaken;
  final int mySide;

  final bool stockActive;
  final bool pileActive;
  final bool pileFrozen;
  final bool pileBlocked;

  final VoidCallback? onStock;
  final VoidCallback? onPile;
  final VoidCallback? onInspectPile;

  const TableCenter({
    super.key,
    required this.stockCount,
    required this.trash,
    required this.mortoSizes,
    required this.mortoTaken,
    required this.mySide,
    this.stockActive = false,
    this.pileActive = false,
    this.pileFrozen = false,
    this.pileBlocked = false,
    this.onStock,
    this.onPile,
    this.onInspectPile,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    // Three zones plus two mortos do not fit a 320pt phone; scrolling keeps
    // them all reachable at full size rather than shrinking them to
    // illegibility. The minWidth constraint centres the row whenever it
    // does fit, so on anything wider it never drifts to the left edge.
    builder: (context, constraints) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: constraints.maxWidth),
        child: _zones(),
      ),
    ),
  );

  Widget _zones() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Zone(
        label: 'Stock',
        caption: '$stockCount left',
        active: stockActive,
        onTap: stockActive ? onStock : null,
        child: stockCount == 0
            ? const _EmptySlot(text: 'Empty')
            : const _Deck(count: 2, faceDown: true),
      ),
      const SizedBox(width: 14),
      _Zone(
        label: 'Discard pile',
        caption: pileBlocked
            ? 'Blocked'
            : pileFrozen
            ? 'Frozen'
            : '${trash.length} card${trash.length == 1 ? '' : 's'}',
        captionColor: pileBlocked || pileFrozen ? C.coringa : null,
        active: pileActive,
        onTap: pileActive ? onPile : onInspectPile,
        child: trash.isEmpty
            ? const _EmptySlot(text: 'Empty')
            : GestureDetector(
                onLongPress: onInspectPile,
                child: _Deck(
                  count: _peek(trash.length),
                  topCards: trash.sublist(trash.length - _peek(trash.length)),
                ),
              ),
      ),
      if (mortoSizes.isNotEmpty) ...[
        const SizedBox(width: 14),
        _Zone(
          label: 'Morto',
          caption: mortoTaken[mySide] ? 'Yours is taken' : 'Waiting',
          captionColor: mortoTaken[mySide] ? C.mint : null,
          child: Row(
            children: [
              for (var side = 0; side < mortoSizes.length; side++)
                Padding(
                  padding: EdgeInsets.only(left: side == 0 ? 0 : 6),
                  child: Opacity(
                    opacity: mortoSizes[side] == 0 ? 0.30 : 1,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PlayingCard(card: 0, width: 40, faceDown: true),
                        if (side == mySide)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: C.night,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: C.mint, width: 1),
                            ),
                            child: Text(
                              'YOURS',
                              style: T.mono(7, color: C.mint),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ],
  );

  /// How many of the pile's top cards to fan out.
  static int _peek(int length) => length < 3 ? length : 3;
}

class _Zone extends StatelessWidget {
  final String label;
  final String caption;
  final Color? captionColor;
  final bool active;
  final Widget child;
  final VoidCallback? onTap;

  const _Zone({
    required this.label,
    required this.caption,
    required this.child,
    this.captionColor,
    this.active = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label, $caption',
    button: onTap != null,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.quick),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.black.withValues(alpha: active ? 0.10 : 0.20),
          border: Border.all(
            color: active ? C.mint : C.line,
            width: active ? 2 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: C.mint.withValues(alpha: 0.30),
                    blurRadius: 14,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Eyebrow(label),
            const SizedBox(height: 6),
            SizedBox(height: 54 / kCardAspect + 8, child: child),
            const SizedBox(height: 4),
            Text(caption, style: T.mono(9, color: captionColor ?? C.ash)),
          ],
        ),
      ),
    ),
  );
}

/// A few cards stacked with a small offset, so a pile reads as physical.
///
/// The size is explicit: a bare [Stack] of positioned children has nothing to
/// measure itself against and fails to lay out inside a scrolling row.
class _Deck extends StatelessWidget {
  final int count;
  final bool faceDown;

  /// Bottom-to-top; the last one ends up on top. Ignored when [faceDown].
  final List<CardId> topCards;

  const _Deck({
    required this.count,
    this.faceDown = false,
    this.topCards = const [],
  });

  static const double _cardWidth = 54;
  static const double _offset = 2.5;

  @override
  Widget build(BuildContext context) {
    final layers = count < 1 ? 1 : count;
    return SizedBox(
      width: _cardWidth + _offset * (layers - 1),
      height: _cardWidth / kCardAspect + _offset * (layers - 1),
      child: Stack(
        children: [
          for (var i = 0; i < layers; i++)
            Positioned(
              left: i * _offset,
              top: i * _offset,
              child: PlayingCard(
                card: faceDown || i >= topCards.length ? 0 : topCards[i],
                width: _cardWidth,
                faceDown: faceDown,
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  final String text;
  const _EmptySlot({required this.text});

  @override
  Widget build(BuildContext context) => Container(
    width: 54,
    height: 54 / kCardAspect,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: C.line),
    ),
    alignment: Alignment.center,
    child: Text(text, style: T.mono(8, color: C.ashDim)),
  );
}
