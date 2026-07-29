/// Match progression over the round engine: deal, apply, score, deal again.
///
/// This is the authoritative game object. It holds the full ground truth
/// including every hidden zone, so it must only ever live on whoever is hosting
/// the game — in single-player and hot-seat that is the device itself, in
/// online play it is the server. Clients get the redacted `TableView` instead.
library;

import 'action.dart';
import 'cards.dart';
import 'config.dart';
import 'legal.dart';
import 'prng.dart';
import 'scoring.dart';
import 'state.dart';
import 'turns.dart';

/// One thing that happened, for the table log and animation cues.
class GameEvent {
  final int actor;
  final String kind;
  final CardId? card;

  const GameEvent(this.actor, this.kind, {this.card});

  Map<String, dynamic> toJson() => {
    'actor': actor,
    'kind': kind,
    if (card != null) 'card': card,
  };

  factory GameEvent.fromJson(Map<String, dynamic> json) => GameEvent(
    json['actor'] as int,
    json['kind'] as String,
    card: json['card'] as int?,
  );
}

/// How a round ended, ready to show on the score screen.
class RoundResult {
  final int roundIndex;
  final EndReason reason;
  final int? wentOutSide;
  final List<SideScore> sheet;
  final List<int> matchScoresAfter;

  const RoundResult({
    required this.roundIndex,
    required this.reason,
    required this.wentOutSide,
    required this.sheet,
    required this.matchScoresAfter,
  });
}

class Match {
  final RulesConfig cfg;
  final int seed;

  final Prng _rng;
  final List<int> _matchScores;
  final List<GameEvent> _history = [];
  final List<int> _actionLog = [];

  late RoundState _round;
  int _roundIndex = 0;
  RoundResult? _lastRoundResult;
  bool _matchOver = false;

  Match({required this.cfg, required this.seed})
    : _rng = Prng(seed),
      _matchScores = List.filled(cfg.table.numSides, 0) {
    _round = dealRound(cfg, _rng, firstPlayer: 0, matchScores: _matchScores);
  }

  RoundState get round => _round;
  int get roundIndex => _roundIndex;
  List<int> get matchScores => List.unmodifiable(_matchScores);
  List<GameEvent> get history => List.unmodifiable(_history);
  List<int> get actionLog => List.unmodifiable(_actionLog);
  RoundResult? get lastRoundResult => _lastRoundResult;
  bool get matchOver => _matchOver;
  int get currentPlayer => _round.currentPlayer;

  /// The leading side, meaningful once [matchOver].
  int? get winnerSide {
    if (!_matchOver) return null;
    var best = 0;
    for (var s = 1; s < _matchScores.length; s++) {
      if (_matchScores[s] > _matchScores[best]) best = s;
    }
    return best;
  }

  List<int> legalActionIdsNow() =>
      _matchOver ? const [] : legalActionIds(_round);

  List<GameAction> legalActionsNow() =>
      _matchOver ? const [] : legalActions(_round);

  /// Apply one micro-action. Throws [IllegalAction] for anything the legal-move
  /// enumeration would not have offered.
  ///
  /// Returns the round result when this action ended a round, otherwise null.
  RoundResult? applyId(int actionId) {
    if (_matchOver) throw IllegalAction('the match is over');
    final action = decodeAction(actionId, cfg.meld.maxMeldSlots);
    final actor = _round.currentPlayer;
    applyAction(_round, action);
    _actionLog.add(actionId);
    _history.add(_eventFor(action, actor));

    if (!_round.roundOver) return null;

    final sheet = roundScoreSheet(_round);
    for (var side = 0; side < cfg.table.numSides; side++) {
      _matchScores[side] += sheet[side].total;
    }
    final result = RoundResult(
      roundIndex: _roundIndex,
      reason: _round.endReason!,
      wentOutSide: _round.wentOutSide,
      sheet: sheet,
      matchScoresAfter: List.of(_matchScores),
    );
    _lastRoundResult = result;
    if (_matchScores.any((s) => s >= cfg.scoring.matchTarget)) {
      _matchOver = true;
    }
    return result;
  }

  /// Deal the next round. Only valid once the current round is over and the
  /// match target has not been reached.
  void startNextRound() {
    if (_matchOver) throw StateError('the match is over');
    if (!_round.roundOver) throw StateError('the round is still in progress');
    _roundIndex += 1;
    _history.clear();
    _round = dealRound(
      cfg,
      _rng,
      firstPlayer: _roundIndex % cfg.table.numPlayers,
      matchScores: _matchScores,
    );
  }

  GameEvent _eventFor(GameAction action, int actor) => switch (action) {
    DrawDeck() => GameEvent(actor, 'drawDeck'),
    DrawTrash() => GameEvent(actor, 'drawTrash'),
    CreateSeq() => GameEvent(actor, 'createSeq'),
    CreateSet() => GameEvent(actor, 'createSet'),
    AddToMeld(:final ct) => GameEvent(actor, 'add', card: ct),
    Discard(:final ct) => GameEvent(actor, 'discard', card: ct),
    GoOut() => GameEvent(actor, 'goOut'),
    EndRound() => GameEvent(actor, 'endRound'),
  };
}
