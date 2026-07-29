/// Naming a card in running text.
///
/// "9♣" cannot be written as a string here — no bundled font has the suit
/// characters, so any label containing one renders as a blank box. These build
/// the name as text plus a painted [SuitPip] instead, which is why prompts and
/// move lists take structured card ids rather than pre-formatted strings.
library;

import 'package:flutter/material.dart';

import '../../engine/cards.dart';
import '../theme.dart';
import 'suit_pip.dart';

/// Inline spans naming [card], e.g. a `9` followed by a small clubs pip.
List<InlineSpan> cardSpans(CardId card, TextStyle style) {
  if (card == kJoker) {
    return [TextSpan(text: 'Joker', style: style)];
  }
  final ink = isRed(card) ? C.suitRed : style.color ?? C.bone;
  final size = (style.fontSize ?? 14) * 0.82;
  return [
    TextSpan(
      text: kRankNames[card % 13],
      style: style.copyWith(color: ink),
    ),
    WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: EdgeInsets.only(left: size * 0.16, right: size * 0.10),
        child: SuitPip(suit: card ~/ 13, size: size, color: ink),
      ),
    ),
  ];
}

/// A sentence with card names in it, e.g. "Discard " + 9♣.
class CardSentence extends StatelessWidget {
  final String prefix;
  final List<CardId> cards;
  final TextStyle style;
  final String? suffix;

  const CardSentence({
    super.key,
    required this.prefix,
    required this.cards,
    required this.style,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        if (prefix.isNotEmpty) TextSpan(text: prefix, style: style),
        for (final c in cards) ...cardSpans(c, style),
        if (suffix != null) TextSpan(text: suffix, style: style),
      ],
    ),
    overflow: TextOverflow.ellipsis,
  );
}

/// Screen-reader and fallback text for a card. Words, not glyphs.
String cardWords(CardId ct) {
  if (ct == kJoker) return 'joker';
  const suits = ['clubs', 'diamonds', 'hearts', 'spades'];
  return '${kRankNames[ct % 13]} of ${suits[ct ~/ 13]}';
}
