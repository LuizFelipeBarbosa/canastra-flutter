import 'package:canastra/ai/arena.dart';
import 'package:canastra/ai/heuristic_score.dart';
import 'package:canastra/ai/signals.dart';
import 'package:canastra/ai/smart_agent.dart';
import 'package:canastra/engine/action.dart';
import 'package:canastra/engine/cards.dart';
import 'package:canastra/engine/match.dart';
import 'package:canastra/engine/profiles.dart';
import 'package:canastra/multiplayer/table_view.dart';
import 'package:flutter_test/flutter_test.dart';

TableView _view({
  List<CardId> hand = const [],
  List<int>? handSizes,
  List<MeldView> melds = const [],
  List<CardId> trash = const [],
  int stockCount = 40,
  CardId? pendingPileCard,
  List<List<CardId>>? redThrees,
  List<int> legalActions = const [],
  List<GameEvent> history = const [],
  int numPlayers = 2,
  int numSides = 2,
  int side = 0,
}) => TableView(
  seat: side,
  side: side,
  numPlayers: numPlayers,
  numSides: numSides,
  partnerSeat: numPlayers == 4 ? (side + 2) % 4 : null,
  playerNames: [for (var seat = 0; seat < numPlayers; seat++) 'seat $seat'],
  profile: 'buraco',
  matchTarget: 3000,
  canastraMinSize: 7,
  hand: hand,
  handSizes: handSizes ?? [hand.length, ...List.filled(numPlayers - 1, 11)],
  melds: melds,
  trash: trash,
  stockCount: stockCount,
  mortoTaken: List.filled(numSides, false),
  mortoSizes: List.filled(numSides, 11),
  redThrees: redThrees ?? [for (var side = 0; side < numSides; side++) []],
  currentPlayer: side,
  phase: 'play',
  turnNumber: 1,
  frozen: false,
  pileBlocked: false,
  pendingPileCard: pendingPileCard,
  boughtSolePileCard: null,
  initialMeldDone: List.filled(numSides, false),
  initialMeldMin: List.filled(numSides, 0),
  stagedPoints: 0,
  publicScores: List.filled(numSides, 0),
  matchScores: List.filled(numSides, 0),
  matchNumber: 0,
  roundOver: false,
  matchOver: false,
  wentOutSide: null,
  winnerSide: null,
  roundIndex: 0,
  roundResult: null,
  legalActions: legalActions,
  history: history,
);

MeldView _sequence({
  required int owner,
  required int suit,
  required int start,
  required List<CardId> cards,
}) => MeldView(
  owner: owner,
  isSequence: true,
  suit: suit,
  rank: null,
  startPos: start,
  cards: cards,
  wildIndices: const [],
  isCanastra: false,
  isClean: true,
  points: 0,
);

double _smartScore(TableView view, GameAction action) {
  final cfg = buraco();
  final facts = TurnFacts.of(cfg, view);
  return baseActionScore(cfg, view, facts.hand, action) +
      signalDelta(cfg, view, facts, action);
}

