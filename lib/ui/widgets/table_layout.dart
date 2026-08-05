/// Card observations shared by the fluid table and its renderer.
///
/// [CardSpot] is the complete shape of one positioned card.
/// [CardIdentityTracker] carries a physical copy's identity as that observation
/// moves between the hand, piles, and melds, so animation keys remain stable.
/// [rankMajorOrder] supplies the table's alternate hand ordering without
/// coupling either concern to widget layout.
library;

import '../../engine/cards.dart';

/// How much of life size an opponent's transient deal card is drawn at.
const double kOpponentScale = 0.42;

/// Where a card sits, and how it should look there.
class CardSpot {
  /// Identity across rebuilds. A card type is held and melded many times over a
  /// two-deck game, so this is a place-and-copy identifier rather than the card
  /// itself — it is what makes the same widget follow the same card as it moves.
  final String key;

  final CardId card;
  final double x;
  final double y;
  final double scale;
  final int z;

  final bool faceUp;
  final bool asWild;
  final bool selected;

  /// In your hand, and therefore something you can pick up.
  final bool inHand;

  /// Which of the hand's identically-typed copies this is (0 = leftmost).
  /// Hand cards only; it is what a tap reports so the tapped twin is the one
  /// that rises.
  final int copy;

  const CardSpot({
    required this.key,
    required this.card,
    required this.x,
    required this.y,
    required this.scale,
    required this.z,
    required this.faceUp,
    this.asWild = false,
    this.selected = false,
    this.inHand = false,
    this.copy = 0,
  });

  CardSpot _withKey(String key) => CardSpot(
    key: key,
    card: card,
    x: x,
    y: y,
    scale: scale,
    z: z,
    faceUp: faceUp,
    asWild: asWild,
    selected: selected,
    inHand: inHand,
    copy: copy,
  );
}

/// Rewrites [CardSpot] keys to stable per-card-copy identities so the same
/// widget follows the same physical card as it moves between zones.
class CardIdentityTracker {
  final Map<CardId, List<_PreviousCardIdentity>> _previous = {};
  final Map<CardId, int> _nextOrdinal = {};

  void reset() {
    _previous.clear();
    _nextOrdinal.clear();
  }

  /// Call once per layout pass with the frame's spots in layout order.
  ///
  /// Positional keys remain useful as observations: an exact position is the
  /// strongest evidence that a copy stayed put, while the key's prefix tells us
  /// whether it merely shifted within a hand, pile, or individual meld. Only
  /// after preserving those matches can a cross-zone move claim a remaining
  /// identity, which is what lets a discarded card glide from hand to pile.
  List<CardSpot> assign(List<CardSpot> spots) {
    final currentByType = <CardId, List<_CurrentCardIdentity>>{};
    for (var i = 0; i < spots.length; i++) {
      final spot = spots[i];
      if (_isBackPlaceholder(spot.key)) continue;

      currentByType
          .putIfAbsent(spot.card, () => [])
          .add(
            _CurrentCardIdentity(
              spotIndex: i,
              location: _CardLocation.fromKey(spot.key),
            ),
          );
    }

    final ordinals = List<int?>.filled(spots.length, null);
    final next = <CardId, List<_PreviousCardIdentity>>{};
    for (final entry in currentByType.entries) {
      final previous = _previous[entry.key] ?? const [];
      final claimed = List<bool>.filled(previous.length, false);

      void matchPrevious(
        bool Function(_CardLocation current, _CardLocation previous) matches,
      ) {
        for (final current in entry.value) {
          if (ordinals[current.spotIndex] != null) continue;
          for (var i = 0; i < previous.length; i++) {
            if (claimed[i] ||
                !matches(current.location, previous[i].location)) {
              continue;
            }
            ordinals[current.spotIndex] = previous[i].ordinal;
            claimed[i] = true;
            break;
          }
        }
      }

      matchPrevious(
        (current, previous) =>
            current.zone == previous.zone && current.slot == previous.slot,
      );
      matchPrevious((current, previous) => current.zone == previous.zone);
      matchPrevious((current, previous) => true);

      var nextOrdinal = _nextOrdinal[entry.key] ?? 0;
      for (final current in entry.value) {
        if (ordinals[current.spotIndex] != null) continue;
        ordinals[current.spotIndex] = nextOrdinal;
        nextOrdinal++;
      }
      _nextOrdinal[entry.key] = nextOrdinal;

      next[entry.key] = [
        for (final current in entry.value)
          _PreviousCardIdentity(
            ordinal: ordinals[current.spotIndex]!,
            location: current.location,
          ),
      ];
    }

    _previous
      ..clear()
      ..addAll(next);

    return [
      for (var i = 0; i < spots.length; i++)
        if (ordinals[i] case final ordinal?)
          spots[i]._withKey('card:${spots[i].card}:$ordinal')
        else
          spots[i],
    ];
  }
}

class _CurrentCardIdentity {
  final int spotIndex;
  final _CardLocation location;

  const _CurrentCardIdentity({required this.spotIndex, required this.location});
}

class _PreviousCardIdentity {
  final int ordinal;
  final _CardLocation location;

  const _PreviousCardIdentity({required this.ordinal, required this.location});
}

class _CardLocation {
  final String zone;
  final String slot;

  const _CardLocation({required this.zone, required this.slot});

  factory _CardLocation.fromKey(String key) {
    final parts = key.split(':');
    final zone = parts.first == 'meld' && parts.length >= 3
        ? parts.take(3).join(':')
        : parts.first;
    return _CardLocation(zone: zone, slot: key);
  }
}

/// Stock, morto, and opponent-hand backs carry no card type in the player's
/// view. Letting their sentinel value consume a real ordinal would collide with
/// the valid card id zero, while their existing positional keys are already the
/// only identity the renderer can meaningfully preserve.
bool _isBackPlaceholder(String key) =>
    key.startsWith('stock:') ||
    key.startsWith('morto:') ||
    (key.startsWith('seat') && key.contains(':'));

/// Rank-major hand order: low ranks first, ties broken by suit, jokers last.
int rankMajorOrder(CardId a, CardId b) {
  if (isJoker(a) || isJoker(b)) {
    return (isJoker(a) ? 1 : 0) - (isJoker(b) ? 1 : 0);
  }
  final byRank = idRank(a)! - idRank(b)!;
  return byRank != 0 ? byRank : idSuit(a)! - idSuit(b)!;
}
