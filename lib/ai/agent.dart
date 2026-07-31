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
import 'heuristic_score.dart';
import 'smart_agent.dart';

export 'heuristic_score.dart' show seqWildNoneValue;

enum AgentLevel {
  /// Plays a legal move at random. Chaotic, and a gentle first opponent.
  easy,

  /// Greedy: melds naturals, hoards wilds, takes a pile that connects.
  normal,

  /// Reads opponents' melds, counts unseen cards, and remembers what they took
  /// and threw this round. Changes its play as the stock runs low.
  hard,
}

abstract class Agent {
  /// An action id drawn from `view.legalActions`.
  int chooseAction(RulesConfig cfg, TableView view);

  factory Agent.forLevel(AgentLevel level, {int seed = 0}) => switch (level) {
    AgentLevel.easy => RandomAgent(seed: seed),
    AgentLevel.normal => HeuristicAgent(seed: seed, noise: 1.0),
    AgentLevel.hard => SmartAgent(seed: seed),
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
      final score =
          baseActionScore(cfg, view, hand, action) + _rng.nextDouble() * noise;
      if (score > bestScore) {
        bestScore = score;
        bestId = id;
      }
    }
    return bestId;
  }
}
