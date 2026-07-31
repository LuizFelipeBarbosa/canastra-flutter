/// A reference multiplayer host.
///
/// Lives in `lib/` rather than `bin/` so the integration test can start it
/// in-process and drive it through the real [WebSocketTransport]; `bin/server
/// .dart` is just a `main` around it.
///
/// Rooms are created on first join and hold a [MatchHost] — the same class the
/// app uses offline, so the rules can never diverge between local and online
/// play. Clients connect to `ws://host:port/ws`, send [JoinRoom] with a room
/// code, and play once every seat has readied up.
///
/// This is deliberately in-memory and open by default so local development
/// stays frictionless. A production host can require Supabase identity without
/// changing the game code, because the host still speaks only [ClientCommand]
/// and [ServerEvent].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../engine/match.dart';
import 'auth.dart';
import 'game_backend.dart';
import 'match_host.dart';
import 'protocol.dart';
import 'room_rules.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum _ConnState { idle, authorizing, seated, spectating }

class _MatchRecorder {
  final GameBackend backend;
  final String roomCode;
  final String? roomId;
  final String? ladderId;
  final bool isRanked;
  final bool authenticatedOwners;

  final List<Map<String, dynamic>> _rounds = [];
  final Map<int, int> _disconnects = {};
  final Set<int> _replacedByBot = {};
  final Set<String> _submittedMatchIds = {};
  String? _activeMatchId;
  bool _recorded = false;
  bool _disposed = false;

  _MatchRecorder({
    required this.backend,
    required this.roomCode,
    required this.roomId,
    required this.ladderId,
    required this.isRanked,
    required this.authenticatedOwners,
  });

  void recordRound(RoundResult result, {required String matchId}) {
    if (_disposed) return;
    _selectMatch(matchId);
    final sheet = {
      'roundIndex': result.roundIndex,
      'reason': result.reason.name,
      'wentOutSide': result.wentOutSide,
      'sheets': [
        for (final sideScore in result.sheet)
          {
            'side': sideScore.side,
            'lines': [
              for (final line in sideScore.lines)
                {'label': line.label, 'points': line.points},
            ],
            'total': sideScore.total,
          },
      ],
      'matchScores': List<int>.of(result.matchScoresAfter),
    };
    _rounds.add({
      'round_index': result.roundIndex,
      'reason': result.reason.name,
      'went_out_side': result.wentOutSide,
      'sheet': sheet,
      'match_scores_after': List<int>.of(result.matchScoresAfter),
    });
  }

  void recordDisconnect(int seat, {required String matchId}) {
    if (_disposed) return;
    _selectMatch(matchId);
    _disconnects[seat] = (_disconnects[seat] ?? 0) + 1;
  }

  void recordBotReplacement(int seat, {required String matchId}) {
    if (_disposed) return;
    _selectMatch(matchId);
    _replacedByBot.add(seat);
  }

  void recordMatch(
    Match match, {
    required String matchId,
    required DateTime startedAt,
    required List<SeatInfo> seats,
    required Map<int, String> seatOwners,
  }) {
    if (_disposed) return;
    _selectMatch(matchId);
    if (_recorded) return;
    _recorded = true;

    final finalScores = List<int>.of(match.matchScores);
    var winnerSide = match.winnerSide;
    if (finalScores.length > 1) {
      final ordered = List<int>.of(finalScores)..sort((a, b) => b.compareTo(a));
      // winnerSide picks the first maximum, but both sides can cross the
      // target in one round. A tied match has no database winner.
      if (ordered[0] == ordered[1]) winnerSide = null;
    }

    final payload = <String, dynamic>{
      'match_id': matchId,
      'room_id': roomId,
      'room_code': roomCode,
      'ladder_id': ladderId,
      'profile': match.cfg.name,
      'num_players': match.cfg.table.numPlayers,
      'num_sides': match.cfg.table.numSides,
      'match_target': match.cfg.scoring.matchTarget,
      'seed': match.seed,
      'is_ranked': isRanked,
      'host_instance': Platform.environment['FLY_MACHINE_ID'],
      'started_at': startedAt.toUtc().toIso8601String(),
      'ended_at': DateTime.now().toUtc().toIso8601String(),
      'winner_side': winnerSide,
      'final_scores': finalScores,
      'sides': [
        for (var side = 0; side < finalScores.length; side++)
          {'side': side, 'score_final': finalScores[side]},
      ],
      'players': [
        for (final seat in seats)
          {
            'seat': seat.seat,
            'side': match.cfg.table.side(seat.seat),
            'user_id': authenticatedOwners && seat.kind != SeatKind.bot
                ? seatOwners[seat.seat]
                : null,
            'is_bot': seat.kind == SeatKind.bot,
            'bot_level': seat.kind == SeatKind.bot ? 'normal' : null,
            'display_name': seat.name,
            'disconnects': _disconnects[seat.seat] ?? 0,
            'replaced_by_bot': _replacedByBot.contains(seat.seat),
          },
      ],
      'rounds': List<Map<String, dynamic>>.of(_rounds),
    };
    _submittedMatchIds.add(matchId);
    unawaited(
      backend.recordMatchResult(payload).whenComplete(() {
        _submittedMatchIds.remove(matchId);
      }),
    );
  }

