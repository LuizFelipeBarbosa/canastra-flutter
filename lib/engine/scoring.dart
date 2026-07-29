/// Card points, canastra bonuses and round scoring.
///
/// Every card scores its own face value regardless of what a wild represents.
/// Round scores are per side; match accumulation lives in [MatchState].
library;

import 'config.dart';
import 'meld.dart';
import 'state.dart';

int meldPoints(RulesConfig cfg, Meld meld) =>
    meld.slots.fold(0, (sum, slot) => sum + cfg.cardValue(slot.card));

int canastraBonus(RulesConfig cfg, Meld meld) {
  if (!meld.isCanastra(cfg.meld.canastraMinSize)) return 0;
  return meld.isClean ? cfg.meld.canastraBonusClean : cfg.meld.canastraBonusDirty;
}

int handPoints(RulesConfig cfg, RoundState state, int player) => state
    .hands[player].entries
    .fold(0, (sum, e) => sum + cfg.cardValue(e.key) * e.value);

/// One line of the round score sheet — what the UI shows players after a round.
class ScoreLine {
  final String label;
  final int points;
  const ScoreLine(this.label, this.points);
}

/// Itemised round score for one side.
class SideScore {
  final int side;
  final List<ScoreLine> lines;
  final int total;
  const SideScore({required this.side, required this.lines, required this.total});
}

/// Final (or would-be) round score per side, itemised.
///
/// Meaningful at [Phase.terminal]; before that it is a running estimate that
/// deliberately still counts hidden hand penalties, so only show it to a player
/// for their own side.
List<SideScore> roundScoreSheet(RoundState state) {
  final cfg = state.cfg;
  final numSides = cfg.table.numSides;
  final lines = List.generate(numSides, (_) => <ScoreLine>[]);

  for (var side = 0; side < numSides; side++) {
    var meldTotal = 0;
    var bonusTotal = 0;
    for (final meld in state.melds.where((m) => m.owner == side)) {
      meldTotal += meldPoints(cfg, meld);
      bonusTotal += canastraBonus(cfg, meld);
    }
    if (meldTotal != 0) lines[side].add(ScoreLine('Melded cards', meldTotal));
    if (bonusTotal != 0) lines[side].add(ScoreLine('Canastra bonuses', bonusTotal));
  }

  if (state.wentOutSide != null) {
    final side = state.wentOutSide!;
    lines[side].add(ScoreLine('Went out', cfg.goingOut.goOutBonus));
    if (cfg.goingOut.concealedBonus != 0 &&
        state.openedOnTurn.isNotEmpty &&
        state.openedOnTurn[side] == state.turnNumber) {
      lines[side].add(ScoreLine('Concealed', cfg.goingOut.concealedBonus));
    }
  }

  if (cfg.specialThrees.redThreeMode == red3BonusAutoreplace) {
    for (var side = 0; side < state.redThrees.length; side++) {
      final tray = state.redThrees[side];
      if (tray.isEmpty) continue;
      var bonus = tray.length * cfg.specialThrees.redThreeBonus;
      if (tray.length == 4) bonus += cfg.specialThrees.redThreeAllBonus;
      final opened = state.melds.any((m) => m.owner == side);
      final negative = cfg.specialThrees.redThreeNegativeIfNoMeld && !opened;
      lines[side].add(ScoreLine('Red threes', negative ? -bonus : bonus));
    }
  }

  if (cfg.morto.count != 0) {
    for (var side = 0; side < numSides; side++) {
      if (side < state.mortoTaken.length && !state.mortoTaken[side]) {
        lines[side].add(ScoreLine('Morto not taken', -cfg.morto.untakenPenalty));
      }
    }
  }

  final mode = cfg.scoring.handPenaltyMode;
  if (mode == handPenaltySelfNegative) {
    final penalty = List.filled(numSides, 0);
    for (var player = 0; player < cfg.table.numPlayers; player++) {
      penalty[cfg.table.side(player)] += handPoints(cfg, state, player);
    }
    for (var side = 0; side < numSides; side++) {
      if (penalty[side] != 0) {
        lines[side].add(ScoreLine('Cards left in hand', -penalty[side]));
      }
    }
  } else if (mode == handPenaltyOpponentPositive) {
    if (state.wentOutSide != null) {
      var gained = 0;
      for (var p = 0; p < cfg.table.numPlayers; p++) {
        if (cfg.table.side(p) != state.wentOutSide) {
          gained += handPoints(cfg, state, p);
        }
      }
      if (gained != 0) {
        lines[state.wentOutSide!].add(ScoreLine("Opponents' cards", gained));
      }
    }
  } else {
    throw ArgumentError('unknown hand penalty mode: $mode');
  }

  return [
    for (var side = 0; side < numSides; side++)
      SideScore(
        side: side,
        lines: lines[side],
        total: lines[side].fold(0, (sum, l) => sum + l.points),
      ),
  ];
}

/// Final (or would-be) round score per side.
List<int> roundScores(RoundState state) =>
    [for (final s in roundScoreSheet(state)) s.total];
