/// Lobby tests use the local host where possible so the ready handshake is the
/// same one offline play depends on. A tiny scripted transport is reserved for
/// authoritative rule updates that a local room would never contradict.
library;

import 'dart:async';

import 'package:canastra/engine/profiles.dart';
import 'package:canastra/game/game_controller.dart';
import 'package:canastra/multiplayer/local_transport.dart';
import 'package:canastra/multiplayer/protocol.dart';
import 'package:canastra/multiplayer/transport.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScriptedTransport implements GameTransport {
  final StreamController<ServerEvent> _events =
      StreamController<ServerEvent>.broadcast();
  bool _connected = false;

  @override
  Stream<ServerEvent> get events => _events.stream;

  @override
  int? get seat => null;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect() async {
    _connected = true;
  }

  void emit(ServerEvent event) => _events.add(event);

  @override
  void send(ClientCommand command) {
    if (!_connected) throw TransportException('not connected');
  }

  @override
  Future<void> dispose() async {
    _connected = false;
    await _events.close();
  }
}

Future<void> _settle() async {
  // The local host, transport and controller each contribute an asynchronous
  // stream hop.
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

GameController _localController({bool autoReady = true}) {
  final cfg = loadProfile('buraco', numPlayers: 2);
  return GameController(
    cfg: cfg,
    transport: LocalTransport.singlePlayer(
      cfg: cfg,
      seed: 9,
      botDelay: Duration.zero,
    ),
    autoReady: autoReady,
  );
}

void main() {
  test('autoReady false keeps the table waiting', () async {
    final controller = _localController(autoReady: false);
    addTearDown(() async {
      controller.dispose();
      await _settle();
    });

    await controller.start();
    await _settle();

    expect(controller.inLobby, isTrue);
    expect(controller.myReady, isFalse);
    expect(controller.view, isNull);
  });

  test('setReady starts the match', () async {
    final controller = _localController(autoReady: false);
    addTearDown(() async {
      controller.dispose();
      await _settle();
    });

    await controller.start();
    await _settle();
    controller.setReady(true);
    await _settle();

    expect(controller.view, isNotNull);
    expect(controller.inLobby, isFalse);
  });

  test('autoReady true deals immediately', () async {
    final controller = _localController();
    addTearDown(() async {
      controller.dispose();
      await _settle();
    });

    await controller.start();
    await _settle();

    expect(controller.view, isNotNull);
    expect(controller.inLobby, isFalse);
  });

  test('the lobby rebuilds rules from the wire', () async {
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
    transport.emit(const Joined(roomCode: 'RULES', seat: 0));
    transport.emit(
      const LobbyUpdate(
        roomCode: 'RULES',
        profile: 'canasta',
        numPlayers: 2,
        seats: [
          SeatInfo(seat: 0, name: 'You', kind: SeatKind.human),
          SeatInfo(
            seat: 1,
            name: 'Open',
            kind: SeatKind.empty,
            connected: false,
          ),
        ],
        started: false,
        matchTarget: 4500,
      ),
    );
    await _settle();

    expect(controller.cfg.name, 'canasta');
    expect(controller.cfg.scoring.matchTarget, 4500);

    final knownRules = controller.cfg;
    transport.emit(
      const LobbyUpdate(
        roomCode: 'RULES',
        profile: 'future-table',
        numPlayers: 2,
        seats: [],
        started: false,
        matchTarget: 6000,
      ),
    );
    await _settle();

    expect(controller.cfg, same(knownRules));
    expect(controller.notice, isNotNull);
  });
}
