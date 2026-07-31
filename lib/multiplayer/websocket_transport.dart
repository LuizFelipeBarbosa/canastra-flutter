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
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'protocol.dart';
import 'transport.dart';

class WebSocketTransport implements GameTransport, ConnectionStateTransport {
  /// e.g. `ws://localhost:8080/ws` or `wss://play.example.com/ws`.
  final Uri endpoint;
  final String roomCode;
  final String playerName;
  final int? preferredSeat;
  final bool spectate;

  /// Supplies a fresh Supabase access token for each connection attempt.
  final Future<String?> Function()? authToken;

  /// Stable anonymous identity used for reconnects when host auth is off.
  final String? clientId;

  /// Rule profile declared when this connection creates the room.
  final String? profileId;

  /// Player count declared when this connection creates the room.
  final int? numPlayers;

  /// Match target declared when this connection creates the room.
  final int? matchTarget;

  /// How many times to retry a dropped connection before giving up.
  final int maxRetries;

  final _events = StreamController<ServerEvent>.broadcast();
  final _connectionChanges = StreamController<bool>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  int? _seat;
  bool _connected = false;
  bool _connecting = false;
  bool _reconnecting = false;
  bool _disposed = false;
  Timer? _retryTimer;
  int _retries = 0;

  WebSocketTransport({
    required this.endpoint,
    required this.roomCode,
    required this.playerName,
    this.preferredSeat,
    this.spectate = false,
    this.authToken,
    this.clientId,
    this.profileId,
    this.numPlayers,
    this.matchTarget,
    this.maxRetries = 8,
  });

  /// Computes one retry delay without opening a socket.
  @visibleForTesting
  static Duration retryDelay(int retries, {Random? random}) {
    final baseMilliseconds = 300 * (1 << retries);
    final multiplier = 0.75 + (random ?? Random()).nextDouble() * 0.5;
    return Duration(milliseconds: (baseMilliseconds * multiplier).round());
  }

  @override
  Stream<ServerEvent> get events => _events.stream;

  @override
  Stream<bool> get connectionChanges => _connectionChanges.stream;

  @override
  int? get seat => _seat;

  @override
  bool get isConnected => _connected;

  @override
  bool get reconnecting => _reconnecting;

  @override
  Future<void> connect() async {
    if (_disposed) throw TransportException('transport was disposed');
    if (_connected || _connecting) return;

    _connecting = true;
    try {
      final token = await authToken?.call();
      WebSocketChannel? connectingChannel;
      try {
        final channel = WebSocketChannel.connect(endpoint);
        connectingChannel = channel;
        _channel = channel;
        await channel.ready;
      } catch (e) {
        if (identical(_channel, connectingChannel)) _channel = null;
        throw TransportException('could not reach $endpoint: $e');
      }
      final channel = connectingChannel;
      if (_disposed) {
        if (identical(_channel, channel)) _channel = null;
        await channel.sink.close();
        throw TransportException('transport was disposed');
      }
      if (!identical(_channel, channel)) {
        await channel.sink.close();
        return;
      }
      if (_connected) return;

      _connected = true;
      _retries = 0;
      _setReconnecting(false);
      _sub = channel.stream.listen(
        _onMessage,
        onDone: _onDisconnected,
        onError: (Object e) {
          _events.add(ServerError(message: 'connection error: $e'));
          _onDisconnected();
        },
      );

      if (spectate) {
        send(
          SpectateRoom(
            roomCode: roomCode,
            authToken: token,
            clientId: clientId,
          ),
        );
      } else {
        send(
          JoinRoom(
            roomCode: roomCode,
            playerName: playerName,
            preferredSeat: _seat ?? preferredSeat,
            authToken: token,
            clientId: clientId,
            profileId: profileId,
            numPlayers: numPlayers,
            matchTarget: matchTarget,
          ),
        );
      }
    } finally {
      _connecting = false;
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final event = ServerEvent.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (event is Joined) _seat = event.spectator ? null : event.seat;
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
      _setReconnecting(false);
      _events.add(const ServerError(message: 'lost connection to the host'));
      return;
    }
    _setReconnecting(true);
    // Without jitter, every seat retries together after a host restart and
    // hammers it in synchronized waves; a small spread breaks that lockstep.
    final delay = retryDelay(_retries);
    _retries++;
    // Held so dispose() can defuse it: the flag alone makes the callback a
    // no-op, but the armed timer itself would outlive the transport by up to
    // the whole backoff.
    _retryTimer = Timer(delay, () async {
      if (_disposed) return;
      try {
        await connect();
      } on TransportException {
        _onDisconnected();
      }
    });
  }

  void _setReconnecting(bool value) {
    if (_reconnecting == value) return;
    _reconnecting = value;
    _connectionChanges.add(value);
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
    _retryTimer?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
    await _events.close();
    await _connectionChanges.close();
  }
}