  void _selectMatch(String matchId) {
    if (_activeMatchId == matchId) return;
    _activeMatchId = matchId;
    _rounds.clear();
    _disconnects.clear();
    _replacedByBot.clear();
    _recorded = false;
  }

  void dispose() {
    _disposed = true;
    final gameBackend = backend;
    if (gameBackend is SupabaseGameBackend) {
      for (final matchId in _submittedMatchIds) {
        gameBackend.cancelPendingMatchResult(matchId);
      }
    }
    _submittedMatchIds.clear();
    _rounds.clear();
    _disconnects.clear();
    _replacedByBot.clear();
  }
}

class _Room {
  final String code;
  final MatchHost host;
  final _MatchRecorder recorder;
  final Map<int, WebSocketChannel> clients = {};
  final Set<WebSocketChannel> spectators = {};
  final Map<int, String> seatOwners = {};
  final Map<int, Timer> botTakeover = {};
  Timer? roomGrace;
  late final StreamSubscription<HostMessage> _sub;

  bool _closed = false;

  _Room({required this.code, required this.host, required this.recorder}) {
    _sub = host.outbound.listen((msg) {
      final payload = jsonEncode(msg.event.toJson());
      if (msg.seat == null) {
        for (final c in clients.values) {
          c.sink.add(payload);
        }
        for (final c in spectators) {
          c.sink.add(payload);
        }
      } else if (msg.seat == spectatorHostSeat) {
        for (final c in spectators) {
          c.sink.add(payload);
        }
      } else {
        clients[msg.seat]?.sink.add(payload);
      }
    });
  }

  /// Reclaims an owned chair first, otherwise picks the first free seat.
  int? claimSeat(int? preferred, {String? owner}) {
    if (owner != null) {
      for (final entry in seatOwners.entries) {
        final seat = entry.key;
        if (entry.value == owner && !clients.containsKey(seat)) {
          return seat;
        }
      }
    }

    // Once play has started, a disconnected owner's chair stays reserved for
    // them: handing it to anyone else would also hand them the owner's cards.
    // (An owner match never reaches this list — the reclaim loop returns it.)
    final free = host.seats
        .where(
          (s) =>
              s.kind != SeatKind.bot &&
              !clients.containsKey(s.seat) &&
              !(host.started && seatOwners.containsKey(s.seat)),
        )
        .map((s) => s.seat)
        .toList();
    if (free.isEmpty) return null;
    final claimed = preferred != null && free.contains(preferred)
        ? preferred
        : free.first;
    if (owner != null) {
      seatOwners[claimed] = owner;
    } else {
      // An anonymous claimant must not inherit a stale owner, or that owner
      // could later "reclaim" the seat and read the new occupant's hand.
      seatOwners.remove(claimed);
    }
    return claimed;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    roomGrace?.cancel();
    roomGrace = null;
    for (final timer in botTakeover.values) {
      timer.cancel();
    }
    botTakeover.clear();
    recorder.dispose();
    final spectatorSockets = spectators.toList();
    spectators.clear();
    await _sub.cancel();
    host.dispose();
    for (final c in clients.values) {
      await c.sink.close();
    }
    for (final c in spectatorSockets) {
      await c.sink.close();
    }
  }
}

class GameServer {
  static const int _maxSpectatorsPerRoom = 8;
  static const int _maxSpectatorsTotal = 64;

  final String profileId;
  final int numPlayers;

  /// Match target used when a first joiner does not declare complete rules.
  final int defaultMatchTarget;

  /// When set, every join must carry a token this verifier accepts.
  ///
  /// Null preserves the open behavior used by local development and tests.
  final TokenVerifier? verifier;

  /// Database admission and result recording. The no-op default preserves the
  /// open, in-memory server used by local development.
  final GameBackend backend;

