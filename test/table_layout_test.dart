/// Tests for stable physical-card identities across pure table-layout frames.
library;

import 'package:canastra/engine/cards.dart';
import 'package:canastra/game/move_index.dart';
import 'package:canastra/multiplayer/table_view.dart';
import 'package:canastra/ui/widgets/playing_card.dart';
import 'package:canastra/ui/widgets/stage.dart';
import 'package:canastra/ui/widgets/table_layout.dart';
import 'package:flutter_test/flutter_test.dart';

CardSpot _spot(String key, CardId card) =>
    CardSpot(key: key, card: card, x: 0, y: 0, scale: 1, z: 0, faceUp: true);

/// A spot still staged on the stock, the way `_hands` draws an undealt card —
/// same key and card, different everything else, exactly the shape
/// [CardIdentityTracker] is required to see through.
CardSpot _staged(String key, CardId card) =>
    _spot(key, card).onTheStock(TableMetrics.landscape);

List<CardSpot> _hand(List<CardId> cards) => [
  for (var i = 0; i < cards.length; i++) _spot('hand:$i', cards[i]),
];

Map<CardId, String> _keysByCard(Iterable<CardSpot> spots) => {
  for (final spot in spots) spot.card: spot.key,
};

String _count(int value) => '$value';

/// The far edge of the felt, with a float's worth of slack: a row whose scale
/// was solved to fill its span exactly lands on the margin, and does not land
/// on it in binary.
Matcher _withinFelt(TableMetrics m) =>
    lessThanOrEqualTo(m.size.width - m.margin + 1e-9);

/// Every card the layout drew into a meld, in the order it drew them.
List<CardSpot> _meldedCards(TableLayout layout) => [
  for (final spot in layout.cards)
    if (spot.key.startsWith('meld:')) spot,
];

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

