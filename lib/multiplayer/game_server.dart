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

import 'auth.dart';
import 'match_host.dart';
import 'protocol.dart';
import 'room_rules.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum _ConnState { idle, authorizing, seated, spectating }

class _Room {
  final String code;
  final MatchHost host;
  final Map<int, WebSocketChannel> clients = {};
  final Set<WebSocketChannel> spectators = {};
  final Map<int, String> seatOwners = {};
  final Map<int, Timer> botTakeover = {};
  Timer? roomGrace;
  late final StreamSubscription<HostMessage> _sub;

  _Room({required this.code, required this.host}) {
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

    final free = host.seats
        .where((s) => s.kind != SeatKind.bot && !clients.containsKey(s.seat))
        .map((s) => s.seat)
        .toList();
    if (free.isEmpty) return null;
    final claimed = preferred != null && free.contains(preferred)
        ? preferred
        : free.first;
    if (owner != null) seatOwners[claimed] = owner;
    return claimed;
  }

  Future<void> close() async {
    roomGrace?.cancel();
    roomGrace = null;
    for (final timer in botTakeover.values) {
      timer.cancel();
    }
    botTakeover.clear();
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
          if (connectionClosed) return;

          final existing = _rooms[join.roomCode];
          late final _Room target;
          if (existing != null) {
            // A later joiner learns the room's immutable rules from its lobby
            // update; its own declaration cannot reconfigure an active room.
            target = existing;
          } else {
            late final RoomRules resolvedRules;
            if (join.profileId != null &&
                join.numPlayers != null &&
                join.matchTarget != null) {
              try {
                resolvedRules = RoomRules.validated(
                  profileId: join.profileId!,
                  numPlayers: join.numPlayers!,
                  matchTarget: join.matchTarget!,
                );
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
            target = _rooms.putIfAbsent(
              join.roomCode,
              () => _Room(
                code: join.roomCode,
                host: MatchHost(
                  roomCode: join.roomCode,
                  cfg: resolvedRules.toConfig(),
                  seed: _nextSeed++,
                  seats: [
                    for (var i = 0; i < resolvedRules.numPlayers; i++)
                      SeatInfo(seat: i, name: 'Seat $i', kind: SeatKind.remote),
                  ],
                ),
              ),
            );
          }
          final claimed = target.claimSeat(join.preferredSeat, owner: ownerId);
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
        r.host.handle(s, const LeaveRoom());
        stdout.writeln('[${r.code}] seat $s disconnected');
        r.botTakeover.remove(s)?.cancel();
        final takeoverDelay = botTakeoverAfter;
        if (takeoverDelay != null && r.host.started) {
          r.botTakeover[s] = Timer(takeoverDelay, () {
            r.botTakeover.remove(s);
            if (!r.clients.containsKey(s)) r.host.takeOverWithBot(s);
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

  Future<void> _closeRoom(_Room room) async {
    _spectatorCount -= room.spectators.length;
    assert(_spectatorCount >= 0);
    await room.close();
  }
}
