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

  TableView? get table =>
      events.whereType<TableUpdate>().isEmpty
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
}
