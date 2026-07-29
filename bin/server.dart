/// A reference multiplayer host.
///
///     dart run bin/server.dart --port 8080
///
/// Rooms are created on first join and hold a [MatchHost] — the same class the
/// app uses offline, so the rules can never diverge between local and online
/// play. Clients connect to `ws://host:port/ws`, send [JoinRoom] with a room
/// code, and play once every seat has readied up.
///
/// This is deliberately in-memory and unauthenticated: it exists to prove the
/// transport seam end to end and to develop against. Before shipping online
/// play you would add identity, persistence, reconnection tokens and rate
/// limiting — none of which touch the game code, because the host already
/// speaks only [ClientCommand] and [ServerEvent].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:canastra/engine/profiles.dart';
import 'package:canastra/multiplayer/match_host.dart';
import 'package:canastra/multiplayer/protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _Room {
  final String code;
  final MatchHost host;
  final Map<int, WebSocketChannel> clients = {};
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

  /// The first seat that is free, or null when the room is full.
  int? claimSeat(int? preferred) {
    final free = host.seats
        .where((s) => s.kind != SeatKind.bot && !clients.containsKey(s.seat))
        .map((s) => s.seat)
        .toList();
    if (free.isEmpty) return null;
    if (preferred != null && free.contains(preferred)) return preferred;
    return free.first;
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
  final Map<String, _Room> _rooms = {};
  var _nextSeed = 1;

  GameServer({this.profileId = 'buraco', this.numPlayers = 2});

  Handler get handler => webSocketHandler(_onConnection);

  void _onConnection(WebSocketChannel channel, String? _) {
    _Room? room;
    int? seat;

    channel.stream.listen(
      (raw) {
        if (raw is! String) return;
        final ClientCommand cmd;
        try {
          cmd = ClientCommand.fromJson(
              jsonDecode(raw) as Map<String, dynamic>);
        } on FormatException catch (e) {
          channel.sink
              .add(jsonEncode(ServerError(message: '$e').toJson()));
          return;
        }

        if (cmd is JoinRoom) {
          if (room != null) return; // already seated
          // Bound to a local so the nested closure keeps the promoted type.
          final join = cmd;
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
          final claimed = target.claimSeat(cmd.preferredSeat);
          if (claimed == null) {
            channel.sink.add(
                jsonEncode(const ServerError(message: 'room is full').toJson()));
            return;
          }
          room = target;
          seat = claimed;
          target.clients[claimed] = channel;
          stdout.writeln('[${join.roomCode}] ${join.playerName} -> seat $claimed');
          target.host.handle(claimed, join);
          return;
        }

        final r = room;
        final s = seat;
        if (r == null || s == null) {
          channel.sink.add(jsonEncode(
              const ServerError(message: 'join a room first').toJson()));
          return;
        }
        r.host.handle(s, cmd);
      },
      onDone: () async {
        final r = room;
        final s = seat;
        if (r == null || s == null) return;
        r.clients.remove(s);
        r.host.handle(s, const LeaveRoom());
        stdout.writeln('[${r.code}] seat $s disconnected');
        if (r.clients.isEmpty) {
          _rooms.remove(r.code);
          await r.close();
          stdout.writeln('[${r.code}] room closed');
        }
      },
    );
  }
}

Future<void> main(List<String> args) async {
  var port = 8080;
  var profile = 'buraco';
  var players = 2;
  for (var i = 0; i < args.length - 1; i++) {
    switch (args[i]) {
      case '--port':
        port = int.parse(args[i + 1]);
      case '--profile':
        profile = args[i + 1];
      case '--players':
        players = int.parse(args[i + 1]);
    }
  }

  final server = GameServer(profileId: profile, numPlayers: players);
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(server.handler);

  final http = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('canastra host on ws://${http.address.host}:${http.port}/');
  stdout.writeln('profile: $profile, $players players per room');
}
