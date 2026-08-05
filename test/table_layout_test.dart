/// Tests for stable physical-card identities and the surviving hand ordering.
library;

import 'package:canastra/engine/cards.dart';
import 'package:canastra/ui/widgets/table_layout.dart';
import 'package:flutter_test/flutter_test.dart';

CardSpot _spot(String key, CardId card) =>
    CardSpot(key: key, card: card, x: 0, y: 0, scale: 1, z: 0, faceUp: true);

/// A spot still staged on the stock, the way the solver draws an undealt card —
/// same key and card, different everything else, exactly the shape
/// [CardIdentityTracker] is required to see through.
CardSpot _staged(String key, CardId card) => CardSpot(
  key: key,
  card: card,
  x: 17,
  y: 23,
  scale: 0.42,
  z: 9,
  faceUp: false,
);

List<CardSpot> _hand(List<CardId> cards) => [
  for (var i = 0; i < cards.length; i++) _spot('hand:$i', cards[i]),
];

Map<CardId, String> _keysByCard(Iterable<CardSpot> spots) => {
  for (final spot in spots) spot.card: spot.key,
};

void main() {
  group('CardIdentityTracker', () {
    test('carries a middle discard from hand to pile', () {
      final tracker = CardIdentityTracker();
      final first = tracker.assign(_hand(const [4, 5, 6, 7, 8]));
      final firstKeys = _keysByCard(first);

      final second = tracker.assign([
        _spot('pile:0', 6),
        ..._hand(const [4, 5, 7, 8]),
      ]);
      final secondKeys = _keysByCard(second);

      for (final card in const [4, 5, 7, 8]) {
        expect(secondKeys[card], firstKeys[card]);
      }
      expect(secondKeys[6], firstKeys[6]);
    });

    test('keeps meld identities when a low card shifts every index', () {
      final tracker = CardIdentityTracker();
      final first = tracker.assign([
        _spot('meld:me:0:0', 20),
        _spot('meld:me:0:1', 21),
        _spot('meld:me:0:2', 22),
      ]);
      final firstKeys = _keysByCard(first);

      // A card added to the low end shifts every existing card's slot within
      // the same meld, e.g. 20 was `meld:me:0:0` and is now `meld:me:0:1`.
      final second = tracker.assign([
        _spot('meld:me:0:0', 19),
        _spot('meld:me:0:1', 20),
        _spot('meld:me:0:2', 21),
        _spot('meld:me:0:3', 22),
      ]);
      final secondKeys = _keysByCard(second);

      for (final card in const [20, 21, 22]) {
        expect(secondKeys[card], firstKeys[card]);
      }
      expect(secondKeys[19], isNot(anyOf(firstKeys.values)));
    });

    test('distinguishes duplicate card types by stable slot', () {
      final tracker = CardIdentityTracker();
      // Two sevens in the same hand — a real shape once melds share a
      // two-deck pool with the hand.
      final first = tracker.assign([
        _spot('hand:0', 7),
        _spot('hand:1', 3),
        _spot('hand:2', 7),
        _spot('hand:3', 9),
      ]);
      final sevenAtSlot0 = first[0].key;
      final sevenAtSlot2 = first[2].key;
      expect(sevenAtSlot0, isNot(sevenAtSlot2));

      // Same hand again next frame — nothing moved, so each seven must keep
      // exactly the key it was given, not swap with the other.
      final second = tracker.assign([
        _spot('hand:0', 7),
        _spot('hand:1', 3),
        _spot('hand:2', 7),
        _spot('hand:3', 9),
      ]);
      expect(second[0].key, sevenAtSlot0);
      expect(second[2].key, sevenAtSlot2);
    });

    test('keeps identities while dealt cards land from the stock', () {
      final tracker = CardIdentityTracker();
      // Mid-deal: every hand card is still staged on the stock, but already
      // carries its eventual `hand:$i` key, exactly as the solver draws it.
      final staged = tracker.assign([
        _staged('hand:0', 11),
        _staged('hand:1', 12),
        _staged('hand:2', 13),
      ]);
      final stagedKeys = _keysByCard(staged);

      final landed = tracker.assign([
        _spot('hand:0', 11),
        _spot('hand:1', 12),
        _spot('hand:2', 13),
      ]);
      final landedKeys = _keysByCard(landed);

      for (final card in const [11, 12, 13]) {
        expect(landedKeys[card], stagedKeys[card]);
      }
      // No two cards in the landed hand collide on the same rewritten key.
      expect(landedKeys.values.toSet().length, landedKeys.length);
    });

    test('never recycles an ordinal after a copy leaves', () {
      final tracker = CardIdentityTracker();
      final first = tracker.assign([_spot('hand:0', 30), _spot('hand:1', 40)]);
      final firstKeyForThirty = _keysByCard(first)[30];

      // The card of type 30 is gone entirely this frame (buried, not simply
      // moved to a zone this tracker sees) — its ordinal must be retired.
      tracker.assign([_spot('hand:0', 40)]);

      // A brand new copy of type 30 appears later (e.g. re-drawn from the
      // stock in a later round). It must not reuse the retired ordinal.
      final third = tracker.assign([_spot('hand:0', 40), _spot('hand:1', 30)]);
      final thirdKeyForThirty = _keysByCard(third)[30];

      expect(thirdKeyForThirty, isNot(firstKeyForThirty));
    });

    test('does not let hidden backs consume card zero identity', () {
      final tracker = CardIdentityTracker();
      // `card: 0` is the face-down sentinel for stock/morto backs, but it is
      // also a legitimate real card id (rank 0, suit 0) once it is in a hand.
      final result = tracker.assign([_spot('stock:0', 0), _spot('hand:0', 0)]);
      // assign() preserves input order, and only the real card's key is
      // rewritten — the back placeholder's is left untouched.
      final backSpot = result[0];
      final handSpot = result[1];

      // The back placeholder keeps its positional key untouched...
      expect(backSpot.key, 'stock:0');
      // ...while the real card in hand gets a genuine identity key that
      // cannot collide with it.
      expect(handSpot.key, isNot('stock:0'));
      expect(handSpot.key, startsWith('card:0:'));
    });
  });

  test('rank-major order groups ranks, ties by suit, jokers last', () {
    final hand = [
      kJoker,
      cardId(9, 3),
      cardId(2, 2),
      kJoker,
      cardId(2, 0),
      cardId(2, 0),
      cardId(0, 1),
    ]..sort(rankMajorOrder);

    expect(hand, [
      cardId(0, 1),
      cardId(2, 0),
      cardId(2, 0),
      cardId(2, 2),
      cardId(9, 3),
      kJoker,
      kJoker,
    ]);
  });
}
