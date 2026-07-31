/// Tests for stable physical-card identities across pure table-layout frames.
library;

import 'package:canastra/engine/cards.dart';
import 'package:canastra/game/move_index.dart';
import 'package:canastra/multiplayer/table_view.dart';
import 'package:canastra/ui/widgets/stage.dart';
import 'package:canastra/ui/widgets/table_layout.dart';
import 'package:flutter_test/flutter_test.dart';

CardSpot _spot(String key, CardId card) =>
    CardSpot(key: key, card: card, x: 0, y: 0, scale: 1, z: 0, faceUp: true);

/// A spot still staged on the stock, the way `_hands` draws an undealt card —
/// same key and card, different everything else, exactly the shape
/// [CardIdentityTracker] is required to see through.
CardSpot _staged(String key, CardId card) => _spot(key, card).onTheStock();

List<CardSpot> _hand(List<CardId> cards) => [
  for (var i = 0; i < cards.length; i++) _spot('hand:$i', cards[i]),
];

Map<CardId, String> _keysByCard(Iterable<CardSpot> spots) => {
  for (final spot in spots) spot.card: spot.key,
};

String _count(int value) => '$value';

const _words = ZoneWords(
  stock: 'stock',
  pile: 'pile',
  morto: 'morto',
  playArea: 'play',
  playIdle: 'idle',
  playReady: 'ready',
  pileDiscard: 'discard',
  pileBatida: 'out',
  empty: 'empty',
  waiting: 'waiting',
  taken: 'taken',
  left: _count,
  cards: _count,
);

TableLayout _crowdedTableLayout({
  List<CardId> hand = const [],
  List<CardId>? handOverride,
}) {
  final melds = [
    for (var slot = 0; slot < 9; slot++)
      MeldView(
        owner: 0,
        isSequence: false,
        suit: null,
        rank: slot,
        startPos: null,
        cards: [
          for (var copy = 0; copy < 7; copy++)
            cardId(slot, copy % Suit.values.length),
        ],
        wildIndices: const [],
        isCanastra: true,
        isClean: true,
        points: 100,
      ),
  ];
  final view = TableView(
    seat: 0,
    side: 0,
    numPlayers: 2,
    numSides: 2,
    partnerSeat: null,
    playerNames: const ['You', 'Them'],
    profile: 'buraco',
    matchTarget: 3000,
    canastraMinSize: 7,
    hand: hand,
    handSizes: const [0, 0],
    melds: melds,
    trash: const [],
    stockCount: 0,
    mortoTaken: const [false, false],
    mortoSizes: const [0, 0],
    redThrees: const [[], []],
    currentPlayer: 0,
    phase: 'play',
    turnNumber: 0,
    frozen: false,
    pileBlocked: false,
    pendingPileCard: null,
    boughtSolePileCard: null,
    initialMeldDone: const [true, true],
    initialMeldMin: const [0, 0],
    stagedPoints: 0,
    publicScores: const [0, 0],
    matchScores: const [0, 0],
    matchNumber: 0,
    roundOver: false,
    matchOver: false,
    wentOutSide: null,
    winnerSide: null,
    roundIndex: 0,
    roundResult: null,
    legalActions: const [],
    history: const [],
  );
  return layOutTable(
    LayoutInput(
      view: view,
      moves: MoveIndex.empty,
      handOverride: handOverride,
      selection: const [],
      openSlots: const {},
      canMeld: false,
      canDiscard: false,
      discardGoesOut: false,
      dealt: 0,
      dealDone: true,
      words: _words,
    ),
  );
}

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
      // carries its eventual `hand:$i` key, exactly as `_hands` draws it.
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

  test('a fully compressed play zone keeps the stage right gutter', () {
    final play = _crowdedTableLayout().zones.singleWhere(
      (zone) => zone.id == 'play',
    );

    expect(play.x, 1030);
    expect(play.width, 190);
    expect(kStage.width - (play.x + play.width), 20);
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

  test('the layout draws the hand in the override order', () {
    final layout = _crowdedTableLayout(
      hand: [cardId(3, 2), kJoker, cardId(3, 0)],
      handOverride: [cardId(3, 0), cardId(3, 2), kJoker],
    );
    final drawn = [
      for (final spot in layout.cards)
        if (spot.inHand) spot.card,
    ];

    expect(drawn, [cardId(3, 0), cardId(3, 2), kJoker]);
  });
}
