/// Your hand.
///
/// Cards overlap so a 15-card Canasta hand still fits a phone, and the selected
/// card lifts clear of its neighbours so you can see what you picked up. Cards
/// with no legal move right now are dimmed rather than removed — knowing a card
/// is stuck is information worth having.
library;

import 'package:flutter/material.dart';

import '../../engine/cards.dart';
import '../theme.dart';
import 'playing_card.dart';

class HandFan extends StatelessWidget {
  final List<CardId> cards;
  final CardId? selected;
  final Set<CardId> playable;

  /// Dim the unplayable cards. Off during the draw phase, when nothing in hand
  /// is playable yet and dimming the whole hand would just look broken.
  final bool markUnplayable;

  final ValueChanged<CardId> onTap;

  const HandFan({
    super.key,
    required this.cards,
    required this.selected,
    required this.playable,
    required this.onTap,
    this.markUnplayable = true,
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return SizedBox(
        height: 96,
        child: Center(
          child: Text('Your hand is empty', style: T.body(13, color: C.ashDim)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Shrink the overlap until the hand fits, down to a floor that keeps
        // each card's rank corner visible.
        const maxCardWidth = 76.0;
        final available = constraints.maxWidth - 24;
        var cardWidth = maxCardWidth;
        var step = cardWidth * 0.62;
        final needed = cardWidth + step * (cards.length - 1);
        if (needed > available) {
          final minStep = cardWidth * 0.30;
          step = ((available - cardWidth) / (cards.length - 1)).clamp(
            minStep,
            step,
          );
          final stillNeeded = cardWidth + step * (cards.length - 1);
          if (stillNeeded > available) {
            final scale = available / stillNeeded;
            cardWidth *= scale;
            step *= scale;
          }
        }

        final height = cardWidth / kCardAspect + 18;
        return SizedBox(
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < cards.length; i++)
                AnimatedPositioned(
                  key: ValueKey('${cards[i]}-$i'),
                  duration: Motion.of(context, Motion.base),
                  curve: Motion.curve,
                  left: 12 + i * step,
                  bottom: cards[i] == selected ? 16 : 0,
                  child: PlayingCard(
                    card: cards[i],
                    width: cardWidth,
                    selected: cards[i] == selected,
                    dimmed: markUnplayable && !playable.contains(cards[i]),
                    onTap: () => onTap(cards[i]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
