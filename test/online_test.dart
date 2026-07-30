/// End-to-end test of online play.
///
/// Starts the real [GameServer] on a real socket and drives it with two real
/// [WebSocketTransport] clients — the same objects the app uses. This is what
/// makes "the multiplayer scaffolding works" a checked claim rather than an
/// assertion: JSON framing, seat assignment, turn enforcement and hidden-
/// information redaction all have to hold across a genuine network hop.
@Tags(['online'])
library;

import 'dart:io';

import 'package:canastra/multiplayer/auth.dart';
import 'package:canastra/multiplayer/game_server.dart';
import 'package:canastra/multiplayer/protocol.dart';
import 'package:canastra/multiplayer/table_view.dart';
import 'package:canastra/multiplayer/websocket_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Collects a client's events and lets a test await the next one it cares about.
class _Client {
  final WebSocketTransport transport;
  final List<ServerEvent> events = [];

  _Client(this.transport) {
    transport.events.listen(events.add);
  }

  TableView? get table => events.whereType<TableUpdate>().isEmpty
      ? null
      : events.whereType<TableUpdate>().last.view;

  /// Waits until [test] holds of the latest table view, or times out.
  Future<TableView> waitForTable(
    bool Function(TableView) test, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final view = table;
      if (view != null && test(view)) return view;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    throw StateError('timed out; last view: ${table?.toJson()}');
  }
}

class _StubVerifier implements TokenVerifier {
  @override
  Future<AuthedUser?> verify(String token) async => token == 'good-token'
      ? const AuthedUser(
          id: 'verified-user',
          email: 'player@example.com',
          isAnonymous: false,
        )
      : null;
}

Future<({HttpServer http, Uri endpoint})> _serveServer(
  GameServer server,
) async {
  final http = await shelf_io.serve(
    server.handler,
    InternetAddress.loopbackIPv4,
    0,
  );
  return (
    http: http,
    endpoint: Uri.parse('ws://${http.address.host}:${http.port}'),
  );
}

Future<T> _nextEvent<T extends ServerEvent>(_Client client) => client
    .transport
    .events
    .where((event) => event is T)
    .cast<T>()
    .first
    .timeout(const Duration(seconds: 5));