void main() {
  test('unseen counts subtract every visible zone and clamp at zero', () {
    final cfg = canasta(numPlayers: 2);
    final aceClubs = cardId(Rank.ace, Suit.clubs);
    final aceDiamonds = cardId(Rank.ace, Suit.diamonds);
    final aceHearts = cardId(Rank.ace, Suit.hearts);
    final aceSpades = cardId(Rank.ace, Suit.spades);
    final view = _view(
      hand: [aceClubs, aceClubs, aceClubs, kJoker],
      trash: [aceDiamonds, aceDiamonds, kJoker],
      melds: [
        _sequence(
          owner: 1,
          suit: Suit.hearts,
          start: 1,
          cards: [aceHearts, aceHearts, kJoker],
        ),
      ],
      redThrees: [
        [aceSpades, kJoker],
        [aceSpades],
      ],
      pendingPileCard: kJoker,
    );

    final unseen = unseenCounts(cfg, view);

    expect(unseen[aceClubs], 0, reason: 'over-visible ids are clamped');
    expect(unseen[aceDiamonds], 0);
    expect(unseen[aceHearts], 0);
    expect(unseen[aceSpades], 0);
    expect(unseen[kJoker], 0);
    expect(unseen[kPad], 0);
  });

  test('near an opponent run is a worse discard than unrelated junk', () {
    final cfg = buraco();
    final near = cardId(Rank.three, Suit.clubs);
    final unrelated = cardId(Rank.three, Suit.diamonds);
    final run = _sequence(
      owner: 1,
      suit: Suit.clubs,
      start: positionsOf(Rank.five).single,
      cards: [
        cardId(Rank.five, Suit.clubs),
        cardId(Rank.six, Suit.clubs),
        cardId(Rank.seven, Suit.clubs),
      ],
    );
    final view = _view(
      hand: [near, unrelated],
      melds: [run],
      legalActions: [
        encodeAction(Discard(ct: near), cfg.meld.maxMeldSlots),
        encodeAction(Discard(ct: unrelated), cfg.meld.maxMeldSlots),
      ],
    );

    expect(
      _smartScore(view, Discard(ct: near)),
      lessThan(_smartScore(view, Discard(ct: unrelated))),
    );
    expect(
      SmartAgent(seed: 1, noise: 0).chooseAction(cfg, view),
      encodeAction(Discard(ct: unrelated), cfg.meld.maxMeldSlots),
    );
  });

  test('a wild ranks below every natural discard option', () {
    final wild = cardId(Rank.two, Suit.clubs);
    final naturals = [
      cardId(Rank.four, Suit.clubs),
      cardId(Rank.nine, Suit.diamonds),
      cardId(Rank.king, Suit.hearts),
    ];
    final view = _view(hand: [wild, ...naturals]);
    final wildScore = _smartScore(view, Discard(ct: wild));

    for (final natural in naturals) {
      expect(wildScore, lessThan(_smartScore(view, Discard(ct: natural))));
    }
  });

  test(
    'a dead pair has lower retention value than an equivalent live pair',
    () {
      final deadRank = Rank.five;
      final liveRank = Rank.six;
      final dead = cardId(deadRank, Suit.clubs);
      final live = cardId(liveRank, Suit.clubs);
      final hand = [
        dead,
        cardId(deadRank, Suit.diamonds),
        live,
        cardId(liveRank, Suit.diamonds),
      ];
      final accountedFor = <CardId>[];
      for (final suit in Suit.values) {
        final copiesAlreadyInHand = suit == Suit.clubs || suit == Suit.diamonds;
        final visibleCopies = copiesAlreadyInHand ? 1 : 2;
        for (var copy = 0; copy < visibleCopies; copy++) {
          accountedFor.add(cardId(deadRank, suit));
        }
      }
      final view = _view(hand: hand, trash: accountedFor);
      final facts = TurnFacts.of(buraco(), view);

      expect([
        for (final suit in Suit.values) facts.unseen[cardId(deadRank, suit)],
      ], everyElement(0));
      expect(
        _smartScore(view, Discard(ct: dead)),
        greaterThan(_smartScore(view, Discard(ct: live))),
        reason: 'the less useful dead pair should be discarded first',
      );
    },
  );

  test('history attributes an unannotated pile pickup to the actor side', () {
    final wanted = cardId(Rank.queen, Suit.hearts);
    final ownShed = cardId(Rank.four, Suit.clubs);
    final view = _view(
      numPlayers: 4,
      numSides: 2,
      handSizes: const [11, 11, 11, 11],
      history: [
        GameEvent(2, 'discard', card: ownShed),
        const GameEvent(2, 'drawTrash'),
        GameEvent(0, 'discard', card: wanted),
        const GameEvent(3, 'drawTrash'),
      ],
    );

    final reads = readOpponents(buraco(numPlayers: 4), view);

    expect(reads.keys, {1});
    expect(reads[1]!.pickedUpRanks, contains(Rank.queen));
    expect(reads[1]!.pickedUpRanks, isNot(contains(Rank.four)));
  });

  test('same seed makes identical choices across the same view sequence', () {
    final cfg = buraco();
    final match = Match(cfg: cfg, seed: 73);
    final first = SmartAgent(seed: 991);
    final second = SmartAgent(seed: 991);
    const names = ['first', 'second'];

    for (var step = 0; step < 100 && !match.round.roundOver; step++) {
      final view = buildTableView(
        match,
        match.currentPlayer,
        playerNames: names,
      );
      final firstChoice = first.chooseAction(cfg, view);
      final secondChoice = second.chooseAction(cfg, view);
      expect(secondChoice, firstChoice, reason: 'action $step');
      match.applyId(firstChoice);
    }
  });

  test('arena exposes smart without changing the hard ladder mapping', () {
    expect(agentFactory('smart')(1), isA<SmartAgent>());
    expect(agentFactory('hard')(1), isNot(isA<SmartAgent>()));
  });
}
