/// End-to-end test of online play.
///
/// Starts the real [GameServer] on a real socket and drives it with two real
/// [WebSocketTransport] clients — the same objects the app uses. This is what
/// makes "the multiplayer scaffolding works" a checked claim rather than an
/// assertion: JSON framing, seat assignment, turn enforcement and hidden-
/// information redaction all have to hold across a genuine network hop.
@Tags(['online'])
library;

import 'dart:async';
import 'dart:io';

import 'package:canastra/ai/agent.dart';
import 'package:canastra/engine/profiles.dart';
import 'package:canastra/multiplayer/auth.dart';
import 'package:canastra/multiplayer/game_backend.dart';
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

  group('disconnect resilience', () {
    test(
      'a dropped seat is taken over by a bot after the grace window',
      () async {
        final hosted = await _serveServer(
          GameServer(
            numPlayers: 2,
            botTakeoverAfter: const Duration(milliseconds: 120),
            roomGraceAfter: null,
          ),
        );
        addTearDown(() => hosted.http.close(force: true));
        final a = _Client(
          WebSocketTransport(
            endpoint: hosted.endpoint,
            roomCode: 'takeover',
            playerName: 'Ana',
            clientId: 'ana',
            maxRetries: 0,
          ),
        );
        final b = _Client(
          WebSocketTransport(
            endpoint: hosted.endpoint,
            roomCode: 'takeover',
            playerName: 'Bruno',
            clientId: 'bruno',
            maxRetries: 0,
          ),
        );
        addTearDown(a.transport.dispose);
        addTearDown(b.transport.dispose);

        await a.transport.connect();
        await b.transport.connect();
        a.transport.send(const SetReady(ready: true));
        b.transport.send(const SetReady(ready: true));
        await Future.wait([
          a.waitForTable((view) => view.hand.isNotEmpty),
          b.waitForTable((view) => view.hand.isNotEmpty),
        ]);

        final takenOver = _nextLobbyWhere(
          b,
          (lobby) => _seatIn(lobby, 0).kind == SeatKind.bot,
        );
        await a.transport.dispose();

        final lobby = await takenOver;
        expect(_seatIn(lobby, 0).kind, SeatKind.bot);
      },
    );

    test('a reconnect before the window keeps the seat human', () async {
      final hosted = await _serveServer(
        GameServer(
          numPlayers: 2,
          botTakeoverAfter: const Duration(milliseconds: 300),
          roomGraceAfter: null,
        ),
      );
      addTearDown(() => hosted.http.close(force: true));
      final a = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'quick-reconnect',
          playerName: 'Ana',
          clientId: 'ana',
          maxRetries: 0,
        ),
      );
      final b = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'quick-reconnect',
          playerName: 'Bruno',
          clientId: 'bruno',
          maxRetries: 0,
        ),
      );
      addTearDown(a.transport.dispose);
      addTearDown(b.transport.dispose);

      await a.transport.connect();
      await b.transport.connect();
      a.transport.send(const SetReady(ready: true));
      b.transport.send(const SetReady(ready: true));
      await Future.wait([
        a.waitForTable((view) => view.hand.isNotEmpty),
        b.waitForTable((view) => view.hand.isNotEmpty),
      ]);

      final disconnected = _nextLobbyWhere(
        b,
        (lobby) => !_seatIn(lobby, 0).connected,
      );
      await a.transport.dispose();
      await disconnected;

      final reconnected = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'quick-reconnect',
          playerName: 'Ana',
          clientId: 'ana',
          maxRetries: 0,
        ),
      );
      addTearDown(reconnected.transport.dispose);
      final joined = _nextEvent<Joined>(reconnected);
      final humanLobby = _nextLobbyWhere(
        reconnected,
        (lobby) =>
            _seatIn(lobby, 0).kind == SeatKind.remote &&
            _seatIn(lobby, 0).connected,
      );

      await reconnected.transport.connect();

      expect((await joined).seat, 0);
      expect(_seatIn(await humanLobby, 0).kind, SeatKind.remote);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final lobbies = [
        ...b.events.whereType<LobbyUpdate>(),
        ...reconnected.events.whereType<LobbyUpdate>(),
      ];
      expect(
        lobbies.any((lobby) => _seatIn(lobby, 0).kind == SeatKind.bot),
        isFalse,
      );
    });

    test('a reconnect after takeover evicts the bot', () async {
      final hosted = await _serveServer(
        GameServer(
          numPlayers: 2,
          botTakeoverAfter: const Duration(milliseconds: 120),
          roomGraceAfter: null,
        ),
      );
      addTearDown(() => hosted.http.close(force: true));
      final a = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'late-reconnect',
          playerName: 'Ana',
          clientId: 'ana',
          maxRetries: 0,
        ),
      );
      final b = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'late-reconnect',
          playerName: 'Bruno',
          clientId: 'bruno',
          maxRetries: 0,
        ),
      );
      addTearDown(a.transport.dispose);
      addTearDown(b.transport.dispose);

      await a.transport.connect();
      await b.transport.connect();
      a.transport.send(const SetReady(ready: true));
      b.transport.send(const SetReady(ready: true));
      await Future.wait([
        a.waitForTable((view) => view.hand.isNotEmpty),
        b.waitForTable((view) => view.hand.isNotEmpty),
      ]);

      final botLobby = _nextLobbyWhere(
        b,
        (lobby) => _seatIn(lobby, 0).kind == SeatKind.bot,
      );
      await a.transport.dispose();
      await botLobby;

      final reconnected = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'late-reconnect',
          playerName: 'Ana',
          clientId: 'ana',
          maxRetries: 0,
        ),
      );
      addTearDown(reconnected.transport.dispose);
      final joined = _nextEvent<Joined>(reconnected);
      final humanLobby = _nextLobbyWhere(
        reconnected,
        (lobby) => _seatIn(lobby, 0).kind == SeatKind.remote,
      );
      final table = _nextEvent<TableUpdate>(reconnected);

      await reconnected.transport.connect();

      expect((await joined).seat, 0);
      expect(_seatIn(await humanLobby, 0).kind, SeatKind.remote);
      expect((await table).view.seat, 0);
    });

    test('an empty room survives its grace window', () async {
      final hosted = await _serveServer(
        GameServer(
          profileId: 'rummy',
          numPlayers: 2,
          defaultMatchTarget: 2000,
          botTakeoverAfter: null,
          roomGraceAfter: const Duration(milliseconds: 300),
        ),
      );
      addTearDown(() => hosted.http.close(force: true));
      final a = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'room-grace',
          playerName: 'Ana',
          clientId: 'ana',
          profileId: 'canasta',
          numPlayers: 4,
          matchTarget: 1500,
          maxRetries: 0,
        ),
      );
      final b = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'room-grace',
          playerName: 'Bruno',
          clientId: 'bruno',
          maxRetries: 0,
        ),
      );
      addTearDown(a.transport.dispose);
      addTearDown(b.transport.dispose);
      final originalLobby = _nextEvent<LobbyUpdate>(a);

      await a.transport.connect();
      final original = await originalLobby;
      final bJoined = _nextEvent<Joined>(b);
      await b.transport.connect();
      expect(a.transport.seat, 0);
      expect((await bJoined).seat, 1);

      final aDisconnected = _nextLobbyWhere(
        b,
        (lobby) => !_seatIn(lobby, 0).connected,
      );
      await a.transport.dispose();
      await aDisconnected;
      await b.transport.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final reconnected = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'room-grace',
          playerName: 'Ana',
          clientId: 'ana',
          maxRetries: 0,
        ),
      );
      addTearDown(reconnected.transport.dispose);
      final joined = _nextEvent<Joined>(reconnected);
      final lobby = _nextEvent<LobbyUpdate>(reconnected);

      await reconnected.transport.connect();

      expect((await joined).seat, 0);
      final restored = await lobby;
      expect(restored.profile, original.profile);
      expect(restored.numPlayers, original.numPlayers);
      expect(restored.matchTarget, original.matchTarget);

      await reconnected.transport.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 450));
    });

    test('an empty room past its grace is gone', () async {
      final hosted = await _serveServer(
        GameServer(
          profileId: 'rummy',
          numPlayers: 2,
          defaultMatchTarget: 2000,
          botTakeoverAfter: null,
          roomGraceAfter: const Duration(milliseconds: 100),
        ),
      );
      addTearDown(() => hosted.http.close(force: true));
      final a = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'room-expired',
          playerName: 'Ana',
          clientId: 'ana',
          profileId: 'canasta',
          numPlayers: 4,
          matchTarget: 1500,
          maxRetries: 0,
        ),
      );
      final b = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'room-expired',
          playerName: 'Bruno',
          clientId: 'bruno',
          maxRetries: 0,
        ),
      );
      addTearDown(a.transport.dispose);
      addTearDown(b.transport.dispose);
      final originalLobby = _nextEvent<LobbyUpdate>(a);

      await a.transport.connect();
      expect((await originalLobby).profile, 'canasta');
      final bJoined = _nextEvent<Joined>(b);
      await b.transport.connect();
      expect((await bJoined).seat, 1);

      final aDisconnected = _nextLobbyWhere(
        b,
        (lobby) => !_seatIn(lobby, 0).connected,
      );
      await a.transport.dispose();
      await aDisconnected;
      await b.transport.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 250));

      final reconnected = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'room-expired',
          playerName: 'Ana',
          clientId: 'ana',
          maxRetries: 0,
        ),
      );
      addTearDown(reconnected.transport.dispose);
      final joined = _nextEvent<Joined>(reconnected);
      final lobby = _nextEvent<LobbyUpdate>(reconnected);

      await reconnected.transport.connect();

      expect((await joined).seat, 0);
      final fresh = await lobby;
      expect(fresh.profile, 'rummy');
      expect(fresh.numPlayers, 2);
      expect(fresh.matchTarget, 2000);

      await reconnected.transport.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
  });

  group('spectators', () {
    test('a spectator holds no seat and receives live table updates', () async {
      final hosted = await _serveServer(
        GameServer(numPlayers: 2, botTakeoverAfter: null, roomGraceAfter: null),
      );
      addTearDown(() => hosted.http.close(force: true));
      final a = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'live-gallery',
          playerName: 'Ana',
        ),
      );
      final b = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'live-gallery',
          playerName: 'Bruno',
        ),
      );
      addTearDown(a.transport.dispose);
      addTearDown(b.transport.dispose);

      await a.transport.connect();
      await b.transport.connect();
      a.transport.send(const SetReady(ready: true));
      b.transport.send(const SetReady(ready: true));
      final dealt = await a.waitForTable((view) => view.hand.isNotEmpty);
      await b.waitForTable((view) => view.hand.isNotEmpty);
      final seatsBefore = a.events.whereType<LobbyUpdate>().last.seats.length;

      final spectator = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'live-gallery',
          playerName: 'Viewer',
          spectate: true,
        ),
      );
      addTearDown(spectator.transport.dispose);
      final joined = _nextEvent<Joined>(spectator);
      final lobby = _nextLobbyWhere(
        spectator,
        (update) => update.spectators == 1,
      );

      await spectator.transport.connect();

      final spectatorJoined = await joined;
      expect(spectatorJoined.spectator, isTrue);
      expect(spectatorJoined.seat, equals(-1));
      expect(spectator.transport.seat, isNull);
      final spectatorLobby = await lobby;
      expect(spectatorLobby.seats, hasLength(seatsBefore));
      expect(spectatorLobby.spectators, equals(1));

      final firstView = await spectator.waitForTable(
        (view) => view.stockCount == dealt.stockCount,
      );
      expect(firstView.hand, isEmpty);
      expect(firstView.legalActions, isEmpty);

      a.transport.send(SubmitAction(actionId: dealt.legalActions.first));
      final updated = await spectator.waitForTable(
        (view) =>
            view.phase != firstView.phase ||
            view.stockCount != firstView.stockCount ||
            view.turnNumber != firstView.turnNumber,
      );
      expect(updated.hand, isEmpty);
      expect(updated.legalActions, isEmpty);
    });

    test('a spectator action is rejected without changing the match', () async {
      final hosted = await _serveServer(
        GameServer(numPlayers: 2, botTakeoverAfter: null, roomGraceAfter: null),
      );
      addTearDown(() => hosted.http.close(force: true));
      final a = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'look-only',
          playerName: 'Ana',
        ),
      );
      final b = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'look-only',
          playerName: 'Bruno',
        ),
      );
      final spectator = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'look-only',
          playerName: 'Viewer',
          spectate: true,
        ),
      );
      addTearDown(a.transport.dispose);
      addTearDown(b.transport.dispose);
      addTearDown(spectator.transport.dispose);

      await a.transport.connect();
      await b.transport.connect();
      a.transport.send(const SetReady(ready: true));
      b.transport.send(const SetReady(ready: true));
      await Future.wait([
        a.waitForTable((view) => view.hand.isNotEmpty),
        b.waitForTable((view) => view.hand.isNotEmpty),
      ]);
      await spectator.transport.connect();
      await spectator.waitForTable((view) => view.hand.isEmpty);

      final before = a.table!.toJson();
      final error = _nextEvent<ServerError>(spectator);
      spectator.transport.send(const SubmitAction(actionId: 0));

      expect((await error).message, equals('spectators only watch'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(a.table!.toJson(), equals(before));
    });

    test('a ninth spectator is refused by the per-room cap', () async {
      final hosted = await _serveServer(
        GameServer(numPlayers: 2, botTakeoverAfter: null, roomGraceAfter: null),
      );
      addTearDown(() => hosted.http.close(force: true));
      final player = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'full-gallery',
          playerName: 'Ana',
        ),
      );
      addTearDown(player.transport.dispose);
      final playerJoined = _nextEvent<Joined>(player);
      await player.transport.connect();
      await playerJoined;

      final spectators = <_Client>[];
      for (var i = 0; i < 8; i++) {
        final spectator = _Client(
          WebSocketTransport(
            endpoint: hosted.endpoint,
            roomCode: 'full-gallery',
            playerName: 'Viewer $i',
            spectate: true,
          ),
        );
        spectators.add(spectator);
        addTearDown(spectator.transport.dispose);
        final joined = _nextEvent<Joined>(spectator);
        await spectator.transport.connect();
        expect((await joined).spectator, isTrue);
      }

      final ninth = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'full-gallery',
          playerName: 'Viewer 9',
          spectate: true,
          maxRetries: 0,
        ),
      );
      addTearDown(ninth.transport.dispose);
      final error = _nextEvent<ServerError>(ninth);

      await ninth.transport.connect();

      expect((await error).message, equals('the gallery is full'));
      expect(ninth.transport.seat, isNull);
      expect(ninth.events.whereType<Joined>(), isEmpty);
      expect(
        spectators.expand((client) => client.events.whereType<Joined>()).length,
        equals(8),
      );
    });

    test('spectators do not keep an empty room alive past grace', () async {
      final hosted = await _serveServer(
        GameServer(
          numPlayers: 2,
          botTakeoverAfter: null,
          roomGraceAfter: const Duration(milliseconds: 120),
        ),
      );
      addTearDown(() => hosted.http.close(force: true));
      final a = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'gallery-grace',
          playerName: 'Ana',
          maxRetries: 0,
        ),
      );
      final b = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'gallery-grace',
          playerName: 'Bruno',
          maxRetries: 0,
        ),
      );
      final spectator = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'gallery-grace',
          playerName: 'Viewer',
          spectate: true,
          maxRetries: 0,
        ),
      );
      addTearDown(a.transport.dispose);
      addTearDown(b.transport.dispose);
      addTearDown(spectator.transport.dispose);

      await a.transport.connect();
      await b.transport.connect();
      final spectatorJoined = _nextEvent<Joined>(spectator);
      await spectator.transport.connect();
      expect((await spectatorJoined).spectator, isTrue);

      final disconnected = _nextEvent<ServerError>(spectator);
      await a.transport.dispose();
      await b.transport.dispose();
      expect(
        (await disconnected).message,
        equals('lost connection to the host'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final lateSpectator = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'gallery-grace',
          playerName: 'Late viewer',
          spectate: true,
          maxRetries: 0,
        ),
      );
      addTearDown(lateSpectator.transport.dispose);
      final noTable = _nextEvent<ServerError>(lateSpectator);

      await lateSpectator.transport.connect();

      expect((await noTable).message, equals('no such table'));
    });
  });

  group('game backend integration', () {
    test(
      'a finished open match records one internally consistent payload',
      () async {
        final backend = _RecordingBackend();
        final server = GameServer(
          profileId: 'rummy',
          numPlayers: 2,
          defaultMatchTarget: 500,
          backend: backend,
          botTakeoverAfter: null,
          roomGraceAfter: null,
        );
        final hosted = await _serveServer(server);
        addTearDown(() async {
          await hosted.http.close(force: true);
          await server.dispose();
        });
        final ana = _Client(
          WebSocketTransport(
            endpoint: hosted.endpoint,
            roomCode: 'record-match',
            playerName: 'Ana',
            clientId: 'client-ana',
            maxRetries: 0,
          ),
        );
        final bruno = _Client(
          WebSocketTransport(
            endpoint: hosted.endpoint,
            roomCode: 'record-match',
            playerName: 'Bruno',
            clientId: 'client-bruno',
            maxRetries: 0,
          ),
        );
        addTearDown(ana.transport.dispose);
        addTearDown(bruno.transport.dispose);

        await ana.transport.connect();
        await bruno.transport.connect();
        ana.transport.send(const SetReady(ready: true));
        bruno.transport.send(const SetReady(ready: true));
        await Future.wait([
          ana.waitForTable((view) => view.hand.isNotEmpty),
          bruno.waitForTable((view) => view.hand.isNotEmpty),
        ]);

        final terminal = await _driveRummyMatch(ana, bruno);
        final payload = await backend.nextRecord.timeout(
          const Duration(seconds: 10),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(backend.recorded, hasLength(1));
        expect(backend.authorizationCalls, isEmpty);
        expect(payload['room_code'], equals('record-match'));
        expect(payload['room_id'], isNull);
        expect(payload['is_ranked'], isFalse);
        expect(payload['final_scores'], equals(terminal.matchScores));

        final players = (payload['players'] as List)
            .cast<Map<String, dynamic>>();
        expect(players, hasLength(2));
        final anaRecord = players.singleWhere((player) => player['seat'] == 0);
        final brunoRecord = players.singleWhere(
          (player) => player['seat'] == 1,
        );
        expect(anaRecord['display_name'], equals('Ana'));
        expect(brunoRecord['display_name'], equals('Bruno'));
        for (final player in players) {
          expect(player['user_id'], isNull);
          expect(player['is_bot'], isFalse);
        }

        final sides = (payload['sides'] as List).cast<Map<String, dynamic>>();
        expect(sides, hasLength(terminal.numSides));
        for (var side = 0; side < terminal.numSides; side++) {
          final sideRecord = sides.singleWhere(
            (candidate) => candidate['side'] == side,
          );
          expect(sideRecord['score_final'], equals(terminal.matchScores[side]));
        }

        final rounds = (payload['rounds'] as List).cast<Map<String, dynamic>>();
        expect(rounds, hasLength(terminal.roundIndex + 1));
        for (var side = 0; side < terminal.numSides; side++) {
          final scoreFromRounds = rounds.fold<int>(0, (total, round) {
            final sheetView = round['sheet'] as Map<String, dynamic>;
            final sheets = (sheetView['sheets'] as List)
                .cast<Map<String, dynamic>>();
            final sheet = sheets.singleWhere(
              (candidate) => candidate['side'] == side,
            );
            return total + sheet['total'] as int;
          });
          expect(scoreFromRounds, equals(terminal.matchScores[side]));
        }
        expect(rounds.last['match_scores_after'], equals(terminal.matchScores));

        final orderedScores = List<int>.of(terminal.matchScores)
          ..sort((a, b) => b.compareTo(a));
        final expectedWinner = orderedScores[0] == orderedScores[1]
            ? null
            : terminal.matchScores.indexOf(orderedScores[0]);
        expect(payload['winner_side'], expectedWinner);
      },
    );

    test('authorized rules and seat override the client declaration', () async {
      final backend = _RecordingBackend(
        authorizationResponse: {
          'ok': true,
          'room_id': '00000000-0000-0000-0000-000000000123',
          'seat': 1,
          'is_ranked': true,
          'ladder_id': 'ranked-2p',
          'rules': {'profile': 'buraco', 'num_players': 2, 'match_target': 500},
        },
      );
      final server = GameServer(verifier: _StubVerifier(), backend: backend);
      final hosted = await _serveServer(server);
      addTearDown(() async {
        await hosted.http.close(force: true);
        await server.dispose();
      });
      final client = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'authorized-room',
          playerName: 'Ana',
          preferredSeat: 0,
          authToken: () async => 'good-token',
          profileId: 'rummy',
          numPlayers: 2,
          matchTarget: 2000,
          maxRetries: 0,
        ),
      );
      addTearDown(client.transport.dispose);
      final joined = _nextEvent<Joined>(client);
      final lobby = _nextEvent<LobbyUpdate>(client);

      await client.transport.connect();

      expect((await joined).seat, equals(1));
      final update = await lobby;
      expect(update.profile, equals('buraco'));
      expect(update.numPlayers, equals(2));
      expect(update.matchTarget, equals(500));
      expect(
        update.seats.singleWhere((seat) => seat.seat == 1).name,
        equals('Ana'),
      );
      expect(backend.authorizationCalls, hasLength(1));
      expect(
        backend.authorizationCalls.single,
        containsPair('user_id', 'verified-user'),
      );
    });

    test('an explicit room authorization refusal closes the socket', () async {
      final backend = _RecordingBackend(
        authorizationResponse: {'ok': false, 'reason': 'room expired'},
      );
      final server = GameServer(verifier: _StubVerifier(), backend: backend);
      final hosted = await _serveServer(server);
      addTearDown(() async {
        await hosted.http.close(force: true);
        await server.dispose();
      });
      final client = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'expired-room',
          playerName: 'Ana',
          authToken: () async => 'good-token',
          maxRetries: 0,
        ),
      );
      addTearDown(client.transport.dispose);
      final error = _nextEvent<ServerError>(client);

      await client.transport.connect();

      expect((await error).message, equals('room expired'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(client.transport.isConnected, isFalse);
      expect(client.events.whereType<Joined>(), isEmpty);
    });

    test('an unreachable room backend falls back to open seating', () async {
      final backend = _RecordingBackend();
      final server = GameServer(verifier: _StubVerifier(), backend: backend);
      final hosted = await _serveServer(server);
      addTearDown(() async {
        await hosted.http.close(force: true);
        await server.dispose();
      });
      final client = _Client(
        WebSocketTransport(
          endpoint: hosted.endpoint,
          roomCode: 'backend-down',
          playerName: 'Ana',
          preferredSeat: 0,
          authToken: () async => 'good-token',
          profileId: 'rummy',
          numPlayers: 2,
          matchTarget: 2000,
          maxRetries: 0,
        ),
      );
      addTearDown(client.transport.dispose);
      final joined = _nextEvent<Joined>(client);
      final lobby = _nextEvent<LobbyUpdate>(client);

      await client.transport.connect();

      expect((await joined).seat, equals(0));
      final update = await lobby;
      expect(update.profile, equals('rummy'));
      expect(update.numPlayers, equals(2));
      expect(update.matchTarget, equals(2000));
      expect(backend.authorizationCalls, hasLength(1));
    });
  });
}

