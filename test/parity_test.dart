/// Cross-validation of the Dart engine against the reference Python engine.
///
/// Each trace in `test/data/parity_traces.json` carries a recorded deck order,
/// every step's full legal-action id set, the action taken, and the final
/// scores. Dealing from the same deck order and replaying the same actions must
/// reproduce the legal-action set exactly at every step — an off-by-one in a
/// wildcard rule or an anti-stranding guard shows up as a set difference long
/// before it shows up as a wrong score.
///
/// Regenerate with `tool/export_parity_traces.py` (see its docstring).
library;

import 'dart:convert';
import 'dart:io';

import 'package:canastra/engine/legal.dart';
import 'package:canastra/engine/profiles.dart';
import 'package:canastra/engine/scoring.dart';
import 'package:canastra/engine/state.dart';
import 'package:canastra/engine/turns.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final file = File('test/data/parity_traces.json');
  if (!file.existsSync()) {
    test('parity traces are present', () {
      fail('missing ${file.path}; run tool/export_parity_traces.py');
    });
    return;
  }

  final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final traces = (data['traces'] as List).cast<Map<String, dynamic>>();

  test('the trace corpus covers every profile and table size', () {
    final setups = {
      for (final t in traces) '${t['profile']}-${t['num_players']}p',
    };
    expect(
      setups,
      containsAll([
        'buraco-2p', 'buraco-4p',
        'canasta-2p', 'canasta-4p',
        'biriba-2p', 'biriba-4p',
        'rummy-2p',
      ]),
    );
  });

  for (final trace in traces) {
    final profile = trace['profile'] as String;
    final numPlayers = trace['num_players'] as int;
    final seed = trace['seed'] as int;

    test('$profile ${numPlayers}p seed $seed matches the Python engine', () {
      final cfg = loadProfile(profile, numPlayers: numPlayers);
      final stock = (trace['stock'] as List).cast<int>().toList();
      final state = dealRoundFromStock(cfg, stock);

      final steps = (trace['steps'] as List).cast<Map<String, dynamic>>();
      for (var i = 0; i < steps.length; i++) {
        final expectedLegal = (steps[i]['legal'] as List).cast<int>();
        expect(
          legalActionIds(state),
          equals(expectedLegal),
          reason: 'legal actions diverged at step $i '
              '(turn ${state.turnNumber}, seat ${state.currentPlayer}, '
              'phase ${state.phase.name})',
        );
        applyActionId(state, steps[i]['action'] as int);
      }

      expect(state.roundOver, equals(trace['round_over'] as bool),
          reason: 'round-over flag diverged');
      expect(state.wentOutSide, equals(trace['went_out_side'] as int?),
          reason: 'going-out side diverged');
      final endReason = trace['end_reason'] as int?;
      expect(state.endReason?.index, equals(endReason),
          reason: 'end reason diverged');
      expect(roundScores(state), equals((trace['scores'] as List).cast<int>()),
          reason: 'final round scores diverged');
    });
  }
}
