import '../engine/action.dart';
import '../engine/cards.dart';
import '../engine/config.dart';
import '../multiplayer/table_view.dart';
import 'heuristic_score.dart';

/// Signal magnitudes are deliberately small beside the 450--900 point meld
/// scores. They reorder close discard and draw choices without teaching the
/// policy to skip a legal meld for a tactical bonus.
class SignalWeights {
  final double opponentMeldExtensionPenalty;
  final double opponentMeldNearPenalty;
  final double wildDiscardPenalty;
  final double pickedUpRankPenalty;
  final double adjacentPickedUpRankPenalty;
  final double discardedRankBonus;
  final double memoryMinimum;
  final double memoryMaximum;
  final double endgameDangerMultiplier;
  final double endgameDiscardValueDivisor;
  final double endgameMeldBonus;
  final double endgamePileCardPenalty;
  final double neededCanastraBonus;
  final double deadPairDiscardBonusPerCard;
  final double livePileCardBonus;
  final double wildPileCardMultiplier;
  final double livePileBonusCap;
  final int endgameStockThreshold;
  final int endgameOpponentHandThreshold;

  const SignalWeights({
    this.opponentMeldExtensionPenalty = 30,
    this.opponentMeldNearPenalty = 10,
    this.wildDiscardPenalty = 100,
    this.pickedUpRankPenalty = 15,
    this.adjacentPickedUpRankPenalty = 8,
    this.discardedRankBonus = 8,
    this.memoryMinimum = -15,
    this.memoryMaximum = 8,
    this.endgameDangerMultiplier = 2,
    this.endgameDiscardValueDivisor = 5,
    this.endgameMeldBonus = 40,
    this.endgamePileCardPenalty = 8,
    this.neededCanastraBonus = 100,
    this.deadPairDiscardBonusPerCard = 10,
    this.livePileCardBonus = 15,
    this.wildPileCardMultiplier = 3,
    this.livePileBonusCap = 90,
    this.endgameStockThreshold = 8,
    this.endgameOpponentHandThreshold = 3,
  });
}

const SignalWeights defaultSignalWeights = SignalWeights();

class OpponentRead {
  final Set<int> pickedUpRanks;
  final Set<int> discardedRanks;

  const OpponentRead({
    required this.pickedUpRanks,
    required this.discardedRanks,
  });
}

class TurnFacts {
  final Map<CardId, int> hand;
  final List<int> unseen;
  final List<MeldView> opponentMelds;
  final Set<int> opponentSetRanks;
  final Map<int, OpponentRead> opponentReads;
  final bool endgame;

  const TurnFacts({
    required this.hand,
    required this.unseen,
    required this.opponentMelds,
    required this.opponentSetRanks,
    required this.opponentReads,
    required this.endgame,
  });

  factory TurnFacts.of(
    RulesConfig cfg,
    TableView view, {
    SignalWeights weights = defaultSignalWeights,
  }) {
    final hand = <CardId, int>{};
    for (final ct in view.hand) {
      hand[ct] = (hand[ct] ?? 0) + 1;
    }

    final opponentMelds = [
      for (final meld in view.melds)
        if (meld.owner != view.side) meld,
    ];
    final opponentHands = [
      for (var seat = 0; seat < view.handSizes.length; seat++)
        if (seat % view.numSides != view.side) view.handSizes[seat],
    ];

    return TurnFacts(
      hand: Map.unmodifiable(hand),
      unseen: List.unmodifiable(unseenCounts(cfg, view)),
      opponentMelds: List.unmodifiable(opponentMelds),
      opponentSetRanks: Set.unmodifiable({
        for (final meld in opponentMelds)
          if (!meld.isSequence) meld.rank!,
      }),
      opponentReads: Map.unmodifiable(readOpponents(cfg, view)),
      endgame:
          view.stockCount <= weights.endgameStockThreshold ||
          opponentHands.any(
            (size) => size <= weights.endgameOpponentHandThreshold,
          ),
    );
  }
}

