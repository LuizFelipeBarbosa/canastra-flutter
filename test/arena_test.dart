import 'package:canastra/ai/agent.dart';
import 'package:canastra/ai/arena.dart';
import 'package:canastra/ai/smart_agent.dart';
import 'package:canastra/engine/profiles.dart';
import 'package:flutter_test/flutter_test.dart';

ArenaSpec _rummySpec({int games = 2}) => ArenaSpec(
  cfg: loadProfile('rummy', numPlayers: 2),
  games: games,
  baseSeed: 1,
  makeA: agentFactory('normal'),
  makeB: agentFactory('easy'),
  nameA: 'normal',
  nameB: 'easy',
);

void main() {
  test('policy names resolve to fresh agents', () {
    expect(agentFactory('easy')(1), isA<RandomAgent>());
    expect(agentFactory('normal')(1), isA<HeuristicAgent>());
    expect(agentFactory('hard-legacy')(1), isA<HeuristicAgent>());
    expect(agentFactory('hard')(1), isA<SmartAgent>());
    expect(() => agentFactory('unknown'), throwsArgumentError);

    expect(agentFactory('easy')(1), isNot(same(agentFactory('easy')(1))));
  });

  test('round arena is paired, deterministic, and reports diagnostics', () {
    final progress = <(int, int)>[];
    final first = runRoundArena(
      _rummySpec(games: 3),
      onProgress: (done, total) => progress.add((done, total)),
    );
    final second = runRoundArena(_rummySpec(games: 3));

    expect(first.n, 3);
    expect(first.observations, hasLength(3));
    expect(progress, [(1, 3), (2, 3), (3, 3)]);
    expect(first.winsA + first.winsB + first.draws, 6);
    expect(first.format(), second.format());
    expect(
      first.observations.map((item) => item.normalDiff),
      second.observations.map((item) => item.normalDiff),
    );
    expect(first.diagnosticsA.rounds, 6);
    expect(first.diagnosticsB.rounds, 6);
    expect(first.diagnosticsA.pileTakeRate, inInclusiveRange(0, 1));
    expect(first.diagnosticsB.meanDiscardedCardValue, greaterThanOrEqualTo(0));
  });

  test('match arena reaches the rummy target in both orientations', () {
    final result = runMatchArena(_rummySpec(games: 1));

    expect(result.isMatch, isTrue);
    expect(result.n, 1);
    expect(result.winsA + result.winsB + result.draws, 2);
    expect(result.diagnosticsA.rounds, greaterThanOrEqualTo(2));
    expect(result.diagnosticsB.rounds, result.diagnosticsA.rounds);
    expect(result.format(), contains('Match win rate'));
  });

  test('smart has a reproducible advantage over hard-legacy', () {
    final result = runRoundArena(
      ArenaSpec(
        cfg: loadProfile('buraco', numPlayers: 2),
        games: 1000,
        baseSeed: 1,
        makeA: agentFactory('smart'),
        makeB: agentFactory('hard-legacy'),
        nameA: 'smart',
        nameB: 'hard-legacy',
      ),
    );
    final reason =
        'meanDiff=${result.meanDiff} seDiff=${result.seDiff}; '
        'smart must retain a large, reproducible advantage over hard-legacy';

    expect(result.meanDiff, greaterThan(25), reason: reason);
    // A raw point or win-rate gate can drift with tuning or pass by luck on a
    // small sample; clearing multiple standard errors shows a real advantage.
    expect(result.meanDiff > 2 * result.seDiff, isTrue, reason: reason);
  }, tags: ['arena']);
}
