/// A [GameTransport] whose host lives in this isolate.
///
/// Backs single-player and hot-seat. It is a genuine client of [MatchHost] —
/// commands go in, redacted views come out — so nothing in the UI can reach
/// around it to read hidden state.
library;

import 'dart:async';

import '../ai/agent.dart';
import '../engine/config.dart';
import 'match_host.dart';
import 'protocol.dart';
import 'transport.dart';

class LocalTransport implements GameTransport {
  final MatchHost host;

  /// The seat this client controls. In hot-seat play the device passes through
  /// several seats; see [HotSeatTransport].
  final int mySeat;

  final _events = StreamController<ServerEvent>.broadcast();
  StreamSubscription<HostMessage>? _sub;
  bool _connected = false;
  int? _seat;

  LocalTransport({required this.host, required this.mySeat});

  /// Build a table of one human plus bots.
  factory LocalTransport.singlePlayer({
    required RulesConfig cfg,
    required int seed,
    String playerName = 'You',
    AgentLevel botLevel = AgentLevel.normal,
    Duration botDelay = const Duration(milliseconds: 600),
  }) {
    final seats = [
      for (var i = 0; i < cfg.table.numPlayers; i++)
        SeatInfo(
          seat: i,
          name: i == 0 ? playerName : _botName(i, cfg.table.numPlayers),
          kind: i == 0 ? SeatKind.human : SeatKind.bot,
          ready: i != 0,
        ),
    ];
    final host = MatchHost(
      roomCode: 'LOCAL',
      cfg: cfg,
      seed: seed,
      seats: seats,
      botLevel: botLevel,
      botDelay: botDelay,
    );
    return LocalTransport(host: host, mySeat: 0);
  }

  @override
  Stream<ServerEvent> get events => _events.stream;

  @override
  int? get seat => _seat;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect() async {
    if (_connected) return;
    _connected = true;
    _sub = host.outbound.listen((msg) {
      if (msg.seat == null || msg.seat == mySeat) _events.add(msg.event);
    });
    _seat = mySeat;
    // Let the listener attach before the first burst of events.
    await Future<void>.delayed(Duration.zero);
  }

  @override
  void send(ClientCommand command) {
    if (!_connected) throw TransportException('not connected');
    host.handle(mySeat, command);
  }

  @override
  Future<void> dispose() async {
    _connected = false;
    await _sub?.cancel();
    host.dispose();
    await _events.close();
  }
}

/// Hot-seat: one device, several human seats, passed around the table.
///
/// It forwards every seat's events to the single screen and stamps outgoing
/// commands with whichever seat is currently to act, so the UI can stay exactly
/// the same as in online play.
class HotSeatTransport implements GameTransport {
  final MatchHost host;

  final _events = StreamController<ServerEvent>.broadcast();
  StreamSubscription<HostMessage>? _sub;
  bool _connected = false;

  HotSeatTransport({required this.host});

  factory HotSeatTransport.table({
    required RulesConfig cfg,
    required int seed,
    required List<String> names,
    List<bool>? isBot,
    AgentLevel botLevel = AgentLevel.normal,
    Duration botDelay = const Duration(milliseconds: 600),
  }) {
    final seats = [
      for (var i = 0; i < cfg.table.numPlayers; i++)
        SeatInfo(
          seat: i,
          name: i < names.length ? names[i] : _botName(i, cfg.table.numPlayers),
          kind: (isBot != null && i < isBot.length && isBot[i])
              ? SeatKind.bot
              : SeatKind.human,
          ready: true,
        ),
    ];
    return HotSeatTransport(
      host: MatchHost(
        roomCode: 'HOTSEAT',
        cfg: cfg,
        seed: seed,
        seats: seats,
        botLevel: botLevel,
        botDelay: botDelay,
      ),
    );
  }

  @override
  Stream<ServerEvent> get events => _events.stream;

  /// The seat currently holding the device.
  @override
  int? get seat => host.match.currentPlayer;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect() async {
    if (_connected) return;
    _connected = true;
    _sub = host.outbound.listen((msg) {
      // Only the seat to act should see a hand, so forward that seat's view.
      if (msg.seat == null || msg.seat == host.match.currentPlayer) {
        _events.add(msg.event);
      }
    });
    await Future<void>.delayed(Duration.zero);
  }

  @override
  void send(ClientCommand command) {
    if (!_connected) throw TransportException('not connected');
    host.handle(host.match.currentPlayer, command);
  }

  @override
  Future<void> dispose() async {
    _connected = false;
    await _sub?.cancel();
    host.dispose();
    await _events.close();
  }
}

/// Short on purpose: three opponents share one phone-width row, and the
/// handshake icon already marks which one is your partner.
String _botName(int seat, int numPlayers) =>
    const ['Ana', 'Bruno', 'Carla', 'Diego'][seat % 4];