/// Copies of each card id that this seat cannot currently see.
List<int> unseenCounts(RulesConfig cfg, TableView view) {
  final counts = List<int>.filled(kCardSpace, 0);
  for (var ct = 0; ct < 52; ct++) {
    counts[ct] = cfg.deck.deckCount;
  }
  counts[kJoker] = cfg.deck.printedJokers;

  void subtract(Iterable<CardId> cards) {
    for (final ct in cards) {
      counts[ct]--;
    }
  }

  subtract(view.hand);
  subtract(view.trash);
  for (final meld in view.melds) {
    subtract(meld.cards);
  }
  for (final tray in view.redThrees) {
    subtract(tray);
  }
  if (view.pendingPileCard case final ct?) {
    counts[ct]--;
  }

  for (var ct = 0; ct < counts.length; ct++) {
    if (counts[ct] < 0) counts[ct] = 0;
  }
  return counts;
}

/// Reconstructs public evidence about which ranks each opponent took or shed.
Map<int, OpponentRead> readOpponents(RulesConfig cfg, TableView view) {
  final mutable = <int, _MutableOpponentRead>{
    for (var side = 0; side < view.numSides; side++)
      if (side != view.side) side: _MutableOpponentRead(),
  };
  final simulatedPile = <CardId>[];

  // The initial upcard is dealt before history begins, and auto-resolved red
  // threes drawn from stock are not logged. Those two cards cannot be assigned
  // to a pickup more precisely from the public event stream.
  for (final event in view.history) {
    final actorSide = event.actor % view.numSides;
    if (event.kind == 'discard' && event.card != null) {
      final card = event.card!;
      simulatedPile.add(card);
      final rank = idRank(card);
      if (rank != null) mutable[actorSide]?.discardedRanks.add(rank);
      continue;
    }
    if (event.kind != 'drawTrash') continue;

    final taken = <CardId>[];
    if (cfg.discardPile.drawRule == drawTopCard) {
      if (simulatedPile.isNotEmpty) taken.add(simulatedPile.removeLast());
    } else {
      taken.addAll(simulatedPile);
      simulatedPile.clear();
    }
    final read = mutable[actorSide];
    if (read == null) continue;
    for (final card in taken) {
      final rank = idRank(card);
      if (rank == null) continue;
      read.pickedUpRanks.add(rank);
      read.discardedRanks.remove(rank);
    }
  }

  return {
    for (final entry in mutable.entries)
      entry.key: OpponentRead(
        pickedUpRanks: Set.unmodifiable(entry.value.pickedUpRanks),
        discardedRanks: Set.unmodifiable(entry.value.discardedRanks),
      ),
  };
}

double signalDelta(
  RulesConfig cfg,
  TableView view,
  TurnFacts facts,
  GameAction action, {
  SignalWeights weights = defaultSignalWeights,
}) {
  switch (action) {
    case Discard(:final ct):
      return _discardDelta(cfg, view, facts, ct, weights);
    case DrawTrash():
      var delta = 0.0;
      if (facts.endgame) {
        delta -= weights.endgamePileCardPenalty * view.trash.length;
      }
      if (pileConnects(cfg, view, facts.hand)) {
        delta += _livePileValue(cfg, view, facts, weights);
      }
      return delta;
    case CreateSeq() || CreateSet():
      return facts.endgame ? weights.endgameMeldBonus : 0;
    case AddToMeld(:final slot):
      var delta = facts.endgame ? weights.endgameMeldBonus : 0.0;
      final myMelds = view.myMelds;
      final completes =
          slot < myMelds.length &&
          myMelds[slot].size == view.canastraMinSize - 1;
      if (completes &&
          cfg.goingOut.requireMortoTaken &&
          !view.mortoTaken[view.side]) {
        delta += weights.neededCanastraBonus;
      }
      return delta;
    case DrawDeck() || GoOut() || EndRound():
      return 0;
  }
}