  /// Browser origins allowed to open a socket, or null to accept any.
  ///
  /// Null suits local development and the tests. A deployed host should pin
  /// this to the site that serves the app, because otherwise any page on the
  /// internet can open rooms against it.
  final List<String>? allowedOrigins;

  /// How often to ping an idle client.
  ///
  /// Proxies drop connections that go quiet, and a player thinking over a hand
  /// is quiet for minutes, so this both keeps the socket open and surfaces a
  /// peer that vanished without sending a close frame.
  final Duration? pingInterval;

  /// How long a dropped seat keeps its chair before a bot takes it over.
  ///
  /// Null disables takeover.
  final Duration? botTakeoverAfter;

  /// How long an empty room survives awaiting reconnects before disposal.
  ///
  /// Null reverts to close-on-empty behavior.
  final Duration? roomGraceAfter;

  final Map<String, _Room> _rooms = {};
  var _spectatorCount = 0;
  var _nextSeed = 1;

  GameServer({
    this.profileId = 'buraco',
    this.numPlayers = 2,
    this.defaultMatchTarget = 3000,
    this.allowedOrigins,
    this.pingInterval = const Duration(seconds: 30),
    this.verifier,
    this.backend = const NullBackend(),
    this.botTakeoverAfter = const Duration(seconds: 45),
    this.roomGraceAfter = const Duration(minutes: 10),
  });

  Handler get handler => webSocketHandler(
    _onConnection,
    allowedOrigins: allowedOrigins,
    pingInterval: pingInterval,
  );

