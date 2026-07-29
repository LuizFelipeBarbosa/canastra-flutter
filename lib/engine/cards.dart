/// Card model and the card-type id space.
///
/// A card is identified only by type, never by physical instance. Ids are
/// suit-major: `ct = suit * 13 + rank`. Id 52 is the joker (all printed jokers
/// collapse into one fungible type); id 53 is a pad sentinel that is never
/// held, melded or discarded.
library;

/// A card-type id in `0..53`.
typedef CardId = int;

abstract final class Suit {
  static const int clubs = 0;
  static const int diamonds = 1;
  static const int hearts = 2;
  static const int spades = 3;

  static const List<int> values = [clubs, diamonds, hearts, spades];
}

abstract final class Rank {
  static const int ace = 0;
  static const int two = 1;
  static const int three = 2;
  static const int four = 3;
  static const int five = 4;
  static const int six = 5;
  static const int seven = 6;
  static const int eight = 7;
  static const int nine = 8;
  static const int ten = 9;
  static const int jack = 10;
  static const int queen = 11;
  static const int king = 12;

  static const List<int> values = [
    ace, two, three, four, five, six, seven,
    eight, nine, ten, jack, queen, king,
  ];
}

const CardId kJoker = 52;
const CardId kPad = 53;

/// Width of count vectors and per-card action dimensions.
const int kCardSpace = 54;

const Set<int> kRedSuits = {Suit.diamonds, Suit.hearts};

const List<String> kRankNames = [
  'A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K',
];
const List<String> kSuitSymbols = ['♣', '♦', '♥', '♠'];

/// Sequence position model: 14 positions per suit, 1 = ace-low, 2..13 = ranks
/// two..king, 14 = ace-high. No-wrap is automatic.
const int kPosMin = 1;
const int kPosMax = 14;

/// Rank occupying each sequence position; index 0 unused (positions are 1-based).
final List<int?> _rankAt = List<int?>.generate(
  kPosMax + 1,
  (p) => p < kPosMin ? null : (p == kPosMin || p == kPosMax ? Rank.ace : p - 1),
);

/// Natural card type at each `[suit][position]`; index 0 of the inner list unused.
final List<List<CardId?>> _nat = List.generate(
  4,
  (suit) => List<CardId?>.generate(
    kPosMax + 1,
    (p) => p < kPosMin ? null : suit * 13 + _rankAt[p]!,
  ),
);

final List<bool> _isRed = List.generate(
  53,
  (ct) => ct != kJoker && kRedSuits.contains(ct ~/ 13),
);

CardId cardId(int rank, int suit) => suit * 13 + rank;

/// Rank of `ct`, or null for the joker.
int? idRank(CardId ct) => ct == kJoker ? null : ct % 13;

/// Suit of `ct`, or null for the joker.
int? idSuit(CardId ct) => ct == kJoker ? null : ct ~/ 13;

bool isJoker(CardId ct) => ct == kJoker;

bool isRed(CardId ct) => _isRed[ct];

/// Rank occupying sequence position `pos` (1..14).
int rankAt(int pos) {
  if (pos < kPosMin || pos > kPosMax) {
    throw ArgumentError('position out of range: $pos');
  }
  return _rankAt[pos]!;
}

/// Natural card type at sequence position `pos` in `suit`.
CardId nat(int pos, int suit) {
  if (pos < kPosMin || pos > kPosMax) {
    throw ArgumentError('position out of range: $pos');
  }
  return _nat[suit][pos]!;
}

/// Sequence positions a rank may occupy (aces occupy two).
List<int> positionsOf(int rank) =>
    rank == Rank.ace ? const [kPosMin, kPosMax] : [rank + 1];

String rankName(CardId ct) => ct == kJoker ? 'JOKER' : kRankNames[ct % 13];

/// Human-readable card name, e.g. `A♣` or `Joker`.
String cardStr(CardId ct) {
  if (ct == kJoker) return 'Joker';
  if (ct == kPad) return '<pad>';
  return '${kRankNames[ct % 13]}${kSuitSymbols[ct ~/ 13]}';
}

/// Canonically ordered (unshuffled) full deck as card-type ids.
List<CardId> buildDeck(int deckCount, int printedJokers) => [
      for (var i = 0; i < deckCount; i++)
        for (var ct = 0; ct < 52; ct++) ct,
      for (var i = 0; i < printedJokers; i++) kJoker,
    ];
