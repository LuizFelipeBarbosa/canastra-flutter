/// Bot opponents.
///
/// Agents decide from a [TableView] plus the (public) rules config — exactly
/// the information a remote human player receives. They have no access to the
/// authoritative [RoundState], so a bot cannot see hands, the stock order or a
/// morto's contents even though it happens to run inside the host process.
library;

import '../engine/action.dart';
import '../engine/cards.dart';
import '../engine/config.dart';
import '../engine/prng.dart';
import '../multiplayer/table_view.dart';

enum AgentLevel {
  /// Plays a legal move at random. Chaotic, and a gentle first opponent.
  easy,

  /// Greedy: melds naturals, hoards wilds, takes a pile that connects.
  normal,

  /// The same policy with the tie-breaking noise turned down.
  hard,
}

abstract class Agent {
  /// An action id drawn from `view.legalActions`.
  int chooseAction(RulesConfig cfg, TableView view);

  factory Agent.forLevel(AgentLevel level, {int seed = 0}) => switch (level) {
    AgentLevel.easy => RandomAgent(seed: seed),
    AgentLevel.normal => HeuristicAgent(seed: seed, noise: 1.0),
    AgentLevel.hard => HeuristicAgent(seed: seed, noise: 0.05),
  };
}

class RandomAgent implements Agent {
  final Prng _rng;
  RandomAgent({int seed = 0}) : _rng = Prng(seed);

  @override
  int chooseAction(RulesConfig cfg, TableView view) {
    final legal = view.legalActions;
    if (legal.isEmpty) throw StateError('no legal action to choose from');
    return legal[_rng.nextInt(legal.length)];
  }
}

/// A greedy rule-based policy.
///
/// Priorities: go out when possible; meld naturals aggressively; spend wilds
/// reluctantly, and more willingly when they complete a canastra; take the
/// discard pile when it connects to the hand or to an own meld; discard the
/// least connected, cheapest card.
class HeuristicAgent implements Agent {
  final Prng _rng;

  /// Scale of the random tie-breaker. Scores are spaced tens apart, so noise
  /// around 1.0 only ever reorders moves the policy rates as near-equivalent.
  final double noise;

  HeuristicAgent({int seed = 0, this.noise = 1.0}) : _rng = Prng(seed);

  @override
  int chooseAction(RulesConfig cfg, TableView view) {
    final legal = view.legalActions;
    if (legal.isEmpty) throw StateError('no legal action to choose from');

    final hand = <CardId, int>{};
    for (final ct in view.hand) {
      hand[ct] = (hand[ct] ?? 0) + 1;
    }

    var bestId = legal.first;
    var bestScore = double.negativeInfinity;
    for (final id in legal) {
      final action = decodeAction(id, cfg.meld.maxMeldSlots);
      final score = _score(action, cfg, view, hand) + _rng.nextDouble() * noise;
      if (score > bestScore) {
        bestScore = score;
        bestId = id;
      }
    }
    return bestId;
  }

  double _score(
    GameAction action,
    RulesConfig cfg,
    TableView view,
    Map<CardId, int> hand,
  ) {
    switch (action) {
      case GoOut():
        return 10000;
      case CreateSeq(:final wild):
        return wild == seqWildNoneValue ? 900 : 500;
      case CreateSet(:final wild):
        return wild == seqWildNoneValue ? 850 : 450;
      case AddToMeld(:final slot, :final ct):
        final myMelds = view.myMelds;
        final target = slot < myMelds.length ? myMelds[slot] : null;
        final completes =
            target != null && target.size == view.canastraMinSize - 1;
        if (cfg.isWildCard(ct)) return 300 + (completes ? 250 : 0);
        return 700 + (completes ? 150 : 0);
      case DrawTrash():
        if (!_pileConnects(cfg, view, hand)) return 100;
        // A pile that connects is worth taking, but a huge one floods the hand
        // and pushes going out further away. Without this the policy will take
        // the pile every single turn, the stock never depletes, and two greedy
        // bots pass the same pile back and forth until the round is truncated.
        final flood = (view.trash.length - 10).clamp(0, 40);
        return 600 - 25.0 * flood;
      case DrawDeck():
        return 400;
      case Discard(:final ct):
        return 200 - 10 * _usefulness(cfg, ct, hand) - cfg.cardValue(ct) / 20.0;
      case EndRound():
        return 50;
    }
  }

  /// Does any card in the pile pair with the hand or extend one of my melds?
  bool _pileConnects(RulesConfig cfg, TableView view, Map<CardId, int> hand) {
    final ranksInHand = {
      for (final c in hand.keys)
        if (c != kJoker) idRank(c),
    };
    for (final card in view.trash) {
      // A free wild is always worth taking.
      if (card == kJoker || cfg.isWildCard(card)) return true;
      if (ranksInHand.contains(idRank(card))) return true;
      for (final meld in view.myMelds) {
        if (meld.isSequence && meld.suit == idSuit(card)) {
          final start = meld.startPos!;
          final end = start + meld.size - 1;
          for (final p in positionsOf(idRank(card)!)) {
            if (p == start - 1 || p == end + 1) return true;
          }
        }
        if (!meld.isSequence && meld.rank == idRank(card)) return true;
      }
    }
    return false;
  }

  /// How connected a card is to the rest of the hand — higher means keep it.
  double _usefulness(RulesConfig cfg, CardId ct, Map<CardId, int> hand) {
    // Never throw a wild if there is any alternative.
    if (cfg.isWildCard(ct)) return 12;
    final rank = idRank(ct)!;
    final suit = idSuit(ct)!;

    var sameRank = 0;
    hand.forEach((c, n) {
      if (c != ct && c != kJoker && idRank(c) == rank) sameRank += n;
    });

    var neighbours = 0;
    hand.forEach((other, n) {
      if (other == ct || other == kJoker || idSuit(other) != suit) return;
      var gap = 99;
      for (final p in positionsOf(rank)) {
        for (final q in positionsOf(idRank(other)!)) {
          final d = (p - q).abs();
          if (d < gap) gap = d;
        }
      }
      if (gap >= 1 && gap <= 2) neighbours += n;
    });

    return 2.0 * sameRank + neighbours + ((hand[ct] ?? 0) - 1);
  }
}

/// `seqWildNone` and `setWildNone` are both 0; naming it once keeps the score
/// table readable without importing the meld layer into the AI.
const int seqWildNoneValue = 0;
