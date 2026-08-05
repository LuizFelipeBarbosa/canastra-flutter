/// Tests for the pure-Dart fluid table solver.
library;

import 'dart:ui' show Size;

import 'package:canastra/multiplayer/table_view.dart';
import 'package:canastra/ui/widgets/playing_card.dart' show kCardWidth;
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
  hand: List.generate(handSize, (index) => index % 52),
  handSizes: [handSize, 0],
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

TableSolution _solve(TableView view, Size viewport, {double cardBoost = 1}) {
  TableSolution? solution;
  expect(
    () => solution = solveTable(
      TableSolverInput(
        viewport: viewport,
        view: view,
        selection: const [],
        openSlots: const {},
        dealt: 0,
        dealDone: true,
        cardBoost: cardBoost,
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
}
