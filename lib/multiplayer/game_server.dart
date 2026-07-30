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

import '../engine/profiles.dart';
import 'auth.dart';
import 'match_host.dart';
import 'protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum _ConnState { idle, authorizing, seated }

class _Room {
  final String code;
  final MatchHost host;
  final Map<int, WebSocketChannel> clients = {};
  final Map<int, String> seatOwners = {};
  late final StreamSubscription<HostMessage> _sub;

  _Room({required this.code, required this.host}) {
    _sub = host.outbound.listen((msg) {
      final payload = jsonEncode(msg.event.toJson());
      if (msg.seat == null) {
        for (final c in clients.values) {
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
        final isBot = host.seats.any(
          (candidate) =>
              candidate.seat == seat && candidate.kind == SeatKind.bot,
        );
        if (entry.value == owner && !clients.containsKey(seat) && !isBot) {
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
    await _sub.cancel();
    host.dispose();
    for (final c in clients.values) {
      await c.sink.close();
    }
  }
}

class GameServer {
  final String profileId;
  final int numPlayers;

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

  final Map<String, _Room> _rooms = {};
  var _nextSeed = 1;

  GameServer({
    this.profileId = 'buraco',
    this.numPlayers = 2,
    this.allowedOrigins,
    this.pingInterval = const Duration(seconds: 30),
    this.verifier,
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
          if (cmd is! JoinRoom) {
            channel.sink.add(
              jsonEncode(const ServerError(message: 'still joining').toJson()),
            );
          }
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

          final target = _rooms.putIfAbsent(
            join.roomCode,
            () => _Room(
              code: join.roomCode,
              host: MatchHost(
                roomCode: join.roomCode,
                cfg: loadProfile(profileId, numPlayers: numPlayers),
                seed: _nextSeed++,
                seats: [
                  for (var i = 0; i < numPlayers; i++)
                    SeatInfo(seat: i, name: 'Seat $i', kind: SeatKind.remote),
                ],
              ),
            ),
          );
          final claimed = target.claimSeat(join.preferredSeat, owner: ownerId);
          if (claimed == null) {
            state = _ConnState.idle;
            channel.sink.add(
              jsonEncode(const ServerError(message: 'room is full').toJson()),
            );
            return;
          }
          room = target;
          seat = claimed;
          target.clients[claimed] = channel;
          state = _ConnState.seated;
          stdout.writeln(
            '[${join.roomCode}] ${join.playerName} -> seat $claimed',
          );
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
        final s = seat;
        if (r == null || s == null) return;
        r.clients.remove(s);
        r.host.handle(s, const LeaveRoom());
        stdout.writeln('[${r.code}] seat $s disconnected');
        // A seat's owner entry needs no cleanup of its own: the room dies with
        // its last socket, taking seatOwners with it. Reclaim only ever spans
        // the life of a room that some other seat is still keeping alive;
        // surviving a fully empty room (grace timers) is a later phase.
        if (r.clients.isEmpty) {
          _rooms.remove(r.code);
          await r.close();
          stdout.writeln('[${r.code}] room closed');
        }
      },
    );
  }
}
