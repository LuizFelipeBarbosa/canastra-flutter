/// Tests for the pure-Dart fluid table solver.
library;

import 'dart:ui' show Rect, Size;

import 'package:canastra/engine/cards.dart';
import 'package:canastra/game/game_controller.dart' show PickedCard;
import 'package:canastra/multiplayer/table_view.dart';
import 'package:canastra/ui/widgets/playing_card.dart'
    show kCardHeight, kCardWidth;
import 'package:canastra/ui/widgets/table_solver.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _MeldSpec = ({int cards, int points, bool canastra, bool clean});

List<MeldView> _meldsForSide({
  required int owner,
  required List<_MeldSpec> specs,
  Set<int>? sequenceSlots,
  Map<int, int> startPositions = const {},
}) {
  final sequences =
      sequenceSlots ??
      {for (var slot = 0; slot < specs.length; slot += 2) slot};

  return List.generate(specs.length, (slot) {
    final spec = specs[slot];
    final isSequence = sequences.contains(slot);
    final maximumStart = 15 - spec.cards;
    final suggestedStart = startPositions[slot] ?? slot + 2;
    final startPos = suggestedStart < 1
        ? 1
        : suggestedStart > maximumStart
        ? maximumStart
        : suggestedStart;

    return MeldView(
      owner: owner,
      isSequence: isSequence,
      suit: isSequence ? slot % 4 : null,
      rank: isSequence ? null : slot % 13,
      startPos: isSequence ? startPos : null,
      cards: List.generate(
        spec.cards,
        (index) => (owner * 17 + slot * 5 + index) % 52,
      ),
      wildIndices: spec.clean || spec.cards < 3 ? const [] : const [1],
      isCanastra: spec.canastra,
      isClean: spec.clean,
      points: spec.points,
    );
  });
}