Future<LobbyUpdate> _nextLobbyWhere(
  _Client client,
  bool Function(LobbyUpdate) test,
) => client.transport.events
    .where((event) => event is LobbyUpdate)
    .cast<LobbyUpdate>()
    .firstWhere(test)
    .timeout(const Duration(seconds: 5));

SeatInfo _seatIn(LobbyUpdate lobby, int seat) =>
    lobby.seats.singleWhere((candidate) => candidate.seat == seat);

Future<TableView> _driveRummyMatch(_Client ana, _Client bruno) async {
  final cfg = loadProfile('rummy', numPlayers: 2).withMatchTarget(500);
  final agents = [HeuristicAgent(seed: 101), HeuristicAgent(seed: 202)];

  for (var guard = 0; guard < 50000; guard++) {
    final view = ana.table;
    if (view == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      continue;
    }
    if (view.matchOver) return view;

    final anaUpdates = ana.events.whereType<TableUpdate>().length;
    final brunoUpdates = bruno.events.whereType<TableUpdate>().length;
    if (view.roundOver) {
      ana.transport.send(const RequestNextRound());
    } else {
      final actingClient = view.currentPlayer == 0 ? ana : bruno;
      final actingView = actingClient.table;
      if (actingView == null ||
          actingView.currentPlayer != view.currentPlayer ||
          actingView.roundIndex != view.roundIndex ||
          actingView.turnNumber != view.turnNumber ||
          actingView.phase != view.phase) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        continue;
      }
      actingClient.transport.send(
        SubmitAction(
          actionId: agents[view.currentPlayer].chooseAction(cfg, actingView),
        ),
      );
    }

    await Future.wait([
      _waitForTableCount(ana, anaUpdates + 1),
      _waitForTableCount(bruno, brunoUpdates + 1),
    ]);
  }
  throw StateError('rummy match did not finish');
}

Future<void> _waitForTableCount(_Client client, int count) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (client.events.whereType<TableUpdate>().length >= count) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError('timed out waiting for table update $count');
}

class _RecordingBackend implements GameBackend {
  final Map<String, dynamic>? authorizationResponse;
  final List<Map<String, dynamic>> authorizationCalls = [];
  final List<Map<String, dynamic>> recorded = [];
  final Completer<Map<String, dynamic>> _firstRecord = Completer();

  _RecordingBackend({this.authorizationResponse});

  Future<Map<String, dynamic>> get nextRecord => _firstRecord.future;

  @override
  Future<Map<String, dynamic>?> authorizeJoin({
    required String roomCode,
    required String userId,
    bool spectator = false,
  }) async {
    authorizationCalls.add({
      'room_code': roomCode,
      'user_id': userId,
      'spectator': spectator,
    });
    return authorizationResponse;
  }

  @override
  Future<void> recordMatchResult(Map<String, dynamic> payload) async {
    recorded.add(payload);
    if (!_firstRecord.isCompleted) _firstRecord.complete(payload);
  }

  @override
  Future<void> dispose() async {}
}
