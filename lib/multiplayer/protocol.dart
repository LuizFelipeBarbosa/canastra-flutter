/// The client/server wire protocol.
///
/// Every message is JSON with a `type` discriminator, so the same definitions
/// serve the in-process local host today and a real server later without the
/// game code noticing which one it is talking to.
///
/// The protocol is deliberately thin: clients send *intent* (an action id from
/// the legal list the server gave them), the server replies with a fresh
/// [TableView]. Clients never compute state — they render what they are told —
/// which is what stops a modified client from cheating.
library;

import 'table_view.dart';

/// How a seat is filled.
enum SeatKind { human, bot, remote, empty }

class SeatInfo {
  final int seat;
  final String name;
  final SeatKind kind;
  final bool connected;
  final bool ready;

  const SeatInfo({
    required this.seat,
    required this.name,
    required this.kind,
    this.connected = true,
    this.ready = false,
  });

  SeatInfo copyWith({
    String? name,
    SeatKind? kind,
    bool? connected,
    bool? ready,
  }) => SeatInfo(
    seat: seat,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    connected: connected ?? this.connected,
    ready: ready ?? this.ready,
  );

  Map<String, dynamic> toJson() => {
    'seat': seat,
    'name': name,
    'kind': kind.name,
    'connected': connected,
    'ready': ready,
  };

  factory SeatInfo.fromJson(Map<String, dynamic> j) => SeatInfo(
    seat: j['seat'] as int,
    name: j['name'] as String,
    kind: SeatKind.values.byName(j['kind'] as String),
    connected: j['connected'] as bool,
    ready: j['ready'] as bool,
  );
}

// --- client -> server ---------------------------------------------------------

sealed class ClientCommand {
  const ClientCommand();

  Map<String, dynamic> toJson();

  static ClientCommand fromJson(Map<String, dynamic> j) =>
      switch (j['type'] as String) {
        'join' => JoinRoom(
          roomCode: j['roomCode'] as String,
          playerName: j['playerName'] as String,
          preferredSeat: j['preferredSeat'] as int?,
        ),
        'ready' => SetReady(ready: j['ready'] as bool),
        'action' => SubmitAction(actionId: j['actionId'] as int),
        'nextRound' => const RequestNextRound(),
        'rematch' => const RequestRematch(),
        'leave' => const LeaveRoom(),
        final t => throw FormatException('unknown command type: $t'),
      };
}

class JoinRoom extends ClientCommand {
  final String roomCode;
  final String playerName;

  /// Null lets the host place you in the first free seat.
  final int? preferredSeat;

  const JoinRoom({
    required this.roomCode,
    required this.playerName,
    this.preferredSeat,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'join',
    'roomCode': roomCode,
    'playerName': playerName,
    'preferredSeat': preferredSeat,
  };
}

class SetReady extends ClientCommand {
  final bool ready;
  const SetReady({required this.ready});

  @override
  Map<String, dynamic> toJson() => {'type': 'ready', 'ready': ready};
}

/// Play one micro-action. [actionId] must come from the `legalActions` list of
/// the most recent [TableView] — anything else is rejected by the host.
class SubmitAction extends ClientCommand {
  final int actionId;
  const SubmitAction({required this.actionId});

  @override
  Map<String, dynamic> toJson() => {'type': 'action', 'actionId': actionId};
}

class RequestNextRound extends ClientCommand {
  const RequestNextRound();
  @override
  Map<String, dynamic> toJson() => {'type': 'nextRound'};
}

class RequestRematch extends ClientCommand {
  const RequestRematch();
  @override
  Map<String, dynamic> toJson() => {'type': 'rematch'};
}

class LeaveRoom extends ClientCommand {
  const LeaveRoom();
  @override
  Map<String, dynamic> toJson() => {'type': 'leave'};
}

// --- server -> client ---------------------------------------------------------

sealed class ServerEvent {
  const ServerEvent();

  Map<String, dynamic> toJson();

  static ServerEvent fromJson(Map<String, dynamic> j) =>
      switch (j['type'] as String) {
        'joined' => Joined(
          roomCode: j['roomCode'] as String,
          seat: j['seat'] as int,
        ),
        'lobby' => LobbyUpdate(
          roomCode: j['roomCode'] as String,
          profile: j['profile'] as String,
          numPlayers: j['numPlayers'] as int,
          seats: [
            for (final s in (j['seats'] as List).cast<Map<String, dynamic>>())
              SeatInfo.fromJson(s),
          ],
          started: j['started'] as bool,
        ),
        'table' => TableUpdate(
          view: TableView.fromJson(j['view'] as Map<String, dynamic>),
        ),
        'rejected' => ActionRejected(
          actionId: j['actionId'] as int,
          reason: j['reason'] as String,
        ),
        'error' => ServerError(message: j['message'] as String),
        final t => throw FormatException('unknown event type: $t'),
      };
}

/// Sent once, right after a successful join: this is your seat.
class Joined extends ServerEvent {
  final String roomCode;
  final int seat;
  const Joined({required this.roomCode, required this.seat});

  @override
  Map<String, dynamic> toJson() => {
    'type': 'joined',
    'roomCode': roomCode,
    'seat': seat,
  };
}

/// The pre-game roster; also sent when someone joins, leaves or readies up.
class LobbyUpdate extends ServerEvent {
  final String roomCode;
  final String profile;
  final int numPlayers;
  final List<SeatInfo> seats;
  final bool started;

  const LobbyUpdate({
    required this.roomCode,
    required this.profile,
    required this.numPlayers,
    required this.seats,
    required this.started,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'lobby',
    'roomCode': roomCode,
    'profile': profile,
    'numPlayers': numPlayers,
    'seats': [for (final s in seats) s.toJson()],
    'started': started,
  };
}

/// The authoritative state, redacted for the receiving seat. Sent after every
/// applied action — clients re-render from this and hold no derived state.
class TableUpdate extends ServerEvent {
  final TableView view;
  const TableUpdate({required this.view});

  @override
  Map<String, dynamic> toJson() => {'type': 'table', 'view': view.toJson()};
}

/// The submitted action was not legal. The accompanying [TableUpdate] restates
/// the truth, so the client should simply re-render.
class ActionRejected extends ServerEvent {
  final int actionId;
  final String reason;
  const ActionRejected({required this.actionId, required this.reason});

  @override
  Map<String, dynamic> toJson() => {
    'type': 'rejected',
    'actionId': actionId,
    'reason': reason,
  };
}

class ServerError extends ServerEvent {
  final String message;
  const ServerError({required this.message});

  @override
  Map<String, dynamic> toJson() => {'type': 'error', 'message': message};
}