  void _onConnection(WebSocketChannel channel, String? _) {
    _Room? room;
    int? seat;
    String? ownerId;
    var state = _ConnState.idle;
    var connectionClosed = false;

    channel.stream.listen(
      (raw) async {
        if (raw is! String) return;
        final ClientCommand cmd;
        try {
          cmd = ClientCommand.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        } on FormatException catch (e) {
          channel.sink.add(jsonEncode(ServerError(message: '$e').toJson()));
          return;
        }

        if (state == _ConnState.authorizing) {
          if (cmd is! JoinRoom && cmd is! SpectateRoom) {
            channel.sink.add(
              jsonEncode(const ServerError(message: 'still joining').toJson()),
            );
          }
          return;
        }

        if (state == _ConnState.spectating) {
          if (cmd is LeaveRoom) {
            await channel.sink.close();
          } else {
            channel.sink.add(
              jsonEncode(
                const ServerError(message: 'spectators only watch').toJson(),
              ),
            );
          }
          return;
        }

        if (cmd is SpectateRoom) {
          if (state == _ConnState.seated) return;
          state = _ConnState.authorizing;
          final spectate = cmd;
          final tokenVerifier = verifier;
          String? verifiedUserId;
          if (tokenVerifier != null) {
            final token = spectate.authToken;
            if (token == null) {
              channel.sink.add(
                jsonEncode(
                  const ServerError(message: 'sign in to play').toJson(),
                ),
              );
              await channel.sink.close();
              return;
            }
            final user = await tokenVerifier.verify(token);
            if (user == null) {
              channel.sink.add(
                jsonEncode(
                  const ServerError(message: 'session rejected').toJson(),
                ),
              );
              await channel.sink.close();
              return;
            }
            verifiedUserId = user.id;
          }
          final gameBackend = backend;
          if (verifiedUserId != null && gameBackend is! NullBackend) {
            final authorization = await gameBackend.authorizeJoin(
              roomCode: spectate.roomCode,
              userId: verifiedUserId,
              spectator: true,
            );
            if (connectionClosed) return;
            if (authorization == null) {
              // Admission bookkeeping must not take the live game down. During
              // a backend outage, favor availability and keep open seating.
              stderr.writeln(
                '[${spectate.roomCode}] room authorization unavailable; '
                'allowing spectator',
              );
            } else if (authorization['ok'] != true) {
              final reason = authorization['reason'];
              channel.sink.add(
                jsonEncode(
                  ServerError(
                    message: reason is String ? reason : 'room join refused',
                  ).toJson(),
                ),
              );
              await channel.sink.close();
              return;
            }
          }
          if (connectionClosed) return;

          final target = _rooms[spectate.roomCode];
          if (target == null) {
            state = _ConnState.idle;
            channel.sink.add(
              jsonEncode(const ServerError(message: 'no such table').toJson()),
            );
            return;
          }
          if (target.spectators.length >= _maxSpectatorsPerRoom ||
              _spectatorCount >= _maxSpectatorsTotal) {
            state = _ConnState.idle;
            channel.sink.add(
              jsonEncode(
                const ServerError(message: 'the gallery is full').toJson(),
              ),
            );
            return;
          }

          room = target;
          target.spectators.add(channel);
          _spectatorCount++;
          state = _ConnState.spectating;
          channel.sink.add(
            jsonEncode(
              Joined(roomCode: target.code, seat: -1, spectator: true).toJson(),
            ),
          );
          target.host.updateSpectatorCount(target.spectators.length);
          if (target.host.started) target.host.pushSpectatorTable();
          stdout.writeln('[${target.code}] spectator joined');
          return;
        }

        if (cmd is JoinRoom) {
          if (state == _ConnState.seated) return;
          // Set before the first await so a burst of joins can claim only once.
          state = _ConnState.authorizing;
          // Bound to a local so the nested closure keeps the promoted type.
          final join = cmd;
          final tokenVerifier = verifier;
          Map<String, dynamic>? authorization;
          if (tokenVerifier != null) {
            final token = join.authToken;
            if (token == null) {
              channel.sink.add(
                jsonEncode(
                  const ServerError(message: 'sign in to play').toJson(),
                ),
              );
              await channel.sink.close();
              return;
            }
            final user = await tokenVerifier.verify(token);
            if (user == null) {
              channel.sink.add(
                jsonEncode(
                  const ServerError(message: 'session rejected').toJson(),
                ),
              );
              await channel.sink.close();
              return;
            }
            ownerId = user.id;
          } else {
            ownerId = join.clientId;
          }
          final gameBackend = backend;
          if (tokenVerifier != null && gameBackend is! NullBackend) {
            authorization = await gameBackend.authorizeJoin(
              roomCode: join.roomCode,
              userId: ownerId!,
            );
            if (connectionClosed) return;
            if (authorization == null) {
              // A database outage must not make an otherwise healthy table
              // unavailable. The room stays unranked and seating stays open.
              stderr.writeln(
                '[${join.roomCode}] room authorization unavailable; '
                'allowing open seating',
              );
            } else if (authorization['ok'] != true) {
              final reason = authorization['reason'];
              channel.sink.add(
                jsonEncode(
                  ServerError(
                    message: reason is String ? reason : 'room join refused',
                  ).toJson(),
                ),
              );
              await channel.sink.close();
              return;
            }
          }
          if (connectionClosed) return;

          final existing = _rooms[join.roomCode];
          late final _Room target;
          if (existing != null) {
            // A later joiner learns the room's immutable rules from its lobby
            // update; its own declaration cannot reconfigure an active room.
            target = existing;
          } else {
            late final RoomRules resolvedRules;
            try {
              if (authorization != null) {
                final rules = authorization['rules'];
                if (rules is! Map<String, dynamic> ||
                    rules['profile'] is! String ||
                    rules['num_players'] is! int ||
                    rules['match_target'] is! int) {
                  throw const FormatException('invalid authorized room rules');
                }
                resolvedRules = RoomRules.validated(
                  profileId: rules['profile'] as String,
                  numPlayers: rules['num_players'] as int,
                  matchTarget: rules['match_target'] as int,
                );
              } else if (join.profileId != null &&
                  join.numPlayers != null &&
                  join.matchTarget != null) {
                resolvedRules = RoomRules.validated(
                  profileId: join.profileId!,
                  numPlayers: join.numPlayers!,
                  matchTarget: join.matchTarget!,
                );
              } else {
                // Partial declarations deliberately count as absent. Guessing
                // their missing fields from server defaults would recreate the
                // client/server mismatch this declaration exists to prevent.
                resolvedRules = RoomRules(
                  profileId: profileId,
                  numPlayers: numPlayers,
                  matchTarget: defaultMatchTarget,
                );
              }
            } on FormatException {
              channel.sink.add(
                jsonEncode(
                  const ServerError(
                    message: "that table's rules are not offered here",
                  ).toJson(),
                ),
              );
              await channel.sink.close();
              return;
            }
            target = _rooms.putIfAbsent(
              join.roomCode,
              () => _createRoom(join.roomCode, resolvedRules, authorization),
            );
          }
          final authorizedSeat = authorization?['seat'];
          final preferredSeat = authorizedSeat is int
              ? authorizedSeat
              : join.preferredSeat;
          final claimed = target.claimSeat(preferredSeat, owner: ownerId);
          if (claimed == null) {
            state = _ConnState.idle;
            channel.sink.add(
              jsonEncode(const ServerError(message: 'room is full').toJson()),
            );
            return;
          }
          target.roomGrace?.cancel();
          target.roomGrace = null;
          target.botTakeover.remove(claimed)?.cancel();
          final reclaimingBot = target.host.seats.any(
            (candidate) =>
                candidate.seat == claimed && candidate.kind == SeatKind.bot,
          );
          room = target;
          seat = claimed;
          target.clients[claimed] = channel;
          state = _ConnState.seated;
          stdout.writeln(
            '[${join.roomCode}] ${join.playerName} -> seat $claimed',
          );
          if (reclaimingBot) target.host.handBackSeat(claimed);
          target.host.handle(claimed, join);
          return;
        }

        final r = room;
        final s = seat;
        if (r == null || s == null) {
          channel.sink.add(
            jsonEncode(
              const ServerError(message: 'join a room first').toJson(),
            ),
          );
          return;
        }
        r.host.handle(s, cmd);
      },
      onDone: () async {
        connectionClosed = true;
        final r = room;
        if (r == null) return;

        if (state == _ConnState.spectating) {
          if (r.spectators.remove(channel)) {
            _spectatorCount--;
            r.host.updateSpectatorCount(r.spectators.length);
            stdout.writeln('[${r.code}] spectator disconnected');
          }
          return;
        }

        final s = seat;
        if (s == null) return;
        r.clients.remove(s);
        r.recorder.recordDisconnect(s, matchId: r.host.matchId);
        r.host.handle(s, const LeaveRoom());
        stdout.writeln('[${r.code}] seat $s disconnected');
        r.botTakeover.remove(s)?.cancel();
        final takeoverDelay = botTakeoverAfter;
        if (takeoverDelay != null && r.host.started) {
          r.botTakeover[s] = Timer(takeoverDelay, () {
            r.botTakeover.remove(s);
            if (!r.clients.containsKey(s)) {
              r.host.takeOverWithBot(s);
              r.recorder.recordBotReplacement(s, matchId: r.host.matchId);
            }
          });
        }

        if (r.clients.isEmpty) {
          final graceDelay = roomGraceAfter;
          if (graceDelay == null) {
            _rooms.remove(r.code);
            await _closeRoom(r);
            stdout.writeln('[${r.code}] room closed');
          } else {
            r.roomGrace?.cancel();
            r.roomGrace = Timer(graceDelay, () {
              r.roomGrace = null;
              // Watchers never pin a dead table in memory: only occupied
              // player seats decide whether the room is still alive.
              if (r.clients.isNotEmpty || !identical(_rooms[r.code], r)) {
                return;
              }
              _rooms.remove(r.code);
              unawaited(_closeRoom(r));
              stdout.writeln('[${r.code}] room closed after grace');
            });
          }
        }
      },
    );
  }