/// A table with a whole side's worth of melds down.
///
/// [owner] is the side that laid them: 0 is yours, and anything else is the
/// opponent's row, which is laid out on its own terms and was for a long time
/// never exercised here at all.
TableLayout _crowdedTableLayout({
  List<CardId> hand = const [],
  List<CardId>? handOverride,
  TableMetrics metrics = TableMetrics.landscape,
  List<int> handSizes = const [0, 0],
  int numPlayers = 2,
  int owner = 0,
  int meldCount = 9,
  int meldSize = 7,
}) {
  final melds = [
    for (var slot = 0; slot < meldCount; slot++)
      MeldView(
        owner: owner,
        isSequence: false,
        suit: null,
        rank: slot,
        startPos: null,
        cards: [
          for (var copy = 0; copy < meldSize; copy++)
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
    numPlayers: numPlayers,
    numSides: 2,
    partnerSeat: null,
    playerNames: const ['You', 'Them'],
    profile: 'buraco',
    matchTarget: 3000,
    canastraMinSize: 7,
    hand: hand,
    handSizes: handSizes,
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
      metrics: metrics,
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
    expect(kStageLandscape.width - (play.x + play.width), 20);
  });

  test('the landscape play area is exactly a meld row tall', () {
    // The metric is written out rather than derived, so that it cannot quietly
    // drift away from the row it shares.
    const m = TableMetrics.landscape;
    expect(m.playHeight, m.meldBoxHeight);
    expect(m.playY, m.myRowY);
  });

  // The geometric invariants that have to hold on either stage. Melds are the
  // documented exception: a row compressed to its floor is allowed to run off
  // the felt rather than become unreadable, so they are checked separately.
  for (final (name, m) in const [
    ('a wide table', TableMetrics.landscape),
    ('a phone held upright', TableMetrics.portrait),
  ]) {
    test('every zone keeps the felt margins on $name', () {
      for (final zone in _crowdedTableLayout(metrics: m).zones) {
        expect(zone.x, greaterThanOrEqualTo(m.margin), reason: zone.id);
        expect(
          zone.x + zone.width,
          lessThanOrEqualTo(m.size.width - m.margin),
          reason: zone.id,
        );
        expect(
          zone.y + zone.height,
          lessThanOrEqualTo(m.size.height),
          reason: zone.id,
        );
      }
    });

    test('a hand of any size fans inside $name', () {
      for (final size in const [11, 15, 30]) {
        final hand = [for (var i = 0; i < size; i++) cardId(i % 13, i % 4)];
        final spots = _crowdedTableLayout(
          hand: hand,
          metrics: m,
        ).cards.where((spot) => spot.inHand).toList();

        expect(spots.length, size);
        expect(spots.first.x, greaterThanOrEqualTo(0), reason: '$size cards');
        expect(
          spots.last.x + kCardWidth,
          lessThanOrEqualTo(m.size.width),
          reason: '$size cards',
        );
        expect(
          spots.first.y + kCardHeight,
          lessThanOrEqualTo(m.size.height),
          reason: '$size cards',
        );
      }
    });

    test('three opponents fan inside $name', () {
      final spots = _crowdedTableLayout(
        metrics: m,
        numPlayers: 4,
        handSizes: const [0, 11, 11, 11],
      ).cards.where((spot) => spot.key.startsWith('seat')).toList();

      expect(spots.length, 33);
      for (final spot in spots) {
        expect(spot.x, greaterThanOrEqualTo(m.margin));
        // The last fan may lean into the margin — a three-handed fan shares one
        // band — but never off the stage.
        expect(
          spot.x + kCardWidth * kOpponentScale,
          lessThanOrEqualTo(m.size.width),
        );
      }
    });
  }

  test('nine melds take two rows on a phone, and stay on the felt', () {
    const m = TableMetrics.portrait;
    final mine = _crowdedTableLayout(
      metrics: m,
    ).melds.where((meld) => meld.mine).toList();

    expect(mine.length, 9);
    // Filled evenly: five on the first row, four on the second.
    expect(mine.map((meld) => meld.y).toSet().length, 2);
    expect(mine.where((meld) => meld.y == m.myRowY).length, 5);
    expect(mine.every((meld) => meld.compact), isTrue);

    // Wrapping is what buys this: nine spread melds do not fit any row at any
    // compression, so on a phone they must stay inside the felt without it.
    for (final meld in mine) {
      expect(meld.x, greaterThanOrEqualTo(m.margin));
      expect(meld.x + meld.width, lessThanOrEqualTo(m.size.width - m.margin));
      expect(meld.y + meld.height, lessThanOrEqualTo(m.playY));
    }
  });

  // One to ten melds down, of three to fourteen cards each, on either side —
  // the whole range a side can reach in a game, and the range the fit has to
  // survive. The two stages give ground very differently once it is crowded, so
  // each gets the test its own concessions can pass.
  const counts = 10;
  const sizes = [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14];

  test('a row of stacks stays on the felt at every size a side can meld', () {
    const m = TableMetrics.portrait;
    for (var count = 1; count <= counts; count++) {
      for (final size in sizes) {
        // The opponent is the harder of the two: their melds get one row and
        // yours get two, so ten of theirs meet the felt side by side.
        for (final owner in const [0, 1]) {
          final layout = _crowdedTableLayout(
            metrics: m,
            owner: owner,
            meldCount: count,
            meldSize: size,
          );
          final where = 'side $owner, $count melds of $size';

          expect(layout.melds.length, count, reason: where);
          for (final meld in layout.melds) {
            expect(meld.x, greaterThanOrEqualTo(m.margin), reason: where);
            expect(meld.x + meld.width, _withinFelt(m), reason: where);
          }
          for (final spot in _meldedCards(layout)) {
            expect(
              spot.x + kCardWidth * spot.scale,
              _withinFelt(m),
              reason: where,
            );
            expect(
              spot.scale,
              greaterThanOrEqualTo(m.minMeldScale),
              reason: where,
            );
          }
        }
      }
    }
  });

  test('a spread row leaves the felt only once it is at its floor', () {
    const m = TableMetrics.landscape;
    // A wide table has only the one concession to make. Past the point where a
    // rank in the corner would start to be covered it is documented to overflow
    // rather than become unreadable, and six melds of fourteen still do — the
    // felt holds five. What is checked here is that nothing leaves early:
    // whatever overflows has spent its compression first, and no card on a
    // spread row is ever drawn smaller than the design's size.
    final floor = m.meldCardWidth * 0.26;
    for (var count = 1; count <= counts; count++) {
      for (final size in sizes) {
        for (final owner in const [0, 1]) {
          final layout = _crowdedTableLayout(
            metrics: m,
            owner: owner,
            meldCount: count,
            meldSize: size,
          );
          final where = 'side $owner, $count melds of $size';
          final drawn = _meldedCards(layout);

          for (final meld in layout.melds) {
            expect(meld.x, greaterThanOrEqualTo(m.margin), reason: where);
          }
          for (final spot in drawn) {
            expect(spot.scale, m.meldScale, reason: where);
          }

          final overflowed = layout.melds.any(
            (meld) => meld.x + meld.width > m.size.width - m.margin + 1e-9,
          );
          if (overflowed) {
            expect(drawn[1].x - drawn[0].x, moreOrLessEquals(floor));
            continue;
          }
          for (final spot in drawn) {
            expect(spot.x + kCardWidth * spot.scale, _withinFelt(m));
          }
        }
      }
    }
  });

  test('a stack is no wider at fourteen cards than at seven', () {
    const m = TableMetrics.portrait;
    List<double> widths(int size) => [
      for (final meld in _crowdedTableLayout(
        metrics: m,
        meldCount: 5,
        meldSize: size,
      ).melds)
        meld.width,
    ];

    expect(widths(14), widths(7));

    // Every card in the stack is still its own spot, so melding one has
    // somewhere to glide to. The ones past the thickness simply arrive
    // underneath the card on top.
    final drawn = _meldedCards(
      _crowdedTableLayout(metrics: m, meldCount: 1, meldSize: 14),
    );
    expect(drawn.length, 14);
    expect(drawn.map((spot) => spot.key).toSet().length, 14);
    expect(drawn.last.x, drawn[m.meldStackDepth].x);
    expect(drawn[m.meldStackDepth].x, greaterThan(drawn.first.x));
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
