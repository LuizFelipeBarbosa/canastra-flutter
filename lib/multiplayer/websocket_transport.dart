/// A [GameTransport] that talks to a remote authoritative host over a WebSocket.
///
/// The client side is complete: it frames [ClientCommand]s as JSON, decodes
/// [ServerEvent]s, and reconnects with backoff. What it needs is a server URL —
/// `bin/server.dart` in this repo is a working reference host you can point it
/// at (`dart run bin/server.dart`), and any production backend only has to
/// speak the same JSON to be a drop-in replacement.
///
/// Nothing else in the app changes when you switch to this: the UI already
/// renders from redacted [TableView]s it did not compute.
library;

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'protocol.dart';
import 'transport.dart';

class WebSocketTransport implements GameTransport {
  /// e.g. `ws://localhost:8080/ws` or `wss://play.example.com/ws`.
  final Uri endpoint;
  final String roomCode;
  final String playerName;
  final int? preferredSeat;

  /// How many times to retry a dropped connection before giving up.
  final int maxRetries;

  final _events = StreamController<ServerEvent>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  int? _seat;
  bool _connected = false;
  bool _disposed = false;
  int _retries = 0;

  WebSocketTransport({
    required this.endpoint,
    required this.roomCode,
    required this.playerName,
    this.preferredSeat,
    this.maxRetries = 5,
  });

  @override
  Stream<ServerEvent> get events => _events.stream;

  @override
  int? get seat => _seat;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect() async {
    if (_disposed) throw TransportException('transport was disposed');
    if (_connected) return;

    final WebSocketChannel channel;
    try {
      channel = WebSocketChannel.connect(endpoint);
      await channel.ready;
    } catch (e) {
      throw TransportException('could not reach $endpoint: $e');
    }

    _channel = channel;
    _connected = true;
    _retries = 0;
    _sub = channel.stream.listen(
      _onMessage,
      onDone: _onDisconnected,
      onError: (Object e) {
        _events.add(ServerError(message: 'connection error: $e'));
        _onDisconnected();
      },
    );

    send(JoinRoom(
      roomCode: roomCode,
      playerName: playerName,
      preferredSeat: preferredSeat,
    ));
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final event = ServerEvent.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
      if (event is Joined) _seat = event.seat;
      _events.add(event);
    } on FormatException catch (e) {
      // A message this client version does not understand is not fatal — a
      // newer server may simply have added an event type.
      _events.add(ServerError(message: 'unreadable message from host: $e'));
    }
  }

  void _onDisconnected() {
    _connected = false;
    if (_disposed) return;
    if (_retries >= maxRetries) {
      _events.add(const ServerError(message: 'lost connection to the host'));
      return;
    }
    final delay = Duration(milliseconds: 300 * (1 << _retries));
    _retries++;
    Timer(delay, () async {
      if (_disposed) return;
      try {
        await connect();
      } on TransportException {
        _onDisconnected();
      }
    });
  }

  @override
  void send(ClientCommand command) {
    final channel = _channel;
    if (!_connected || channel == null) {
      throw TransportException('not connected');
    }
    channel.sink.add(jsonEncode(command.toJson()));
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _connected = false;
    await _sub?.cancel();
    await _channel?.sink.close();
    await _events.close();
  }
}
