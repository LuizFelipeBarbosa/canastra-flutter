/// Deterministic, headless policy comparisons over the authoritative engine.
///
/// Each seed is replayed with the policies on opposite sides. Averaging those
/// two score differences leaves the result in points-per-game units while
/// cancelling much of the variation caused by the deal.
library;

import 'dart:math' as math;

import '../engine/action.dart';
import '../engine/config.dart';
import '../engine/match.dart';
import '../multiplayer/table_view.dart';
import 'agent.dart';
import 'smart_agent.dart';

/// Builds a fresh agent per game so no PRNG state leaks between games.
typedef AgentFactory = Agent Function(int seed);

/// Resolve the stable policy names accepted by the arena CLI.
AgentFactory agentFactory(String name) => switch (name) {
  'easy' => (seed) => RandomAgent(seed: seed),
  'normal' => (seed) => HeuristicAgent(seed: seed, noise: 1.0),
  'hard-legacy' => (seed) => HeuristicAgent(seed: seed, noise: 0.05),
  'hard' => (seed) => Agent.forLevel(AgentLevel.hard, seed: seed),
  'smart' => (seed) => SmartAgent(seed: seed),
  _ => throw ArgumentError.value(name, 'name', 'unknown arena policy'),
};

class ArenaSpec {
  final RulesConfig cfg;

  /// Number of paired observations. Each seed runs in both orientations.
  final int games;
  final int baseSeed;
  final AgentFactory makeA;
  final AgentFactory makeB;
  final String nameA;
  final String nameB;

  const ArenaSpec({
    required this.cfg,
    required this.games,
    required this.baseSeed,
    required this.makeA,
    required this.makeB,
    this.nameA = 'A',
    this.nameB = 'B',
  });
}

/// One seed's two orientations, expressed from policy A's perspective.
class ArenaObservation {
  final int seed;
  final int normalDiff;
  final int swappedDiff;

  const ArenaObservation({
    required this.seed,
    required this.normalDiff,
    required this.swappedDiff,
  });

  double get pairedDiff => (normalDiff + swappedDiff) / 2;
}

/// Action-level measurements that help explain a policy result.
class PolicyDiagnostics {
  final int draws;
  final int pileTakes;
  final int turns;
  final int rounds;
  final int canastras;
  final int discards;
  final int discardedCardValue;

  const PolicyDiagnostics({
    required this.draws,
    required this.pileTakes,
    required this.turns,
    required this.rounds,
    required this.canastras,
    required this.discards,
    required this.discardedCardValue,
  });

  double get pileTakeRate => draws == 0 ? 0 : pileTakes / draws;
  double get meanTurnsPerRound => rounds == 0 ? 0 : turns / rounds;
  double get canastrasPerRound => rounds == 0 ? 0 : canastras / rounds;
  double get meanDiscardedCardValue =>
      discards == 0 ? 0 : discardedCardValue / discards;
}

class ArenaResult {
  final bool isMatch;
  final String nameA;
  final String nameB;
  final List<ArenaObservation> observations;
  final int n;
  final double meanDiff;
  final double seDiff;

  /// Outcomes across the two constituent games in every observation.
  final int winsA;
  final int winsB;
  final int draws;
  final PolicyDiagnostics diagnosticsA;
  final PolicyDiagnostics diagnosticsB;

  const ArenaResult({
    required this.isMatch,
    required this.nameA,
    required this.nameB,
    required this.observations,
    required this.n,
    required this.meanDiff,
    required this.seDiff,
    required this.winsA,
    required this.winsB,
    required this.draws,
    required this.diagnosticsA,
    required this.diagnosticsB,
  });

