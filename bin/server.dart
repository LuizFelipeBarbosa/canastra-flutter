/// Runs the multiplayer host.
///
///     dart run bin/server.dart --port 8080 --profile buraco --players 2
///
/// Every setting also reads from the environment — `PORT`, `GAME_PROFILE`,
/// `GAME_PLAYERS`, `ALLOWED_ORIGINS` — so the same binary runs unchanged under
/// a container platform that configures processes with env vars and nothing
/// else. Flags win when both are given.
///
/// Still in-memory and unauthenticated: a match lives in one process and dies
/// with it. Shipping online play would add identity, reconnection tokens and
/// rate limiting — none of which touch the game code, because [GameServer] only
/// ever speaks ClientCommand and ServerEvent.
library;

import 'dart:io';

import 'package:canastra/multiplayer/game_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main(List<String> args) async {
  final env = Platform.environment;
  var port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  var profile = env['GAME_PROFILE'] ?? 'buraco';
  var players = int.tryParse(env['GAME_PLAYERS'] ?? '') ?? 2;
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

  // Unset or empty means any origin, which is what local development wants.
  final origins = (env['ALLOWED_ORIGINS'] ?? '')
      .split(',')
      .map((o) => o.trim())
      .where((o) => o.isNotEmpty)
      .toList();

  final server = GameServer(
    profileId: profile,
    numPlayers: players,
    allowedOrigins: origins.isEmpty ? null : origins,
  );

  // Hoisted because `handler` builds a fresh handler on every read.
  final playHandler = server.handler;
  final handler = const Pipeline().addMiddleware(logRequests()).addHandler(
    (request) => request.url.path == 'health'
        ? Response.ok('ok')
        : playHandler(request),
  );

  final http = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('canastra host on ws://${http.address.host}:${http.port}/');
  stdout.writeln('profile: $profile, $players players per room');
  stdout.writeln(
    origins.isEmpty ? 'origins: any' : 'origins: ${origins.join(', ')}',
  );
}