void main() {
  late HttpServer http;
  late Uri endpoint;
  late int connectionRequests;

  setUp(() async {
    final server = GameServer(profileId: 'buraco', numPlayers: 2);
    connectionRequests = 0;
    http = await shelf_io.serve(
      const Pipeline()
          .addMiddleware(
            createMiddleware(
              requestHandler: (_) {
                connectionRequests++;
                return null;
              },
            ),
          )
          .addHandler(server.handler),
      InternetAddress.loopbackIPv4,
      0, // any free port
    );
    endpoint = Uri.parse('ws://${http.address.host}:${http.port}');
  });

  tearDown(() => http.close(force: true));

  test('overlapping connect calls open only one WebSocket', () async {
    final client = _Client(
      WebSocketTransport(
        endpoint: endpoint,
        roomCode: 'mesa-overlap',
        playerName: 'Ana',
      ),
    );
    addTearDown(client.transport.dispose);
    final joined = client.transport.events
        .firstWhere((event) => event is Joined)
        .timeout(const Duration(seconds: 5));

    final first = client.transport.connect();
    final second = client.transport.connect();
    await Future.wait([first, second]);

    expect((await joined as Joined).seat, equals(0));
    expect(connectionRequests, equals(1));
    expect(client.events.whereType<Joined>(), hasLength(1));
  });

  test('two clients join a room and play a turn', () async {
    final a = _Client(
      WebSocketTransport(
        endpoint: endpoint,
        roomCode: 'mesa-1',
        playerName: 'Ana',
      ),
    );
    final b = _Client(
      WebSocketTransport(
        endpoint: endpoint,
        roomCode: 'mesa-1',
        playerName: 'Bruno',
      ),
    );
    addTearDown(a.transport.dispose);
    addTearDown(b.transport.dispose);

    await a.transport.connect();
    await b.transport.connect();

    // The host seats them, one each.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(a.transport.seat, equals(0));
    expect(b.transport.seat, equals(1));

    // Nothing is dealt until both say they are ready.
    expect(a.table, isNull);
    a.transport.send(const SetReady(ready: true));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(a.table, isNull, reason: 'one player ready is not enough');

    b.transport.send(const SetReady(ready: true));
    final dealt = await a.waitForTable((v) => v.hand.isNotEmpty);

    expect(dealt.seat, equals(0));
    expect(dealt.hand, hasLength(11));
    expect(dealt.myTurn, isTrue);

    // Seat 1 got its own hand and was told nothing about seat 0's moves.
    final other = await b.waitForTable((v) => v.hand.isNotEmpty);
    expect(other.seat, equals(1));
    expect(other.legalActions, isEmpty, reason: 'it is not seat 1 to act');
    expect(other.hand, isNot(equals(dealt.hand)));

    // Seat 1 cannot move out of turn.
    b.transport.send(const SubmitAction(actionId: 0));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(
      b.events.whereType<ActionRejected>().map((e) => e.reason),
      contains('it is not your turn'),
    );

    // Seat 0 draws, and both clients see the result.
    a.transport.send(const SubmitAction(actionId: 0)); // DRAW_DECK
    final afterDraw = await a.waitForTable((v) => v.phase == 'play');
    expect(afterDraw.hand, hasLength(12));
    await b.waitForTable((v) => v.stockCount == afterDraw.stockCount);
  });

  test('a third player is turned away from a full room', () async {
    final clients = [
      for (final name in ['Ana', 'Bruno', 'Carla'])
        _Client(
          WebSocketTransport(
            endpoint: endpoint,
            roomCode: 'mesa-2',
            playerName: name,
          ),
        ),
    ];
    for (final c in clients) {
      addTearDown(c.transport.dispose);
      await c.transport.connect();
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(clients[0].transport.seat, equals(0));
    expect(clients[1].transport.seat, equals(1));
    expect(clients[2].transport.seat, isNull);
    expect(
      clients[2].events.whereType<ServerError>().map((e) => e.message),
      contains('room is full'),
    );
  });

  group('optional join authentication', () {
    test('a protected server rejects a missing token', () async {
      final hosted = await _serveServer(
        GameServer(numPlayers: 2, verifier: _StubVerifier()),
      );
      addTearDown(() => hosted.http.close(force: true));
      final client = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'auth-missing',
          playerName: 'Ana',
          maxRetries: 0,
        ),
      );
      addTearDown(client.transport.dispose);
      final error = _nextEvent<ServerError>(client);

      await client.transport.connect();

      expect((await error).message, equals('sign in to play'));
      expect(client.transport.seat, isNull);
      expect(client.events.whereType<Joined>(), isEmpty);
    });

    test('a protected server rejects a bad token', () async {
      final hosted = await _serveServer(
        GameServer(numPlayers: 2, verifier: _StubVerifier()),
      );
      addTearDown(() => hosted.http.close(force: true));
      final client = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'auth-bad',
          playerName: 'Ana',
          authToken: () async => 'bad-token',
          maxRetries: 0,
        ),
      );
      addTearDown(client.transport.dispose);
      final error = _nextEvent<ServerError>(client);

      await client.transport.connect();

      expect((await error).message, equals('session rejected'));
      expect(client.transport.seat, isNull);
      expect(client.events.whereType<Joined>(), isEmpty);
    });

    test('a protected server seats a verified client', () async {
      final hosted = await _serveServer(
        GameServer(numPlayers: 2, verifier: _StubVerifier()),
      );
      addTearDown(() => hosted.http.close(force: true));
      final client = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'auth-good',
          playerName: 'Ana',
          authToken: () async => 'good-token',
        ),
      );
      addTearDown(client.transport.dispose);
      final joined = _nextEvent<Joined>(client);
      final lobby = _nextEvent<LobbyUpdate>(client);

      await client.transport.connect();

      expect((await joined).seat, equals(0));
      expect((await lobby).roomCode, equals('auth-good'));
      expect(client.transport.seat, equals(0));
    });

    test('an open server still accepts a tokenless client', () async {
      final hosted = await _serveServer(GameServer());
      addTearDown(() => hosted.http.close(force: true));
      final client = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'auth-off',
          playerName: 'Ana',
        ),
      );
      addTearDown(client.transport.dispose);
      final joined = _nextEvent<Joined>(client);

      await client.transport.connect();

      expect((await joined).seat, equals(0));
      expect(client.transport.seat, equals(0));
    });

    test(
      'a client id reclaims its seat while the room is still alive',
      () async {
        // A room dies with its last socket, so the reclaim below only works
        // because Bia's connection keeps this room alive the whole time — Ana
        // never sees an empty room, only her own dropped seat.
        final hosted = await _serveServer(GameServer(numPlayers: 2));
        addTearDown(() => hosted.http.close(force: true));
        final ana = _Client(
          WebSocketTransport(
            endpoint: hosted.endpoint,
            roomCode: 'reconnect',
            playerName: 'Ana',
            clientId: 'ana',
          ),
        );
        addTearDown(ana.transport.dispose);
        final anaJoined = _nextEvent<Joined>(ana);
        await ana.transport.connect();
        expect((await anaJoined).seat, equals(0));

        final bia = _Client(
          WebSocketTransport(
            endpoint: hosted.endpoint,
            roomCode: 'reconnect',
            playerName: 'Bia',
            clientId: 'bia',
          ),
        );
        addTearDown(bia.transport.dispose);
        final biaJoined = _nextEvent<Joined>(bia);
        await bia.transport.connect();
        expect((await biaJoined).seat, equals(1));

        // Ana drops; Bia stays connected, so the room never empties.
        await ana.transport.dispose();

        final anaAgain = _Client(
          WebSocketTransport(
            endpoint: hosted.endpoint,
            roomCode: 'reconnect',
            playerName: 'Ana',
            clientId: 'ana',
          ),
        );
        addTearDown(anaAgain.transport.dispose);
        final rejoined = _nextEvent<Joined>(anaAgain);
        await anaAgain.transport.connect();

        expect((await rejoined).seat, equals(0));
        expect(anaAgain.transport.seat, equals(0));
      },
    );
  });

  group('per-room rules', () {
    test('the first joiner defines rules that every client receives', () async {
      final hosted = await _serveServer(GameServer());
      addTearDown(() => hosted.http.close(force: true));
      final first = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'rules-first',
          playerName: 'Ana',
          profileId: 'canasta',
          numPlayers: 4,
          matchTarget: 1500,
        ),
      );
      addTearDown(first.transport.dispose);
      final firstLobby = _nextEvent<LobbyUpdate>(first);

      await first.transport.connect();

      final created = await firstLobby;
      expect(created.profile, equals('canasta'));
      expect(created.numPlayers, equals(4));
      expect(created.matchTarget, equals(1500));

      final second = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'rules-first',
          playerName: 'Bruno',
        ),
      );
      addTearDown(second.transport.dispose);
      final firstSawSecondJoin = _nextEvent<LobbyUpdate>(first);
      final secondLobby = _nextEvent<LobbyUpdate>(second);

      await second.transport.connect();

      final updates = await Future.wait([firstSawSecondJoin, secondLobby]);
      for (final update in updates) {
        expect(update.profile, equals('canasta'));
        expect(update.numPlayers, equals(4));
        expect(update.matchTarget, equals(1500));
      }
      for (final update in [
        ...first.events.whereType<LobbyUpdate>(),
        ...second.events.whereType<LobbyUpdate>(),
      ]) {
        expect(update.profile, equals('canasta'));
        expect(update.numPlayers, equals(4));
        expect(update.matchTarget, equals(1500));
      }
    });

    test('a later declaration cannot reconfigure an existing room', () async {
      final hosted = await _serveServer(GameServer());
      addTearDown(() => hosted.http.close(force: true));
      final first = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'rules-existing',
          playerName: 'Ana',
          profileId: 'canasta',
          numPlayers: 4,
          matchTarget: 1500,
        ),
      );
      addTearDown(first.transport.dispose);
      final created = _nextEvent<LobbyUpdate>(first);
      await first.transport.connect();
      await created;

      final later = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'rules-existing',
          playerName: 'Bruno',
          profileId: 'rummy',
          numPlayers: 2,
          matchTarget: 2000,
        ),
      );
      addTearDown(later.transport.dispose);
      final firstUpdate = _nextEvent<LobbyUpdate>(first);
      final laterLobby = _nextEvent<LobbyUpdate>(later);

      await later.transport.connect();

      for (final update in await Future.wait([firstUpdate, laterLobby])) {
        expect(update.profile, equals('canasta'));
        expect(update.numPlayers, equals(4));
        expect(update.matchTarget, equals(1500));
      }
      expect(later.transport.seat, equals(1));
    });

    test('an invalid declaration leaves no room behind', () async {
      final hosted = await _serveServer(GameServer());
      addTearDown(() => hosted.http.close(force: true));
      final invalid = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'rules-invalid',
          playerName: 'Ana',
          profileId: 'poker',
          numPlayers: 2,
          matchTarget: 1500,
          maxRetries: 0,
        ),
      );
      addTearDown(invalid.transport.dispose);
      final error = _nextEvent<ServerError>(invalid);

      await invalid.transport.connect();

      expect(
        (await error).message,
        equals("that table's rules are not offered here"),
      );
      expect(invalid.transport.seat, isNull);
      expect(invalid.events.whereType<Joined>(), isEmpty);

      final valid = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'rules-invalid',
          playerName: 'Bruno',
          profileId: 'rummy',
          numPlayers: 2,
          matchTarget: 2000,
        ),
      );
      addTearDown(valid.transport.dispose);
      final lobby = _nextEvent<LobbyUpdate>(valid);

      await valid.transport.connect();

      final created = await lobby;
      expect(created.profile, equals('rummy'));
      expect(created.numPlayers, equals(2));
      expect(created.matchTarget, equals(2000));
    });

    test('an absent declaration preserves server defaults', () async {
      final hosted = await _serveServer(
        GameServer(
          profileId: 'biriba',
          numPlayers: 4,
          defaultMatchTarget: 3500,
        ),
      );
      addTearDown(() => hosted.http.close(force: true));
      final client = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'rules-defaults',
          playerName: 'Ana',
        ),
      );
      addTearDown(client.transport.dispose);
      final lobby = _nextEvent<LobbyUpdate>(client);

      await client.transport.connect();

      final created = await lobby;
      expect(created.profile, equals('biriba'));
      expect(created.numPlayers, equals(4));
      expect(created.matchTarget, equals(3500));
    });
  });
}
