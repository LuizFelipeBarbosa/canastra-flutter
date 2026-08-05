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

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/cards.dart';
import '../app_scope.dart';
import '../copy.dart';
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

  /// Uses the quieter table-stack shadow instead of the raised hand shadow.
  final bool flat;

  /// The scale the parent will apply after this fixed-size card is painted.
  ///
  /// Floors are evaluated at the final size so a small card does not have its
  /// minimum dimensions shrunk a second time by its parent's transform.
  final double renderScale;

  const PlayingCard({
    super.key,
    required this.card,
    required this.palette,
    this.faceDown = false,
    this.asWild = false,
    this.selected = false,
    this.flat = false,
    this.renderScale = 1.0,
  }) : assert(renderScale > 0);

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final l = context.copy;
    final effectiveW = kCardWidth * renderScale;
    final effectiveH = effectiveW / kCardAspect;

    final renderedRadius = effectiveW * 0.10 * p.cardRadiusFactor + 2;
    final radius = renderedRadius / renderScale;

    final Color edge;
    final double renderedBorderWidth;
    if (selected) {
      edge = p.mint;
      renderedBorderWidth = math.max(2.5, p.cardBorderW * 2);
    } else if (asWild) {
      edge = p.pink;
      renderedBorderWidth = math.max(2, p.cardBorderW * 1.4);
    } else {
      edge = p.cardEdge;
      // The floor keeps a reduced card edge from disappearing on low-density
      // displays, while the ceiling preserves the theme's intended weight.
      renderedBorderWidth = math.max(
        1,
        math.min(p.cardBorderW, p.cardBorderW * effectiveW / 62),
      );
    }
    final borderWidth = renderedBorderWidth / renderScale;

    final List<BoxShadow> shadows;
    if (selected) {
      final lift = effectiveW * 0.09 / renderScale;
      final blur = effectiveW * 0.17 / renderScale;
      final glowBlur = effectiveW * 0.20 / renderScale;
      shadows = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.42),
          offset: Offset(0, lift),
          blurRadius: blur,
        ),
        ...p.glowShadow(blur: glowBlur, spread: 0),
      ];
    } else if (flat) {
      shadows = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.20),
          offset: Offset(0, 1 / renderScale),
          blurRadius: 2 / renderScale,
        ),
      ];
    } else {
      final lift = effectiveW * 0.035 / renderScale;
      final blur = effectiveW * 0.08 / renderScale;
      shadows = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.30),
          offset: Offset(0, lift),
          blurRadius: blur,
        ),
      ];
    }

    return Semantics(
      label: faceDown ? l.faceDownCard : cardLabel(card, l, asWild: asWild),
      selected: selected,
      child: SizedBox(
        width: kCardWidth,
        height: kCardHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: faceDown ? p.cardBack : p.cardBg,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: edge, width: borderWidth),
            boxShadow: shadows,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: faceDown
                ? _Back(
                    palette: p,
                    renderScale: renderScale,
                    renderedRadius: renderedRadius,
                  )
                : _Face(
                    card: card,
                    palette: p,
                    asWild: asWild,
                    renderScale: renderScale,
                    effectiveW: effectiveW,
                    effectiveH: effectiveH,
                  ),
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
  final double renderScale;
  final double effectiveW;
  final double effectiveH;

  const _Face({
    required this.card,
    required this.palette,
    required this.asWild,
    required this.renderScale,
    required this.effectiveW,
    required this.effectiveH,
  });

  @override
  Widget build(BuildContext context) {
    // A joker has no suit; its short index occupies the same corner footprint
    // as a suited card so changing wild state never moves the rank.
    final isTheJoker = card == kJoker;
    final ink = isTheJoker
        ? palette.pink
        : isRed(card)
        ? palette.suitRed
        : palette.suitBlack;
    final rank = isTheJoker ? 'JK' : kRankNames[card % 13];
    final rankScale = rank.length > 1 ? 0.35 : 0.50;

    final left = effectiveW * 0.085 / renderScale;
    final top = effectiveW * 0.05 / renderScale;
    final cornerGap = effectiveW * 0.02 / renderScale;
    final renderedRankFontSize = math.max(10, effectiveW * rankScale);
    final rankFontSize = renderedRankFontSize / renderScale;
    // The pip floor keeps the smallest future table scale recognizable.
    final renderedPipSize = math.max(6, effectiveW * 0.29);
    final pipSize = renderedPipSize / renderScale;

    final renderedWildHeight = math.max(13, effectiveH * 0.14);
    final wildHeight = renderedWildHeight / renderScale;
    final renderedWildFontSize = math.max(8, effectiveW * 0.13);
    final wildFontSize = renderedWildFontSize / renderScale;

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                rank,
                style: T
                    .display(
                      rankFontSize,
                      tracking: rankFontSize * -0.05,
                      color: ink,
                    )
                    .copyWith(height: 0.9),
              ),
              SizedBox(height: cornerGap),
              if (!isTheJoker)
                SuitPip(suit: card ~/ 13, size: pipSize, color: ink)
              else
                SizedBox(width: pipSize, height: pipSize),
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
              height: wildHeight,
              color: palette.pink,
              alignment: Alignment.center,
              child: Text(
                context.copy.wild.toUpperCase(),
                style: mono(
                  wildFontSize,
                  tracking: wildFontSize * 0.06,
                  color: Colors.white,
                ).copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ),
      ],
    );
  }
}

class _Back extends StatelessWidget {
  final Palette palette;
  final double renderScale;
  final double renderedRadius;

  const _Back({
    required this.palette,
    required this.renderScale,
    required this.renderedRadius,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveW = kCardWidth * renderScale;
    final inset = effectiveW * 0.09 / renderScale;
    final radius = renderedRadius * 0.6 / renderScale;
    // The one-pixel floor prevents the inset keyline vanishing after scaling.
    final renderedBorderWidth = math.max(1, palette.cardBorderW * 0.8);
    final borderWidth = renderedBorderWidth / renderScale;

    return Padding(
      padding: EdgeInsets.all(inset),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.16),
            width: borderWidth,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.backA, palette.backB],
          ),
        ),
      ),
    );
  }
}

/// Spoken and screen-reader name for a card in the active language.
String cardLabel(CardId card, Copy copy, {bool asWild = false}) {
  if (card == kJoker) return copy.joker;

  final name = copy.cardName(card % 13, card ~/ 13);
  return asWild ? copy.wildCardName(name) : name;
}
