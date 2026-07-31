import '../engine/action.dart';
import '../engine/config.dart';
import '../engine/prng.dart';
import '../multiplayer/table_view.dart';
import 'agent.dart';
import 'heuristic_score.dart';
import 'signals.dart';

class SmartAgent implements Agent {
  final Prng _rng;
  final double noise;
  final SignalWeights weights;

  SmartAgent({
    int seed = 0,
    this.noise = 0.05,
    this.weights = defaultSignalWeights,
  }) : _rng = Prng(seed);

  @override
  int chooseAction(RulesConfig cfg, TableView view) {
    final legal = view.legalActions;
    if (legal.isEmpty) throw StateError('no legal action to choose from');

    final facts = TurnFacts.of(cfg, view, weights: weights);
    var bestId = legal.first;
    var bestScore = double.negativeInfinity;
    for (final id in legal) {
      final action = decodeAction(id, cfg.meld.maxMeldSlots);
      final score =
          baseActionScore(cfg, view, facts.hand, action) +
          signalDelta(cfg, view, facts, action, weights: weights) +
          _rng.nextDouble() * noise;
      if (score > bestScore) {
        bestScore = score;
        bestId = id;
      }
    }
    return bestId;
  }
}