double _discardDelta(
  RulesConfig cfg,
  TableView view,
  TurnFacts facts,
  CardId ct,
  SignalWeights weights,
) {
  if (cfg.isWildCard(ct)) {
    var delta = -weights.wildDiscardPenalty;
    if (facts.endgame) {
      delta -=
          cfg.cardValue(ct) *
          (1 / weights.endgameDiscardValueDivisor - 1 / 20.0);
    }
    return delta;
  }

  final danger = _opponentMeldDanger(facts, ct);
  var dangerPenalty = 0.0;
  if (danger.direct) {
    dangerPenalty += weights.opponentMeldExtensionPenalty;
  }
  if (danger.near) dangerPenalty += weights.opponentMeldNearPenalty;
  if (facts.endgame) dangerPenalty *= weights.endgameDangerMultiplier;

  var delta = -dangerPenalty + _memoryDelta(facts, idRank(ct)!, weights);
  if (!_rankIsLive(facts.unseen, idRank(ct)!)) {
    var sameRank = 0;
    facts.hand.forEach((card, count) {
      if (card != ct && card != kJoker && idRank(card) == idRank(ct)) {
        sameRank += count;
      }
    });
    // Halving the same-rank usefulness term raises the discard score by ten
    // points per matching card under baseActionScore's existing coefficient.
    delta += weights.deadPairDiscardBonusPerCard * sameRank;
  }
  if (facts.endgame) {
    delta -=
        cfg.cardValue(ct) * (1 / weights.endgameDiscardValueDivisor - 1 / 20.0);
  }
  return delta;
}

({bool direct, bool near}) _opponentMeldDanger(TurnFacts facts, CardId ct) {
  final rank = idRank(ct)!;
  if (facts.opponentSetRanks.contains(rank)) {
    return (direct: true, near: false);
  }

  var direct = false;
  var near = false;
  for (final meld in facts.opponentMelds) {
    if (!meld.isSequence || meld.suit != idSuit(ct)) continue;
    final start = meld.startPos!;
    final end = start + meld.size - 1;
    for (final position in positionsOf(rank)) {
      if (position == start - 1 || position == end + 1) direct = true;
      if (position == start - 2 || position == end + 2) near = true;
    }
  }
  return (direct: direct, near: near);
}

double _memoryDelta(TurnFacts facts, int rank, SignalWeights weights) {
  var delta = 0.0;
  for (final read in facts.opponentReads.values) {
    if (read.pickedUpRanks.contains(rank)) {
      delta -= weights.pickedUpRankPenalty;
    } else if (read.pickedUpRanks.any(
      (picked) => _rankDistance(rank, picked) == 1,
    )) {
      delta -= weights.adjacentPickedUpRankPenalty;
    }
    if (read.discardedRanks.contains(rank)) {
      delta += weights.discardedRankBonus;
    }
  }
  return delta.clamp(weights.memoryMinimum, weights.memoryMaximum).toDouble();
}

int _rankDistance(int first, int second) {
  var distance = kPosMax;
  for (final p in positionsOf(first)) {
    for (final q in positionsOf(second)) {
      final candidate = (p - q).abs();
      if (candidate < distance) distance = candidate;
    }
  }
  return distance;
}

double _livePileValue(
  RulesConfig cfg,
  TableView view,
  TurnFacts facts,
  SignalWeights weights,
) {
  var value = 0.0;
  for (final card in view.trash) {
    if (cfg.isWildCard(card)) {
      value += weights.livePileCardBonus * weights.wildPileCardMultiplier;
      continue;
    }
    final rank = idRank(card)!;
    final pairsWithLiveRank =
        facts.hand.keys.any((held) => held != kJoker && idRank(held) == rank) &&
        _rankIsLive(facts.unseen, rank);
    if (pairsWithLiveRank || _extendsOwnMeld(view, card)) {
      value += weights.livePileCardBonus;
    }
  }
  return value.clamp(0, weights.livePileBonusCap).toDouble();
}

bool _rankIsLive(List<int> unseen, int rank) {
  for (final suit in Suit.values) {
    if (unseen[cardId(rank, suit)] > 0) return true;
  }
  return false;
}

bool _extendsOwnMeld(TableView view, CardId card) {
  final rank = idRank(card)!;
  for (final meld in view.myMelds) {
    if (!meld.isSequence && meld.rank == rank) return true;
    if (!meld.isSequence || meld.suit != idSuit(card)) continue;
    final start = meld.startPos!;
    final end = start + meld.size - 1;
    for (final position in positionsOf(rank)) {
      if (position == start - 1 || position == end + 1) return true;
    }
  }
  return false;
}

class _MutableOpponentRead {
  final Set<int> pickedUpRanks = {};
  final Set<int> discardedRanks = {};
}
