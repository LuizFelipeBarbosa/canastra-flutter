/// Reconnect tests keep the socket boundary scripted so controller and table
/// behavior can be exercised deterministically. The transport below exposes the
/// same broadcast connection-state seam as the WebSocket transport, while the
/// retry-delay test covers its pure jitter calculation without opening a port.
library;

import 'dart:async';
import 'dart:math';

import 'package:canastra/engine/profiles.dart';
import 'package:canastra/game/game_controller.dart';
import 'package:canastra/multiplayer/protocol.dart';
import 'package:canastra/multiplayer/table_view.dart';
import 'package:canastra/multiplayer/transport.dart';
import 'package:canastra/multiplayer/websocket_transport.dart';
import 'package:canastra/ui/app_scope.dart';
import 'package:canastra/ui/screens/game_screen.dart';
import 'package:canastra/ui/theme.dart';
import 'package:canastra/ui/widgets/playing_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScriptedTransport implements GameTransport, ConnectionStateTransport {
  final StreamController<ServerEvent> _events =
      StreamController<ServerEvent>.broadcast();
  final StreamController<bool> _connectionChanges =
      StreamController<bool>.broadcast();

  bool _connected = false;
  bool _reconnecting = false;

  @override
  Stream<ServerEvent> get events => _events.stream;

  @override
  Stream<bool> get connectionChanges => _connectionChanges.stream;

  @override
  int? get seat => null;

  @override
  bool get isConnected => _connected;

  @override
  bool get reconnecting => _reconnecting;

  @override
  Future<void> connect() async {
    _connected = true;
  }

  void emit(ServerEvent event) => _events.add(event);

  void setReconnecting(bool value) {
    if (_reconnecting == value) return;
    _reconnecting = value;
    _connectionChanges.add(value);
  }

  @override
  void send(ClientCommand command) {
    if (!_connected) throw TransportException('not connected');
  }

  @override
  Future<void> dispose() async {
    _connected = false;
    await _events.close();
    await _connectionChanges.close();
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

TableView _tableView() {
  final cfg = loadProfile('buraco', numPlayers: 2);
  return TableView(
    seat: 0,
    side: 0,
    numPlayers: 2,
    numSides: 2,
    partnerSeat: null,
    playerNames: const ['You', 'Bruno'],
    profile: cfg.name,
    matchTarget: cfg.scoring.matchTarget,
    canastraMinSize: cfg.meld.canastraMinSize,
    hand: const [0],
    handSizes: const [1, 0],
    melds: const [],
    trash: const [],
    stockCount: 0,
    mortoTaken: const [false, false],
    mortoSizes: const [11, 11],
    redThrees: const [[], []],
    currentPlayer: 0,
    phase: 'play',
    turnNumber: 1,
    frozen: false,
    pileBlocked: false,
    pendingPileCard: null,
    initialMeldDone: const [false, false],
    initialMeldMin: const [0, 0],
    stagedPoints: 0,
    publicScores: const [0, 0],
    matchScores: const [0, 0],
    matchNumber: 0,
    roundOver: false,
    matchOver: false,
    wentOutSide: null,
    winnerSide: null,
    roundIndex: 0,
    roundResult: null,
    legalActions: const [],
    history: const [],
  );
}

void main() {
  group('GameController reconnect state', () {
    test('follows connection changes and notifies listeners', () async {
      final transport = _ScriptedTransport();
      final controller = GameController(
        cfg: loadProfile('buraco', numPlayers: 2),
        transport: transport,
        autoReady: false,
      );
      addTearDown(() async {
        controller.dispose();
        await _settle();
      });

      await controller.start();
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      transport.setReconnecting(true);
      await _settle();
      expect(controller.reconnecting, isTrue);
      expect(notifications, 1);

      transport.setReconnecting(false);
      await _settle();
      expect(controller.reconnecting, isFalse);
      expect(notifications, 2);
    });
  });

  testWidgets('the reconnect overlay blocks and restores table interaction', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final transport = _ScriptedTransport();
    final controller = GameController(
      cfg: loadProfile('buraco', numPlayers: 2),
      transport: transport,
      autoReady: false,
    );
    final prefs = AppPrefs();

    await tester.pumpWidget(
      AppScope(
        prefs: prefs,
        child: MaterialApp(
          theme: buildTheme(prefs.palette, dark: prefs.dark),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: GameScreen(controller: controller),
          ),
        ),
      ),
    );
    transport.emit(TableUpdate(view: _tableView()));
    await tester.pump();

    transport.setReconnecting(true);
    // The signal crosses a stream, the controller's listener, and a setState
    // before it is visible — one frame is not enough.
    await tester.pump();
    await tester.pump();

    expect(find.text(prefs.copy.reconnecting), findsOneWidget);
    final heldCard = find.byWidgetPredicate(
      (widget) => widget is PlayingCard && widget.card == 0 && !widget.faceDown,
    );
    expect(heldCard, findsOneWidget);
    final blockers = tester.widgetList<IgnorePointer>(
      find.ancestor(of: heldCard, matching: find.byType(IgnorePointer)),
    );
    expect(blockers.any((widget) => widget.ignoring), isTrue);

    await tester.tap(heldCard, warnIfMissed: false);
    await tester.pump();
    expect(controller.selection, isEmpty);

    transport.setReconnecting(false);
    await tester.pump();
    await tester.pump();
    expect(find.text(prefs.copy.reconnecting), findsNothing);

    await tester.tap(heldCard);
    await tester.pump();
    expect(controller.selection, const [0]);

    // Inside testWidgets the clock is fake: a Future.delayed never fires, so
    // settling here must go through the tester, not _settle().
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  group('WebSocketTransport retry delay', () {
    test('uses the longer retry budget by default', () async {
      final transport = WebSocketTransport(
        endpoint: Uri.parse('ws://localhost/unused'),
        roomCode: 'TEST',
        playerName: 'You',
      );
      addTearDown(transport.dispose);

      expect(transport.maxRetries, 8);
    });

    test('stays within twenty-five percent of exponential backoff', () {
      final random = Random(17);

      for (final retries in const [0, 1, 3, 5]) {
        final baseMilliseconds = 300 * (1 << retries);
        final samples = [
          for (var i = 0; i < 128; i++)
            WebSocketTransport.retryDelay(
              retries,
              random: random,
            ).inMilliseconds,
        ];

        expect(
          samples,
          everyElement(
            inInclusiveRange(
              (baseMilliseconds * 0.75).round(),
              (baseMilliseconds * 1.25).round(),
            ),
          ),
        );
        expect(samples.any((delay) => delay < baseMilliseconds), isTrue);
        expect(samples.any((delay) => delay > baseMilliseconds), isTrue);
      }
    });
  });
}