  String format() {
    final lines = <String>[
      'Pairing: $nameA (A) vs $nameB (B)',
      'Mode: ${isMatch ? 'full matches' : 'paired single rounds'}',
      'Paired observations: n=$n (${2 * n} games)',
      'Mean paired differential (A - B): '
          '${_signed(meanDiff)} +/- ${seDiff.toStringAsFixed(2)} SE',
    ];
    if (isMatch) {
      final total = winsA + winsB + draws;
      final winRate = total == 0 ? 0.0 : winsA / total;
      lines.add(
        'Match win rate (A): ${(100 * winRate).toStringAsFixed(1)}% '
        '(A $winsA, B $winsB, draws $draws)',
      );
    }

    final labelWidth = [nameA.length, nameB.length].fold<int>(
      6,
      (width, length) => length > width ? length : width,
    );
    lines.addAll([
      '',
      'Diagnostics',
      '${'Policy'.padRight(labelWidth)}  Pile take  Turns/round  '
          'Canastras/round  Discard value',
      _diagnosticRow(nameA, labelWidth, diagnosticsA),
      _diagnosticRow(nameB, labelWidth, diagnosticsB),
    ]);
    return lines.join('\n');
  }
}

/// Compare one round per orientation. No next round is ever dealt.
ArenaResult runRoundArena(
  ArenaSpec spec, {
  void Function(int done, int total)? onProgress,
}) => _runArena(spec, matchMode: false, onProgress: onProgress);

/// Compare full matches played to the configured profile target.
ArenaResult runMatchArena(
  ArenaSpec spec, {
  void Function(int done, int total)? onProgress,
}) => _runArena(spec, matchMode: true, onProgress: onProgress);

const int _maxActionsPerGame = 1000000;
const int _largestSeed = 0x7fffffff;

ArenaResult _runArena(
  ArenaSpec spec, {
  required bool matchMode,
  void Function(int done, int total)? onProgress,
}) {
  if (spec.games <= 0) {
    throw ArgumentError.value(spec.games, 'games', 'must be positive');
  }
  if (spec.cfg.table.numSides != 2) {
    throw ArgumentError(
      'arena comparisons require exactly two sides, got '
      '${spec.cfg.table.numSides}',
    );
  }

  final diagnosticsA = _MutableDiagnostics();
  final diagnosticsB = _MutableDiagnostics();
  final observations = <ArenaObservation>[];
  var winsA = 0;
  var winsB = 0;
  var draws = 0;

  for (var game = 0; game < spec.games; game++) {
    final seed = _positiveSeed(spec.baseSeed + game);
    final normal = _playGame(
      spec,
      seed: seed,
      swapped: false,
      matchMode: matchMode,
      diagnosticsA: diagnosticsA,
      diagnosticsB: diagnosticsB,
    );
    final swapped = _playGame(
      spec,
      seed: seed,
      swapped: true,
      matchMode: matchMode,
      diagnosticsA: diagnosticsA,
      diagnosticsB: diagnosticsB,
    );
    observations.add(
      ArenaObservation(
        seed: seed,
        normalDiff: normal,
        swappedDiff: swapped,
      ),
    );

    for (final diff in [normal, swapped]) {
      if (diff > 0) {
        winsA++;
      } else if (diff < 0) {
        winsB++;
      } else {
        draws++;
      }
    }
    onProgress?.call(game + 1, spec.games);
  }

  final differences = [for (final item in observations) item.pairedDiff];
  final mean = differences.reduce((a, b) => a + b) / differences.length;
  var squaredDeviation = 0.0;
  for (final difference in differences) {
    squaredDeviation += math.pow(difference - mean, 2).toDouble();
  }
  final standardError = differences.length < 2
      ? 0.0
      : math.sqrt(
          squaredDeviation /
              (differences.length - 1) /
              differences.length,
        );

  return ArenaResult(
    isMatch: matchMode,
    nameA: spec.nameA,
    nameB: spec.nameB,
    observations: List.unmodifiable(observations),
    n: observations.length,
    meanDiff: mean,
    seDiff: standardError,
    winsA: winsA,
    winsB: winsB,
    draws: draws,
    diagnosticsA: diagnosticsA.freeze(),
    diagnosticsB: diagnosticsB.freeze(),
  );
}

