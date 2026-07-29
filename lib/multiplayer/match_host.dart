/// The authoritative host: the one place that owns real game state.
///
/// It accepts [ClientCommand]s tagged with the seat they came from, validates
/// them against the engine, and emits [ServerEvent]s addressed to a single seat
/// or broadcast to all. It knows nothing about sockets or widgets, so the same
/// class backs local single-player today and a server process later — a server
/// is this object plus a socket loop.
library;

import 'dart:async';

import '../ai/agent.dart';
import '../engine/config.dart';
import '../engine/match.dart';
import '../engine/turns.dart';
import 'protocol.dart';
import 'table_view.dart';

/// An event and its addressee; [seat] of null means broadcast.
typedef HostMessage = ({int? seat, ServerEvent event});

class MatchHost {
  final String roomCode;
  final RulesConfig cfg;
  final int seed;

  /// How long a bot "thinks" before moving, ~600ms in the app so the table
  /// reads as a sequence of moves rather than one jump.
  ///
  /// [Duration.zero] switches bots to manual: nothing is scheduled and the
  /// caller drives them with [runBotsSynchronously]. Tests use that to keep
  /// play deterministic and free of pending timers.
  final Duration botDelay;

  final List<SeatInfo> _seats;
  final Map<int, Agent> _agents = {};
  final _outbound = StreamController<HostMessage>.broadcast();

  Match _match;
  bool _started = false;
  bool _disposed = false;
  int _botGeneration = 0;

  MatchHost({
    required this.roomCode,
    required this.cfg,
    required this.seed,
    required List<SeatInfo> seats,
    AgentLevel botLevel = AgentLevel.normal,
    this.botDelay = const Duration(milliseconds: 600),
  }) : _seats = List.of(seats),
       _match = Match(cfg: cfg, seed: seed) {
    if (seats.length != cfg.table.numPlayers) {
      throw ArgumentError(
        'expected ${cfg.table.numPlayers} seats, got ${seats.length}',
      );
    }
    for (final s in _seats) {
      if (s.kind == SeatKind.bot) {
        _agents[s.seat] = Agent.forLevel(botLevel, seed: seed + 977 * s.seat);
      }
    }
  }

  Stream<HostMessage> get outbound => _outbound.stream;

  List<SeatInfo> get seats => List.unmodifiable(_seats);
  Match get match => _match;
  bool get started => _started;

  /// Everyone who is not a bot has readied up (bots are always ready).
  bool get everyoneReady =>
      _seats.every((s) => s.kind == SeatKind.bot || s.ready);

  // --- command handling -----------------------------------------------------

  void handle(int seat, ClientCommand cmd) {
    if (_disposed) return;
    switch (cmd) {
      case JoinRoom(:final playerName):
        _updateSeat(seat, (s) => s.copyWith(name: playerName, connected: true));
        _emit(seat, Joined(roomCode: roomCode, seat: seat));
        _broadcastLobby();
        if (_started) _pushTable(seat);

      case SetReady(:final ready):
        _updateSeat(seat, (s) => s.copyWith(ready: ready));
        _broadcastLobby();
        if (!_started && everyoneReady) start();

      case SubmitAction(:final actionId):
        _submit(seat, actionId);

      case RequestNextRound():
        _nextRound();

      case RequestRematch():
        _rematch();

      case LeaveRoom():
        _updateSeat(seat, (s) => s.copyWith(connected: false, ready: false));
        _broadcastLobby();
    }
  }

