/// Runs the multiplayer host.
///
///     dart run bin/server.dart --port 8080 --profile buraco --players 2
///
/// Every setting also reads from the environment — `PORT`, `GAME_PROFILE`,
/// `GAME_PLAYERS`, `ALLOWED_ORIGINS` — so the same binary runs unchanged under
/// a container platform that configures processes with env vars and nothing
/// else. Flags win when both are given.
///
/// Matches remain in-memory, while authentication can be required through the
/// Supabase environment settings without changing the multiplayer protocol.
library;

import 'dart:io';

import 'package:canastra/multiplayer/auth.dart';
import 'package:canastra/multiplayer/game_backend.dart';
import 'package:canastra/multiplayer/game_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main(List<String> args) async {
  final env = Platform.environment;
  var port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  var profile = env['GAME_PROFILE'] ?? 'buraco';
  var players = int.tryParse(env['GAME_PLAYERS'] ?? '') ?? 2;
  final authRequired = (env['AUTH_REQUIRED'] ?? '').toLowerCase() == 'true';
  final supabaseUrl = env['SUPABASE_URL']?.trim();
  final primaryServiceKey = env['SUPABASE_SERVICE_KEY']?.trim();
  final fallbackServiceKey = env['SUPABASE_SERVICE_ROLE_KEY']?.trim();
  final serviceKey = primaryServiceKey != null && primaryServiceKey.isNotEmpty
      ? primaryServiceKey
      : fallbackServiceKey;
  final recordingEnabled =
      supabaseUrl != null &&
      supabaseUrl.isNotEmpty &&
      serviceKey != null &&
      serviceKey.isNotEmpty;
  final GameBackend gameBackend = recordingEnabled
      ? SupabaseGameBackend(supabaseUrl: supabaseUrl, serviceKey: serviceKey)
      : const NullBackend();

  TokenVerifier? verifier;
  if (authRequired) {
    final anonKey = env['SUPABASE_ANON_KEY'];
    if (supabaseUrl == null ||
        supabaseUrl.trim().isEmpty ||
        anonKey == null ||
        anonKey.trim().isEmpty) {
      stderr.writeln(
        'AUTH_REQUIRED=true requires SUPABASE_URL and SUPABASE_ANON_KEY',
      );
      exit(1);
    }
    verifier = SupabaseTokenVerifier(
      supabaseUrl: supabaseUrl,
      anonKey: anonKey,
    );
  }
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
    verifier: verifier,
    backend: gameBackend,
  );

  // Hoisted because `handler` builds a fresh handler on every read.
  final playHandler = server.handler;
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(
        (request) => request.url.path == 'health'
            ? Response.ok('ok')
            : playHandler(request),
      );

  final http = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('canastra host on ws://${http.address.host}:${http.port}/');
  stdout.writeln('match recording: ${recordingEnabled ? 'on' : 'off'}');
  stdout.writeln('profile: $profile, $players players per room');
  stdout.writeln(
    origins.isEmpty ? 'origins: any' : 'origins: ${origins.join(', ')}',
  );
}
