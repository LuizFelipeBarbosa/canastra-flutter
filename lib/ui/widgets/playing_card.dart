/// The card.
///
/// One widget renders every card in the app — hand, meld, pile, morto — so a
/// three of hearts looks identical wherever it appears. It is always drawn at
/// exactly one size and scaled by whoever places it, so a melded card is the
/// same object as a held one seen from further away rather than a second, redrawn
/// design that happens to be smaller.
///
/// State that matters to the rules is drawn, not implied: a card acting as a wild
/// wears a [Palette.pink] band, a selected one is edged and haloed
/// [Palette.mint], and nothing else on a card carries colour.
library;

import 'package:flutter/material.dart';

import '../../engine/cards.dart';
import '../theme.dart';
import 'suit_pip.dart';

/// Life size, and a standard playing-card proportion (2.5 × 3.5in).
const double kCardWidth = 76;
const double kCardHeight = 108.6;
const double kCardAspect = kCardWidth / kCardHeight;

class PlayingCard extends StatelessWidget {
  final CardId card;
  final Palette palette;

  /// A stock card, another player's hand, an untaken morto.
  final bool faceDown;

  /// This card is currently standing in for another one inside a meld.
  final bool asWild;

  /// Picked up, waiting to be played.
  final bool selected;

  const PlayingCard({
    super.key,
    required this.card,
    required this.palette,
    this.faceDown = false,
    this.asWild = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;

    final Color edge;
    if (selected) {
      edge = p.mint;
    } else if (asWild) {
      edge = p.pink;
    } else {
      edge = p.cardEdge;
    }

    return Semantics(
      label: faceDown ? 'Face-down card' : cardLabel(card),
      selected: selected,
      child: SizedBox(
        width: kCardWidth,
        height: kCardHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: faceDown ? p.cardBack : p.cardBg,
            borderRadius: BorderRadius.circular(8.4),
            border: Border.all(color: edge, width: selected || asWild ? 2 : 1),
            boxShadow: selected
                ? p.glowShadow(blur: 16, spread: 2)
                : p.cardShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8.4),
            child: faceDown
                ? _Back(palette: p)
                : _Face(card: card, palette: p, asWild: asWild),
          ),
        ),
      ),
    );
  }
}

class _Face extends StatelessWidget {
  final CardId card;
  final Palette palette;
  final bool asWild;

  const _Face({
    required this.card,
    required this.palette,
    required this.asWild,
  });

  @override
  Widget build(BuildContext context) {
    // A joker has no rank and no suit; it is only ever a wild, so it says so
    // where every other card names itself.
    final isTheJoker = card == kJoker;
    final ink = isTheJoker
        ? palette.pink
        : isRed(card)
        ? palette.suitRed
        : palette.suitBlack;

    return Stack(
      children: [
        Positioned(
          left: 7,
          top: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isTheJoker ? 'JK' : kRankNames[card % 13],
                style: T.display(26, tracking: -1, color: ink),
              ),
              const SizedBox(height: 2),
              if (!isTheJoker)
                SuitPip(suit: card ~/ 13, size: 18, color: ink)
              else
                const SizedBox(height: 18),
            ],
          ),
        ),
        // The corner index is the whole card. A large centre pip would only be
        // visible on the card at the end of a fan, so it read as noise rather
        // than decoration and is deliberately not here.
        if (asWild || isTheJoker)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 13,
              color: palette.pink,
              alignment: Alignment.center,
              child: Text('WILD', style: mono(8, color: Colors.white)),
            ),
          ),
      ],
    );
  }
}

class _Back extends StatelessWidget {
  final Palette palette;
  const _Back({required this.palette});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(7),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: palette.backLine),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.backA, palette.backB],
        ),
      ),
    ),
  );
}

/// Spoken and screen-reader name for a card, e.g. "Queen of hearts".
String cardLabel(CardId ct) {
  if (ct == kJoker) return 'Joker';
  const ranks = [
    'Ace',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
    'Jack',
    'Queen',
    'King',
  ];
  const suits = ['clubs', 'diamonds', 'hearts', 'spades'];
  return '${ranks[ct % 13]} of ${suits[ct ~/ 13]}';
}