  /// Begin play. Idempotent.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _broadcastLobby();
    _broadcastTable();
    _scheduleBot();
  }

  void _submit(int seat, int actionId) {
    if (!_started) {
      _emit(seat, const ServerError(message: 'the game has not started'));
      return;
    }
    if (_match.matchOver || _match.round.roundOver) {
      _emit(
        seat,
        ActionRejected(actionId: actionId, reason: 'the round is already over'),
      );
      _pushTable(seat);
      return;
    }
    if (_match.currentPlayer != seat) {
      _emit(
        seat,
        ActionRejected(actionId: actionId, reason: 'it is not your turn'),
      );
      _pushTable(seat);
      return;
    }
    _applyAndBroadcast(seat, actionId);
  }

  void _applyAndBroadcast(int seat, int actionId) {
    try {
      _match.applyId(actionId);
    } on IllegalAction catch (e) {
      _emit(seat, ActionRejected(actionId: actionId, reason: e.message));
      _pushTable(seat);
      return;
    } on ArgumentError catch (e) {
      _emit(
        seat,
        ActionRejected(actionId: actionId, reason: e.message.toString()),
      );
      _pushTable(seat);
      return;
    }
    _broadcastTable();

    if (_match.round.roundOver) {
      // Nobody human is watching, so keep the match moving on its own.
      final anyHuman = _seats.any(
        (s) =>
            s.kind != SeatKind.bot && s.kind != SeatKind.empty && s.connected,
      );
      if (!anyHuman && !_match.matchOver) {
        _nextRound();
      }
      return;
    }
    _scheduleBot();
  }

  void _nextRound() {
    if (_match.matchOver || !_match.round.roundOver) return;
    _match.startNextRound();
    _broadcastTable();
    _scheduleBot();
  }

  void _rematch() {
    if (!_match.matchOver) return;
    _botGeneration++;
    _match = Match(cfg: cfg, seed: seed + 1013 * (_match.roundIndex + 1));
    _broadcastTable();
    _scheduleBot();
  }

  // --- bots ------------------------------------------------------------------

  /// If the seat to act is a bot, play its move after [botDelay].
  ///
  /// [_botGeneration] invalidates a pending move if the match is replaced while
  /// the timer is in flight, so a stale bot can never act on a fresh table.
  void _scheduleBot() {
    if (_disposed || !_started) return;
    if (botDelay == Duration.zero) return; // manual mode; see [botDelay]
    if (_match.matchOver || _match.round.roundOver) return;
    final seat = _match.currentPlayer;
    final agent = _agents[seat];
    if (agent == null) return;

    final generation = _botGeneration;
    Future<void> play() async {
      await Future<void>.delayed(botDelay);
      if (_disposed || generation != _botGeneration) return;
      if (_match.matchOver || _match.round.roundOver) return;
      if (_match.currentPlayer != seat) return;
      final view = buildTableView(_match, seat, playerNames: _playerNames);
      if (view.legalActions.isEmpty) return;
      _applyAndBroadcast(seat, agent.chooseAction(cfg, view));
    }

    unawaited(play());
  }

  /// Play out every bot turn immediately, with no delay. For tests and for
  /// fast-forwarding a hot-seat table.
  void runBotsSynchronously({int maxActions = 20000}) {
    var guard = 0;
    while (!_match.matchOver &&
        !_match.round.roundOver &&
        _agents.containsKey(_match.currentPlayer) &&
        guard++ < maxActions) {
      final seat = _match.currentPlayer;
      final view = buildTableView(_match, seat, playerNames: _playerNames);
      if (view.legalActions.isEmpty) break;
      _applyAndBroadcast(seat, _agents[seat]!.chooseAction(cfg, view));
    }
  }

  // --- outbound --------------------------------------------------------------

  List<String> get _playerNames => [for (final s in _seats) s.name];

  void _updateSeat(int seat, SeatInfo Function(SeatInfo) update) {
    final i = _seats.indexWhere((s) => s.seat == seat);
    if (i >= 0) _seats[i] = update(_seats[i]);
  }

  void _emit(int? seat, ServerEvent event) {
    if (_disposed) return;
    _outbound.add((seat: seat, event: event));
  }

  void _broadcastLobby() => _emit(
    null,
    LobbyUpdate(
      roomCode: roomCode,
      profile: cfg.name,
      numPlayers: cfg.table.numPlayers,
      seats: seats,
      started: _started,
    ),
  );

  void _pushTable(int seat) => _emit(
    seat,
    TableUpdate(view: buildTableView(_match, seat, playerNames: _playerNames)),
  );

  void _broadcastTable() {
    for (final s in _seats) {
      _pushTable(s.seat);
    }
  }

  void dispose() {
    _disposed = true;
    _botGeneration++;
    _outbound.close();
  }
}