int _playGame(
  ArenaSpec spec, {
  required int seed,
  required bool swapped,
  required bool matchMode,
  required _MutableDiagnostics diagnosticsA,
  required _MutableDiagnostics diagnosticsB,
}) {
  final match = Match(cfg: spec.cfg, seed: seed);
  final agents = <Agent>[];
  final seatUsesA = <bool>[];
  for (var seat = 0; seat < spec.cfg.table.numPlayers; seat++) {
    final isA = (spec.cfg.table.side(seat) == 0) != swapped;
    seatUsesA.add(isA);
    final agentSeed = _positiveSeed(seed + 977 * seat);
    agents.add(isA ? spec.makeA(agentSeed) : spec.makeB(agentSeed));
  }
  final playerNames = [
    for (var seat = 0; seat < spec.cfg.table.numPlayers; seat++) 'seat $seat',
  ];

  var actions = 0;
  while (!match.matchOver) {
    if (match.round.roundOver) {
      if (!matchMode) break;
      match.startNextRound();
      continue;
    }
    if (++actions > _maxActionsPerGame) {
      throw StateError(
        'arena exceeded $_maxActionsPerGame actions for seed $seed',
      );
    }

    final seat = match.currentPlayer;
    final view = buildTableView(match, seat, playerNames: playerNames);
    final actionId = agents[seat].chooseAction(spec.cfg, view);
    final diagnostics = seatUsesA[seat] ? diagnosticsA : diagnosticsB;
    diagnostics.observe(spec.cfg, view, actionId);
    final result = match.applyId(actionId);
    if (result != null) {
      diagnosticsA.rounds++;
      diagnosticsB.rounds++;
    }
  }

  if (matchMode) {
    return _scoreDifference(match.matchScores, swapped: swapped);
  }
  final result = match.lastRoundResult;
  if (result == null) {
    throw StateError('round ended without a result for seed $seed');
  }
  return _scoreDifference(
    [for (final side in result.sheet) side.total],
    swapped: swapped,
  );
}

int _scoreDifference(List<int> sideScores, {required bool swapped}) =>
    swapped ? sideScores[1] - sideScores[0] : sideScores[0] - sideScores[1];

/// Dart's `%` keeps a negative dividend's sign. This mapping makes every seed
/// safe for the engine PRNG while preserving ordinary positive seed values.
int _positiveSeed(int value) {
  final reduced = value % _largestSeed;
  return reduced > 0 ? reduced : reduced + _largestSeed;
}

class _MutableDiagnostics {
  int draws = 0;
  int pileTakes = 0;
  int turns = 0;
  int rounds = 0;
  int canastras = 0;
  int discards = 0;
  int discardedCardValue = 0;

  void observe(RulesConfig cfg, TableView view, int actionId) {
    final action = decodeAction(actionId, cfg.meld.maxMeldSlots);
    switch (action) {
      case DrawDeck():
        draws++;
        turns++;
      case DrawTrash():
        draws++;
        pileTakes++;
        turns++;
      case AddToMeld(:final slot):
        if (slot < view.myMelds.length &&
            view.myMelds[slot].size == cfg.meld.canastraMinSize - 1) {
          canastras++;
        }
      case CreateSeq() || CreateSet():
        if (cfg.meld.minMeldSize >= cfg.meld.canastraMinSize) canastras++;
      case Discard(:final ct):
        discards++;
        discardedCardValue += cfg.cardValue(ct);
      case GoOut() || EndRound():
        break;
    }
  }

  PolicyDiagnostics freeze() => PolicyDiagnostics(
    draws: draws,
    pileTakes: pileTakes,
    turns: turns,
    rounds: rounds,
    canastras: canastras,
    discards: discards,
    discardedCardValue: discardedCardValue,
  );
}

String _signed(double value) {
  final formatted = value.toStringAsFixed(2);
  return value > 0 ? '+$formatted' : formatted;
}

String _diagnosticRow(
  String label,
  int labelWidth,
  PolicyDiagnostics diagnostics,
) =>
    '${label.padRight(labelWidth)}  '
    '${(100 * diagnostics.pileTakeRate).toStringAsFixed(1).padLeft(8)}%  '
    '${diagnostics.meanTurnsPerRound.toStringAsFixed(2).padLeft(11)}  '
    '${diagnostics.canastrasPerRound.toStringAsFixed(2).padLeft(15)}  '
    '${diagnostics.meanDiscardedCardValue.toStringAsFixed(2).padLeft(13)}';
