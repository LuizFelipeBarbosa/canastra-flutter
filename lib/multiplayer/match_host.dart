/// The authoritative host: the one place that owns real game state.
///
/// It accepts [ClientCommand]s tagged with the seat they came from, validates
/// them against the engine, and emits [ServerEvent]s addressed to a single seat
/// or broadcast to all. It knows nothing about sockets or widgets, so the same
/// class backs local single-player today and a server process later — a server
/// is this object plus a socket loop.
library;

import 'dart:async';
import 'dart:math';

import '../ai/agent.dart';
import '../engine/config.dart';
import '../engine/match.dart';
import '../engine/turns.dart';
import 'protocol.dart';
import 'table_view.dart';

/// An event and its addressee; [seat] of null means broadcast.
typedef HostMessage = ({int? seat, ServerEvent event});

typedef RoundOverCallback =
    void Function(
      RoundResult result,
      Match match, {
      required String matchId,
      required DateTime startedAt,
    });

typedef MatchOverCallback =
    void Function(
      Match match, {
      required String matchId,
      required DateTime startedAt,
    });

/// Outbound addressee used for one public-only view shared by all spectators.
const int spectatorHostSeat = -1;

final _uuidRandom = Random.secure();

/// Mint a time-ordered UUIDv7 using the current millisecond and secure entropy.
String uuidV7() {
  final bytes = List<int>.generate(16, (_) => _uuidRandom.nextInt(256));
  var milliseconds = DateTime.now().millisecondsSinceEpoch;
  for (var i = 5; i >= 0; i--) {
    bytes[i] = milliseconds & 0xff;
    milliseconds >>= 8;
  }
  bytes[6] = 0x70 | (bytes[6] & 0x0f);
  bytes[8] = 0x80 | (bytes[8] & 0x3f);

  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

class MatchHost {
  final String roomCode;
  final RulesConfig cfg;
  final int seed;
  final RoundOverCallback? onRoundOver;
  final MatchOverCallback? onMatchOver;

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
  int _matchNumber = 0;
  int _spectatorCount = 0;
  bool _started = false;
  bool _disposed = false;
  int _botGeneration = 0;
  String _matchId;
  DateTime _startedAt;

  MatchHost({
    required this.roomCode,
    required this.cfg,
    required this.seed,
    required List<SeatInfo> seats,
    AgentLevel botLevel = AgentLevel.normal,
    this.botDelay = const Duration(milliseconds: 600),
    this.onRoundOver,
    this.onMatchOver,
  }) : _seats = List.of(seats),
       _match = Match(cfg: cfg, seed: seed),
       _matchId = uuidV7(),
       _startedAt = DateTime.now().toUtc() {
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
  int get spectatorCount => _spectatorCount;
  String get matchId => _matchId;

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

      case SpectateRoom():
        _emit(seat, const ServerError(message: 'spectators only watch'));

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
    final RoundResult? result;
    try {
      result = _match.applyId(actionId);
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

    if (result != null) {
      onRoundOver?.call(
        result,
        _match,
        matchId: _matchId,
        startedAt: _startedAt,
      );
      if (_match.matchOver) {
        onMatchOver?.call(_match, matchId: _matchId, startedAt: _startedAt);
      }
    }

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
    _matchNumber++;
    final rematchSeed = seed + 1013 * (_match.roundIndex + 1);
    _match = Match(cfg: cfg, seed: rematchSeed);
    _matchId = uuidV7();
    _startedAt = DateTime.now().toUtc();
    _broadcastTable();
    _scheduleBot();
  }

  // --- bots ------------------------------------------------------------------

  /// Hand the seat to an [Agent] so the table keeps moving without its human.
  void takeOverWithBot(int seat, {AgentLevel level = AgentLevel.normal}) {
    if (_disposed || _agents.containsKey(seat)) return;
    if (!_seats.any((candidate) => candidate.seat == seat)) return;

    _agents[seat] = Agent.forLevel(level, seed: seed + 977 * seat);
    _updateSeat(
      seat,
      (current) => current.copyWith(kind: SeatKind.bot, ready: true),
    );
    _broadcastLobby();
    _scheduleBot();
  }

  /// Give the seat back to its returning human.
  void handBackSeat(int seat) {
    if (_disposed || !_agents.containsKey(seat)) return;

    _agents.remove(seat);
    _botGeneration++;
    _updateSeat(
      seat,
      (current) => current.copyWith(kind: SeatKind.remote, connected: true),
    );
    _broadcastLobby();
    // The host-wide generation bump also invalidates pending moves for every
    // other bot, so they must all be re-armed after this seat changes hands.
    _scheduleBot();
  }

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
      final view = buildTableView(
        _match,
        seat,
        playerNames: _playerNames,
        matchNumber: _matchNumber,
      );
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
      final view = buildTableView(
        _match,
        seat,
        playerNames: _playerNames,
        matchNumber: _matchNumber,
      );
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

  void updateSpectatorCount(int count) {
    if (_disposed || count == _spectatorCount) return;
    _spectatorCount = count;
    _broadcastLobby();
  }

  void _broadcastLobby() => _emit(
    null,
    LobbyUpdate(
      roomCode: roomCode,
      profile: cfg.name,
      numPlayers: cfg.table.numPlayers,
      seats: seats,
      started: _started,
      matchTarget: cfg.scoring.matchTarget,
      spectators: _spectatorCount,
    ),
  );

  void _pushTable(int seat) => _emit(
    seat,
    TableUpdate(
      view: buildTableView(
        _match,
        seat,
        playerNames: _playerNames,
        matchNumber: _matchNumber,
      ),
    ),
  );

  /// MatchHost already owns the engine state, so it constructs one sentinel
  /// view here instead of leaking [Match] through the socket-facing room.
  void pushSpectatorTable() {
    if (_spectatorCount == 0) return;
    _emit(
      spectatorHostSeat,
      TableUpdate(
        view: buildSpectatorView(
          _match,
          playerNames: _playerNames,
          matchNumber: _matchNumber,
        ),
      ),
    );
  }

  void _broadcastTable() {
    for (final s in _seats) {
      _pushTable(s.seat);
    }
    pushSpectatorTable();
  }

  void dispose() {
    _disposed = true;
    _botGeneration++;
    _outbound.close();
  }
}
