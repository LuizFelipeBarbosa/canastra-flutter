/// Runs the reference multiplayer host.
///
///     dart run bin/server.dart --port 8080 --profile buraco --players 2
///
/// Deliberately in-memory and unauthenticated: it exists to prove the transport
/// seam end to end and to develop against. Shipping online play would add
/// identity, persistence, reconnection tokens and rate limiting — none of which
/// touch the game code, because [GameServer] only ever speaks ClientCommand and
/// ServerEvent.
library;

import 'dart:io';

import 'package:canastra/multiplayer/game_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

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
