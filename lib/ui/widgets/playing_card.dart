/// The card.
///
/// One widget renders every card in the app — hand, meld, pile, morto — so a
/// three of hearts looks identical wherever it appears. State that matters to
/// the rules is drawn, not implied: a card acting as a wild wears a [C.coringa]
/// band, a legal destination glows [C.mint], and a card you cannot use right
/// now is dimmed rather than hidden.
library;

import 'package:flutter/material.dart';

import '../../engine/cards.dart';
import '../theme.dart';
import 'suit_pip.dart';

/// Standard playing-card proportion (2.5 × 3.5in).
const double kCardAspect = 0.7;

class PlayingCard extends StatelessWidget {
  final CardId card;
  final double width;

  /// The card is face down — a stock card, another player's hand, a morto.
  final bool faceDown;

  /// This card is currently acting as a wild inside a meld.
  final bool asWild;

  final bool selected;

  /// A legal destination or a playable card right now.
  final bool highlighted;

  /// Not playable in the current context.
  final bool dimmed;

  final VoidCallback? onTap;

  const PlayingCard({
    super.key,
    required this.card,
    this.width = 64,
    this.faceDown = false,
    this.asWild = false,
    this.selected = false,
    this.highlighted = false,
    this.dimmed = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final height = width / kCardAspect;
    final radius = BorderRadius.circular(width * 0.11);

    final Color edge;
    if (selected) {
      edge = C.mint;
    } else if (highlighted) {
      edge = C.mint.withValues(alpha: 0.75);
    } else if (asWild) {
      edge = C.coringa;
    } else {
      edge = C.boneEdge;
    }

    return Semantics(
      label: faceDown ? 'Face-down card' : cardLabel(card),
      button: onTap != null,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.quick),
          curve: Motion.curve,
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: faceDown ? C.cardBack : C.bone,
            borderRadius: radius,
            border: Border.all(
              color: edge,
              width: selected || highlighted || asWild ? 2.0 : 1.0,
            ),
            boxShadow: [
              if (selected || highlighted)
                BoxShadow(
                  color: C.mint.withValues(alpha: 0.35),
                  blurRadius: 14,
                  spreadRadius: 1,
                )
              else
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
            ],
          ),
          foregroundDecoration: dimmed
              ? BoxDecoration(
                  borderRadius: radius,
                  color: C.night.withValues(alpha: 0.55),
                )
              : null,
          child: faceDown
              ? _CardBack(width: width)
              : _CardFace(card: card, width: width, asWild: asWild),
        ),
      ),
    );
  }
}

class _CardFace extends StatelessWidget {
  final CardId card;
  final double width;
  final bool asWild;

  const _CardFace({
    required this.card,
    required this.width,
    this.asWild = false,
  });

  @override
  Widget build(BuildContext context) {
    if (card == kJoker) {
      // No star glyph: the display face has none, and a fallback would render
      // differently on every platform.
      return Stack(
        children: [
          Positioned(
            left: width * 0.09,
            top: width * 0.07,
            child: Text('JK', style: T.rank(width * 0.30, color: C.coringa)),
          ),
          Center(
            child: Transform.rotate(
              angle: -0.5,
              child: Text(
                'JOKER',
                style: T.mono(width * 0.15, color: C.coringa),
              ),
            ),
          ),
        ],
      );
    }

    final rank = kRankNames[card % 13];
    final suit = card ~/ 13;
    final ink = isRed(card) ? C.suitRed : C.suitBlack;

    return Stack(
      children: [
        Positioned(
          left: width * 0.09,
          top: width * 0.07,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rank, style: T.rank(width * 0.34, color: ink)),
              SizedBox(height: width * 0.03),
              SuitPip(suit: suit, size: width * 0.24, color: ink),
            ],
          ),
        ),
        // The corner index is the whole card. A large centre pip would only be
        // visible on the one card at the end of a fan, so it read as noise
        // rather than decoration and is deliberately not here.
        if (asWild)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: width * 0.17,
              color: C.coringa,
              alignment: Alignment.center,
              child: Text(
                'WILD',
                style: T.mono(width * 0.11, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}

class _CardBack extends StatelessWidget {
  final double width;
  const _CardBack({required this.width});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(width * 0.09),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.06),
        border: Border.all(color: C.mint.withValues(alpha: 0.30)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            C.mint.withValues(alpha: 0.10),
            C.coringa.withValues(alpha: 0.10),
          ],
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
