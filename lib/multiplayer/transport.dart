/// The seam between the game and wherever the authoritative host happens to be.
///
/// The UI talks to a [GameTransport] and nothing else. Single-player, hot-seat
/// and (eventually) online play differ only in which implementation is plugged
/// in — [LocalTransport] runs the host in this isolate, [WebSocketTransport]
/// runs it on a server. Because the local path goes through the same commands
/// and the same redacted [TableView] as the network path, offline play
/// continuously exercises the multiplayer code: a bug in the protocol shows up
/// in single-player, not on launch day.
library;

import 'dart:async';

import 'protocol.dart';

abstract class GameTransport {
  /// Events from the host. Broadcast, so several widgets may listen.
  Stream<ServerEvent> get events;

  /// The seat this client occupies, once [Joined] has arrived.
  int? get seat;

  bool get isConnected;

  Future<void> connect();

  /// Fire-and-forget: the host answers with events, never with a return value.
  void send(ClientCommand command);

  Future<void> dispose();
}

/// Connection-state support implemented only by transports that can reconnect.
///
/// This stays separate from [GameTransport]'s interface because its existing
/// implementations use `implements`, which does not inherit concrete defaults.
abstract interface class ConnectionStateTransport {
  bool get reconnecting;

  Stream<bool> get connectionChanges;
}

/// Non-breaking connection-state defaults for transports without reconnects.
extension GameTransportConnectionState on GameTransport {
  bool get reconnecting => switch (this) {
    ConnectionStateTransport transport => transport.reconnecting,
    _ => false,
  };

  Stream<bool> get connectionChanges => switch (this) {
    ConnectionStateTransport transport => transport.connectionChanges,
    _ => const Stream.empty(),
  };
}

/// Thrown when a transport cannot reach its host.
class TransportException implements Exception {
  final String message;
  TransportException(this.message);
  @override
  String toString() => 'TransportException: $message';
}