  _Room _createRoom(
    String code,
    RoomRules rules,
    Map<String, dynamic>? authorization,
  ) {
    final rawRoomId = authorization?['room_id'];
    final rawLadderId = authorization?['ladder_id'];
    final recorder = _MatchRecorder(
      backend: backend,
      roomCode: code,
      roomId: rawRoomId is String ? rawRoomId : null,
      ladderId: rawLadderId is String ? rawLadderId : null,
      isRanked: authorization?['is_ranked'] == true,
      authenticatedOwners: verifier != null,
    );
    late final _Room room;
    final host = MatchHost(
      roomCode: code,
      cfg: rules.toConfig(),
      seed: _nextSeed++,
      seats: [
        for (var i = 0; i < rules.numPlayers; i++)
          SeatInfo(seat: i, name: 'Seat $i', kind: SeatKind.remote),
      ],
      onRoundOver: (result, match, {required matchId, required startedAt}) {
        recorder.recordRound(result, matchId: matchId);
      },
      onMatchOver: (match, {required matchId, required startedAt}) {
        recorder.recordMatch(
          match,
          matchId: matchId,
          startedAt: startedAt,
          seats: room.host.seats,
          seatOwners: room.seatOwners,
        );
      },
    );
    room = _Room(code: code, host: host, recorder: recorder);
    return room;
  }

  Future<void> _closeRoom(_Room room) async {
    if (room._closed) return;
    _spectatorCount -= room.spectators.length;
    assert(_spectatorCount >= 0);
    await room.close();
  }

  /// Close every room and release resources owned by the configured backend.
  Future<void> dispose() async {
    final rooms = _rooms.values.toList();
    _rooms.clear();
    for (final room in rooms) {
      await _closeRoom(room);
    }
    await backend.dispose();
  }
}