TableView _tableView({
  required int handSize,
  required List<MeldView> myMelds,
  required List<MeldView> theirMelds,
  List<CardId>? hand,
}) => TableView(
  seat: 0,
  side: 0,
  numPlayers: 2,
  numSides: 2,
  partnerSeat: null,
  playerNames: const [],
  profile: '',
  matchTarget: 0,
  canastraMinSize: 7,
  hand: hand ?? List.generate(handSize, (index) => index % 52),
  handSizes: [hand?.length ?? handSize, 0],
  melds: [...myMelds, ...theirMelds],
  trash: const [3, 14, 25],
  stockCount: 40,
  mortoTaken: const [false, false],
  mortoSizes: const [0, 0],
  redThrees: const [[], []],
  currentPlayer: 0,
  phase: 'play',
  turnNumber: 1,
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

TableView _demoView() {
  const mySpecs = <_MeldSpec>[
    (cards: 5, points: 60, canastra: false, clean: false),
    (cards: 7, points: 55, canastra: true, clean: true),
    (cards: 3, points: 45, canastra: false, clean: false),
  ];
  const theirSpecs = <_MeldSpec>[
    (cards: 4, points: 40, canastra: false, clean: false),
    (cards: 6, points: 50, canastra: false, clean: false),
  ];
  return _tableView(
    handSize: 12,
    myMelds: _meldsForSide(owner: 0, specs: mySpecs),
    theirMelds: _meldsForSide(owner: 1, specs: theirSpecs),
  );
}

TableSolution _solve(
  TableView view,
  Size viewport, {
  double cardBoost = 1,
  List<PickedCard> selection = const [],
  List<CardId>? handOverride,
  String Function(MeldView meld)? meldLabeler,
}) {
  TableSolution? solution;
  expect(
    () => solution = solveTable(
      TableSolverInput(
        viewport: viewport,
        view: view,
        selection: selection,
        openSlots: const {},
        dealt: 0,
        dealDone: true,
        cardBoost: cardBoost,
        handOverride: handOverride,
        meldLabeler: meldLabeler,
      ),
    ),
    returnsNormally,
  );

  final result = solution!;
  expect(result.cw, greaterThanOrEqualTo(26 - 0.001));
  expect(result.mcw, greaterThanOrEqualTo(18 - 0.001));
  return result;
}

bool _blocksFit(TableSolution solution) =>
    solution.theirBlock.height + solution.myBlock.height <=
    solution.midInner + 0.5;

void _expectInside(Rect rect, Size viewport, String where) {
  expect(rect.left, greaterThanOrEqualTo(-0.5), reason: where);
  expect(rect.top, greaterThanOrEqualTo(-0.5), reason: where);
  expect(
    rect.right,
    lessThanOrEqualTo(viewport.width + 0.5),
    reason: where,
  );
  expect(
    rect.bottom,
    lessThanOrEqualTo(viewport.height + 0.5),
    reason: where,
  );
}

void _expectMeldsInside(
  TableSolution solution,
  Size viewport,
  String where, {
  bool allowFullDegradation = false,
}) {
  if (allowFullDegradation && solution.degradation == 4) return;
  for (final meld in solution.melds) {
    _expectInside(meld.rect, viewport, '$where, meld ${meld.slot}');
  }
}

({String zone, String slot}) _cardLocationFromKey(String key) {
  final parts = key.split(':');
  final zone = parts.first == 'meld' && parts.length >= 3
      ? parts.take(3).join(':')
      : parts.first;
  return (zone: zone, slot: key);
}

bool _isSolverZone(String zone) {
  if (const {'hand', 'pile', 'stock', 'morto'}.contains(zone)) return true;

  final meldParts = zone.split(':');
  if (meldParts.length == 3 &&
      meldParts.first == 'meld' &&
      const {'me', 'them'}.contains(meldParts[1]) &&
      int.tryParse(meldParts[2]) != null) {
    return true;
  }

  return zone.startsWith('seat') &&
      int.tryParse(zone.substring('seat'.length)) != null;
}

void main() {
  test('nine melds per side and fifteen cards survive compact viewports', () {
    const specs = <_MeldSpec>[
      (cards: 3, points: 30, canastra: false, clean: false),
      (cards: 7, points: 55, canastra: true, clean: true),
      (cards: 4, points: 35, canastra: false, clean: false),
      (cards: 5, points: 40, canastra: false, clean: false),
      (cards: 6, points: 45, canastra: false, clean: false),
      (cards: 4, points: 30, canastra: false, clean: false),
      (cards: 3, points: 25, canastra: false, clean: false),
      (cards: 5, points: 40, canastra: false, clean: false),
      (cards: 4, points: 50, canastra: false, clean: false),
    ];
    final myMelds = _meldsForSide(
      owner: 0,
      specs: specs,
      sequenceSlots: const {0, 8},
      startPositions: const {8: 10},
    );
    final theirMelds = _meldsForSide(
      owner: 1,
      specs: specs,
      sequenceSlots: const {0, 8},
      startPositions: const {8: 10},
    );
    final view = _tableView(
      handSize: 15,
      myMelds: myMelds,
      theirMelds: theirMelds,
    );
    expect(myMelds.map(tableSolverMeldLabel), contains('10–K'));

    for (final viewport in const [
      Size(402, 874),
      Size(874, 402),
      Size(320, 568),
    ]) {
      final solution = _solve(view, viewport);

      expect(solution.degradation, lessThanOrEqualTo(3), reason: '$viewport');
      for (final meld in solution.melds) {
        expect(
          meld.rect.width,
          greaterThanOrEqualTo(meld.captionMinimumWidth - 0.5),
          reason: '$viewport, ${meld.label}',
        );
      }
      expect(
        _blocksFit(solution) || solution.degradation == 4,
        isTrue,
        reason: '$viewport',
      );
      expect(
        solution.handFanWidth,
        lessThanOrEqualTo(viewport.width - 2 * solution.pad + 0.5),
        reason: '$viewport',
      );
    }
  });

  test('twelve melds per side and thirty cards retain a usable hand fan', () {
    final specs = List<_MeldSpec>.generate(12, (slot) {
      final cards = 3 + slot % 6;
      final canastra = cards >= 7 && slot.isEven;
      return (
        cards: cards,
        points: 25 + slot * 5,
        canastra: canastra,
        clean: canastra && slot % 4 == 0,
      );
    });
    final view = _tableView(
      handSize: 30,
      myMelds: _meldsForSide(
        owner: 0,
        specs: specs,
        sequenceSlots: const {0, 6},
      ),
      theirMelds: _meldsForSide(
        owner: 1,
        specs: specs,
        sequenceSlots: const {0, 6},
      ),
    );

    final solution = _solve(view, const Size(320, 568));

    expect(solution.handStep, greaterThanOrEqualTo(8 - 0.001));
    expect(_blocksFit(solution) || solution.degradation == 4, isTrue);
  });

  test('the demo state solves without degradation in landscape', () {
    final solution = _solve(_demoView(), const Size(1440, 900));

    expect(solution.degradation, 0);
    expect(solution.landscape, isTrue);
    expect(solution.railWidth, greaterThan(0));
    for (final meld in solution.melds) {
      for (final card in meld.cards) {
        expect(
          card.scale * kCardWidth,
          greaterThanOrEqualTo(0.55 * solution.cw * 0.999),
        );
      }
    }
    expect(solution.theirRows, lessThanOrEqualTo(2));
    expect(solution.myRows, lessThanOrEqualTo(2));
  });

  test('the demo state uses a pile bank in portrait', () {
    final solution = _solve(_demoView(), const Size(402, 874));

    expect(solution.bankHeight, greaterThan(0));
    expect(solution.railWidth, 0);
  });

  test('every card key follows the identity-tracker zone scheme', () {
    const handSize = 12;
    final solution = _solve(_demoView(), const Size(1440, 900));

    for (final card in solution.cards) {
      final location = _cardLocationFromKey(card.key);
      final parts = card.key.split(':');
      final expectedZone = parts.first == 'meld' && parts.length >= 3
          ? parts.take(3).join(':')
          : parts.first;

      expect(location.zone, expectedZone, reason: card.key);
      expect(location.slot, card.key, reason: card.key);
      expect(_isSolverZone(location.zone), isTrue, reason: card.key);
    }
    expect(
      solution.cards.where((card) => card.key.startsWith('hand:')),
      hasLength(handSize),
    );

    for (final meld in solution.melds) {
      final side = meld.mine ? 'me' : 'them';
      final prefix = 'meld:$side:${meld.slot}:';
      expect(meld.cards, hasLength(meld.meld.cards.length));
      expect(
        solution.cards.where((card) => card.key.startsWith(prefix)),
        hasLength(meld.meld.cards.length),
        reason: prefix,
      );
    }
  });

  test('card boost increases the demo card width monotonically', () {
    final view = _demoView();
    final regular = _solve(view, const Size(1440, 900));
    final boosted = _solve(view, const Size(1440, 900), cardBoost: 1.35);

    expect(boosted.cw, greaterThan(regular.cw));
  });

  test('a caller-supplied meld label reserves its displayed width', () {
    const longLabel = 'A VERY LONG MELD CAPTION LABEL';
    final view = _demoView();
    final target = view.myMelds.first;
    final regular = _solve(view, const Size(1440, 900));
    final labelled = _solve(
      view,
      const Size(1440, 900),
      meldLabeler: (meld) => identical(meld, target)
          ? longLabel
          : tableSolverMeldLabel(meld),
    );
    final regularTarget = regular.melds.singleWhere(
      (solution) => identical(solution.meld, target),
    );
    final labelledTarget = labelled.melds.singleWhere(
      (solution) => identical(solution.meld, target),
    );

    expect(labelledTarget.label, longLabel);
    expect(
      labelledTarget.captionMinimumWidth,
      greaterThan(regularTarget.captionMinimumWidth),
    );
    expect(labelledTarget.rect.width, greaterThan(regularTarget.rect.width));
  });

  test('the copy the selection names is the one that rises', () {
    final view = _tableView(
      handSize: 3,
      hand: const [4, 4, 5],
      myMelds: const [],
      theirMelds: const [],
    );
    final solution = _solve(
      view,
      const Size(1440, 900),
      selection: const [(ct: 4, copy: 1)],
    );
    final spots = solution.cards.where((spot) => spot.inHand).toList();

    expect(spots.map((spot) => spot.copy), equals([0, 1, 0]));
    expect(
      spots.map((spot) => spot.selected),
      equals([false, true, false]),
      reason: 'the second twin was tapped, so the second twin lifts',
    );
  });

  test('every rect the solver returns stays inside the viewport', () {
    for (final viewport in const [
      Size(1440, 900),
      Size(874, 402),
      Size(402, 874),
    ]) {
      final solution = _solve(_demoView(), viewport);
      final rects = <String, Rect>{
        'header': solution.header,
        'their strip': solution.theirStrip,
        'their shelf': solution.theirShelf,
        'their block': solution.theirBlock,
        'my strip': solution.myStrip,
        'my shelf': solution.myShelf,
        'my block': solution.myBlock,
        'pile band': solution.pileBand,
        'new meld slot': solution.newMeldSlot,
        'hand': solution.hand,
      };

      for (final rect in rects.entries) {
        _expectInside(rect.value, viewport, '$viewport, ${rect.key}');
      }
    }
  });

  test('a hand of any size fans inside the viewport', () {
    for (final viewport in const [Size(900, 420), Size(420, 840)]) {
      for (final size in const [11, 15, 30]) {
        final hand = [
          for (var i = 0; i < size; i++) cardId(i % 13, i % 4),
        ];
        final view = _tableView(
          handSize: size,
          hand: hand,
          myMelds: const [],
          theirMelds: const [],
        );
        final spots = _solve(
          view,
          viewport,
        ).cards.where((spot) => spot.inHand).toList();

        expect(spots, hasLength(size), reason: '$viewport, $size cards');
        for (final spot in spots) {
          expect(
            spot.x,
            greaterThanOrEqualTo(-0.5),
            reason: '$viewport, $size cards',
          );
          expect(
            spot.x + kCardWidth * spot.scale,
            lessThanOrEqualTo(viewport.width + 0.5),
            reason: '$viewport, $size cards',
          );
          expect(
            spot.y,
            greaterThanOrEqualTo(-0.5),
            reason: '$viewport, $size cards',
          );
          expect(
            spot.y + kCardHeight * spot.scale,
            lessThanOrEqualTo(viewport.height + 0.5),
            reason: '$viewport, $size cards',
          );
        }
      }
    }
  });

  test(
    'every meld a side can lay stays inside the viewport or fully degrades',
    () {
      for (final viewport in const [Size(1280, 820), Size(420, 840)]) {
        for (final count in const [1, 5, 9, 12, 16]) {
          for (final size in const [3, 7, 10, 14]) {
            if (count * size > 92) continue;
            final specs = List<_MeldSpec>.filled(
              count,
              (
                cards: size,
                points: 100,
                canastra: size >= 7,
                clean: true,
              ),
            );
            for (final owner in const [0, 1]) {
              final melds = _meldsForSide(
                owner: owner,
                specs: specs,
                sequenceSlots: const {},
              );
              final view = _tableView(
                handSize: 15,
                myMelds: owner == 0 ? melds : const [],
                theirMelds: owner == 1 ? melds : const [],
              );
              final solution = _solve(view, viewport);
              final where = '$viewport, side $owner, $count melds of $size';

              expect(solution.melds, hasLength(count), reason: where);
              _expectMeldsInside(
                solution,
                viewport,
                where,
                allowFullDegradation: true,
              );
            }
          }
        }
      }
    },
  );

  test('the round the goldens play out stays inside the viewport', () {
    const seed21 = [8, 5, 7, 8, 6, 6, 7, 4, 7, 5, 4, 4, 4, 4, 3];
    final specs = [
      for (final size in seed21)
        (
          cards: size,
          points: 100,
          canastra: size >= 7,
          clean: true,
        ),
    ];

    for (final viewport in const [Size(1280, 820), Size(420, 840)]) {
      for (final owner in const [0, 1]) {
        final melds = _meldsForSide(
          owner: owner,
          specs: specs,
          sequenceSlots: const {},
        );
        final view = _tableView(
          handSize: 15,
          myMelds: owner == 0 ? melds : const [],
          theirMelds: owner == 1 ? melds : const [],
        );
        final solution = _solve(view, viewport);
        final where = '$viewport, side $owner';

        expect(solution.melds, hasLength(seed21.length), reason: where);
        _expectMeldsInside(solution, viewport, where);
      }
    }
  });

  test('a stack is no wider at fourteen cards than at seven', () {
    TableSolution stacked(int size) {
      final specs = List<_MeldSpec>.filled(
        16,
        (cards: size, points: 0, canastra: false, clean: true),
      );
      final view = _tableView(
        handSize: 15,
        myMelds: _meldsForSide(
          owner: 0,
          specs: specs,
          sequenceSlots: const {},
        ),
        theirMelds: const [],
      );
      return _solve(view, const Size(250, 568));
    }

    final seven = stacked(7);
    final fourteen = stacked(14);
    expect(seven.degradation, greaterThanOrEqualTo(3));
    expect(fourteen.degradation, greaterThanOrEqualTo(3));
    expect(seven.stackedMelds, isTrue);
    expect(fourteen.stackedMelds, isTrue);

    final sevenMeld = seven.melds.singleWhere(
      (meld) => meld.mine && meld.slot == 0,
    );
    final fourteenMeld = fourteen.melds.singleWhere(
      (meld) => meld.mine && meld.slot == 0,
    );
    expect(fourteenMeld.rect.width, closeTo(sevenMeld.rect.width, 0.001));

    final drawn = fourteenMeld.cards;
    expect(drawn, hasLength(14));
    expect(drawn.map((spot) => spot.key).toSet(), hasLength(14));
    expect(drawn.last.x, drawn[2].x);
    expect(drawn[2].x, greaterThan(drawn.first.x));
  });

  test('the solver draws the hand in the override order', () {
    final natural = [cardId(3, 2), kJoker, cardId(3, 0)];
    final override = [cardId(3, 0), cardId(3, 2), kJoker];
    final view = _tableView(
      handSize: natural.length,
      hand: natural,
      myMelds: const [],
      theirMelds: const [],
    );
    final solution = _solve(
      view,
      const Size(1440, 900),
      handOverride: override,
    );
    final drawn = [
      for (final spot in solution.cards)
        if (spot.inHand) spot.card,
    ];

    expect(drawn, override);
  });
}
