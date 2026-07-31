/// Tests for the transport seam: bots play only from what they are shown, the
/// view a seat receives leaks nothing, and the protocol survives a JSON round
/// trip.
library;

import 'dart:convert';

import 'package:canastra/ai/agent.dart';
import 'package:canastra/engine/cards.dart';
import 'package:canastra/engine/match.dart';
import 'package:canastra/engine/profiles.dart';
import 'package:canastra/engine/state.dart';
import 'package:canastra/multiplayer/local_transport.dart';
import 'package:canastra/multiplayer/match_host.dart';
import 'package:canastra/multiplayer/protocol.dart';
import 'package:canastra/multiplayer/table_view.dart';
import 'package:flutter_test/flutter_test.dart';

MatchHost _botTable(String profile, int players, {int seed = 7}) => MatchHost(
  roomCode: 'TEST',
  cfg: loadProfile(profile, numPlayers: players),
  seed: seed,
  seats: [
    for (var i = 0; i < players; i++)
      SeatInfo(seat: i, name: 'Bot $i', kind: SeatKind.bot, ready: true),
  ],
  botDelay: Duration.zero,
);

void main() {
  group('bots play complete matches', () {
    for (final (profile, players) in const [
      ('buraco', 2),
      ('buraco', 4),
      ('canasta', 2),
      ('canasta', 4),
      ('biriba', 2),
      ('biriba', 4),
      ('rummy', 2),
    ]) {
      test('$profile ${players}p reaches a winner', () {
        final host = _botTable(profile, players);
        addTearDown(host.dispose);
        host.start();

        var guard = 0;
        while (!host.match.matchOver && guard++ < 200) {
          host.runBotsSynchronously();
          if (host.match.round.roundOver && !host.match.matchOver) {
            host.handle(0, const RequestNextRound());
          }
        }

        expect(
          host.match.matchOver,
          isTrue,
          reason: 'no winner after $guard rounds',
        );
        expect(host.match.winnerSide, isNotNull);
        expect(
          host.match.matchScores.reduce((a, b) => a > b ? a : b),
          greaterThanOrEqualTo(host.cfg.scoring.matchTarget),
        );
      });
    }
  });

  group('the view a seat receives leaks nothing', () {
    for (final (profile, players) in const [
      ('buraco', 2),
      ('canasta', 4),
      ('rummy', 2),
    ]) {
      test('$profile ${players}p', () {
        final host = _botTable(profile, players, seed: 21);
        addTearDown(host.dispose);
        host.start();

        // Sample views throughout a round rather than only at the deal.
        for (var step = 0; step < 40 && !host.match.round.roundOver; step++) {
          final match = host.match;
          final state = match.round;

          for (var seat = 0; seat < players; seat++) {
            final view = buildTableView(
              match,
              seat,
              playerNames: [for (final s in host.seats) s.name],
            );

            // My hand is exactly my hand.
            final expected = <CardId>[];
            state.hands[seat].forEach((ct, n) {
              for (var i = 0; i < n; i++) {
                expected.add(ct);
              }
            });
            expected.sort();
            expect(view.hand, equals(expected));

            // Only the seat to act is told what it may play.
            if (seat != state.currentPlayer) {
              expect(
                view.legalActions,
                isEmpty,
                reason: 'seat $seat learned another seat\'s moves',
              );
            }

            // The cards the view names are only ever mine or already public.
            final named = <CardId>[
              ...view.hand,
              ...view.trash,
              for (final m in view.melds) ...m.cards,
              for (final t in view.redThrees) ...t,
            ];
            final public = <CardId>[
              ...state.trash,
              for (final m in state.melds) ...m.slots.map((s) => s.card),
              for (final t in state.redThrees) ...t,
            ];
            final allowed = _counts([...expected, ...public]);
            final shown = _counts(named);
            shown.forEach((ct, n) {
              expect(
                n,
                lessThanOrEqualTo(allowed[ct] ?? 0),
                reason:
                    'seat $seat was shown a card it may not know: '
                    '${cardStr(ct)}',
              );
            });

            // Hidden zones appear as counts only, and those counts add up.
            final accountedFor =
                view.hand.length +
                view.trash.length +
                view.stockCount +
                view.melds.fold<int>(0, (a, m) => a + m.size) +
                view.redThrees.fold<int>(0, (a, t) => a + t.length) +
                view.mortoSizes.fold<int>(0, (a, n) => a + n) +
                [
                  for (var p = 0; p < players; p++)
                    if (p != seat) view.handSizes[p],
                ].fold<int>(0, (a, n) => a + n);
            expect(
              accountedFor,
              equals(host.cfg.deck.totalCards),
              reason: 'the card count seat $seat can see does not add up',
            );
          }

          // Advance one bot move and re-check.
          final seat = state.currentPlayer;
          final view = buildTableView(
            match,
            seat,
            playerNames: [for (final s in host.seats) s.name],
          );
          if (view.legalActions.isEmpty) break;
          host.handle(
            seat,
            SubmitAction(
              actionId: RandomAgent(seed: step).chooseAction(host.cfg, view),
            ),
          );
        }
      });
    }
  });

  test('conservation holds across a whole round', () {
    final host = _botTable('buraco', 4, seed: 99);
    addTearDown(host.dispose);
    host.start();
    final atDeal = dealtMultiset(host.match.round);

    var guard = 0;
    while (!host.match.round.roundOver && guard++ < 5000) {
      host.runBotsSynchronously();
    }
    expect(dealtMultiset(host.match.round), equals(atDeal));
  });

  test(
    'a local single-player table drives a real command round trip',
    () async {
      final transport = LocalTransport.singlePlayer(
        cfg: loadProfile('buraco', numPlayers: 2),
        seed: 5,
        botDelay: Duration.zero,
      );
      addTearDown(transport.dispose);

      final received = <ServerEvent>[];
      transport.events.listen(received.add);
      await transport.connect();

      transport.send(const JoinRoom(roomCode: 'LOCAL', playerName: 'Luiz'));
      transport.send(const SetReady(ready: true));
      await Future<void>.delayed(Duration.zero);

      expect(received.whereType<Joined>(), isNotEmpty);
      expect(received.whereType<LobbyUpdate>(), isNotEmpty);

      final table = received.whereType<TableUpdate>().last.view;
      expect(table.seat, equals(0));
      expect(table.myTurn, isTrue);
      expect(table.legalActions, isNotEmpty);
      expect(table.hand, hasLength(11));

      received.clear();
      transport.send(SubmitAction(actionId: table.legalActions.first));
      await Future<void>.delayed(Duration.zero);
      expect(
        received.whereType<TableUpdate>(),
        isNotEmpty,
        reason: 'the host should answer an action with a fresh view',
      );
    },
  );

  test('an illegal action is rejected, not applied', () async {
    final transport = LocalTransport.singlePlayer(
      cfg: loadProfile('buraco', numPlayers: 2),
      seed: 5,
      botDelay: Duration.zero,
    );
    addTearDown(transport.dispose);

    final received = <ServerEvent>[];
    transport.events.listen(received.add);
    await transport.connect();
    transport.send(const SetReady(ready: true));
    await Future<void>.delayed(Duration.zero);

    final before = received.whereType<TableUpdate>().last.view;
    // Discarding during the draw phase is never legal.
    final illegal = before.legalActions.contains(600) ? 601 : 600;
    received.clear();
    transport.send(SubmitAction(actionId: illegal));
    await Future<void>.delayed(Duration.zero);

    expect(received.whereType<ActionRejected>(), isNotEmpty);
    expect(transport.host.match.round.turnNumber, equals(before.turnNumber));
  });

  group('protocol survives a JSON round trip', () {
    test('commands', () {
      final commands = <ClientCommand>[
        const JoinRoom(roomCode: 'ABCD', playerName: 'Luiz', preferredSeat: 2),
        const JoinRoom(
          roomCode: 'AUTH',
          playerName: 'Ana',
          authToken: 'access-token',
          clientId: 'browser-123',
        ),
        const JoinRoom(
          roomCode: 'RECONNECT',
          playerName: 'Bruno',
          clientId: 'browser-456',
        ),
        const SetReady(ready: true),
        const SubmitAction(actionId: 233),
        const RequestNextRound(),
        const RequestRematch(),
        const LeaveRoom(),
        const JoinRoom(
          roomCode: 'RULES',
          playerName: 'Carla',
          clientId: 'browser-789',
          profileId: 'canasta',
          numPlayers: 4,
          matchTarget: 1500,
        ),
      ];
      for (final cmd in commands) {
        final wire = jsonDecode(jsonEncode(cmd.toJson()));
        final back = ClientCommand.fromJson(wire as Map<String, dynamic>);
        expect(back.runtimeType, equals(cmd.runtimeType));
        expect(back.toJson(), equals(cmd.toJson()));
      }
    });

    test('a full table view', () {
      final match = Match(cfg: loadProfile('canasta', numPlayers: 4), seed: 3);
      final view = buildTableView(
        match,
        0,
        playerNames: const ['A', 'B', 'C', 'D'],
      );
      final wire = jsonDecode(jsonEncode(TableUpdate(view: view).toJson()));
      final back = ServerEvent.fromJson(wire as Map<String, dynamic>);

      expect(back, isA<TableUpdate>());
      final restored = (back as TableUpdate).view;
      expect(restored.hand, equals(view.hand));
      expect(restored.handSizes, equals(view.handSizes));
      expect(restored.legalActions, equals(view.legalActions));
      expect(restored.redThrees, equals(view.redThrees));
      expect(restored.initialMeldMin, equals(view.initialMeldMin));
      expect(restored.toJson(), equals(view.toJson()));
    });

    test('a lobby update', () {
      const update = LobbyUpdate(
        roomCode: 'RULES',
        profile: 'canasta',
        numPlayers: 4,
        seats: [
          SeatInfo(seat: 0, name: 'Carla', kind: SeatKind.remote, ready: true),
        ],
        started: false,
        matchTarget: 1500,
      );
      final wire = jsonDecode(jsonEncode(update.toJson()));
      final back = ServerEvent.fromJson(wire as Map<String, dynamic>);

      expect(back, isA<LobbyUpdate>());
      final restored = back as LobbyUpdate;
      expect(restored.matchTarget, equals(1500));
      expect(restored.toJson(), equals(update.toJson()));
    });
  });

  group('seat takeover', () {
    test('a bot takes over a seat and the table keeps moving', () {
      final host = MatchHost(
        roomCode: 'TAKEOVER',
        cfg: loadProfile('buraco', numPlayers: 2),
        seed: 17,
        seats: const [
          SeatInfo(seat: 0, name: 'Ana', kind: SeatKind.remote, ready: true),
          SeatInfo(seat: 1, name: 'Bot 1', kind: SeatKind.bot, ready: true),
        ],
        botDelay: Duration.zero,
      );
      addTearDown(host.dispose);
      host.start();

      final actionsBefore = host.match.actionLog.length;
      host.takeOverWithBot(0);

      final takenSeat = host.seats.singleWhere((seat) => seat.seat == 0);
      expect(takenSeat.kind, SeatKind.bot);
      expect(takenSeat.ready, isTrue);

      host.runBotsSynchronously(maxActions: 100);
      expect(host.match.actionLog.length, greaterThan(actionsBefore));
    });

    test('the returning human gets the seat back', () {
      final host = MatchHost(
        roomCode: 'HAND-BACK',
        cfg: loadProfile('buraco', numPlayers: 4),
        seed: 23,
        seats: const [
          SeatInfo(seat: 0, name: 'Ana', kind: SeatKind.remote, ready: true),
          SeatInfo(seat: 1, name: 'Bot 1', kind: SeatKind.bot, ready: true),
          SeatInfo(seat: 2, name: 'Bot 2', kind: SeatKind.bot, ready: true),
          SeatInfo(seat: 3, name: 'Bruno', kind: SeatKind.remote, ready: true),
        ],
        botDelay: Duration.zero,
      );
      addTearDown(host.dispose);
      host.start();
      host.takeOverWithBot(0);

      var guard = 0;
      while (host.match.currentPlayer == 0 && guard++ < 100) {
        host.runBotsSynchronously(maxActions: 1);
      }
      expect(host.match.currentPlayer, 1);

      host.handBackSeat(0);
      final returnedSeat = host.seats.singleWhere((seat) => seat.seat == 0);
      expect(returnedSeat.kind, SeatKind.remote);
      expect(returnedSeat.connected, isTrue);

      final actionsBeforeOtherBots = host.match.actionLog.length;
      host.runBotsSynchronously(maxActions: 200);
      expect(host.match.actionLog.length, greaterThan(actionsBeforeOtherBots));
      expect(
        host.match.currentPlayer,
        3,
        reason: 'the remaining bots should still play after the hand-back',
      );
    });
  });

  group('spectator protocol additions', () {
    test('SpectateRoom round-trips with and without authentication', () {
      final commands = <SpectateRoom>[
        const SpectateRoom(roomCode: 'OPEN', clientId: 'browser-1'),
        const SpectateRoom(
          roomCode: 'AUTH',
          authToken: 'access-token',
          clientId: 'browser-2',
        ),
      ];

      for (final command in commands) {
        final wire = jsonDecode(jsonEncode(command.toJson()));
        final restored = ClientCommand.fromJson(wire as Map<String, dynamic>);
        expect(restored, isA<SpectateRoom>());
        expect(restored.toJson(), equals(command.toJson()));
      }
      expect(commands.first.toJson(), isNot(contains('authToken')));
    });

    test('Joined emits spectator only when true and round-trips it', () {
      const joined = Joined(roomCode: 'WATCH', seat: -1, spectator: true);
      final wire = jsonDecode(jsonEncode(joined.toJson()));
      final restored = ServerEvent.fromJson(wire as Map<String, dynamic>);

      expect(restored, isA<Joined>());
      expect((restored as Joined).spectator, isTrue);
      expect(restored.toJson(), equals(joined.toJson()));
      expect(
        const Joined(roomCode: 'PLAY', seat: 0).toJson(),
        isNot(contains('spectator')),
      );
    });

    test('LobbyUpdate emits a positive spectator count and round-trips it', () {
      const update = LobbyUpdate(
        roomCode: 'WATCH',
        profile: 'buraco',
        numPlayers: 2,
        seats: [],
        started: true,
        spectators: 2,
      );
      final wire = jsonDecode(jsonEncode(update.toJson()));
      final restored = ServerEvent.fromJson(wire as Map<String, dynamic>);

      expect(restored, isA<LobbyUpdate>());
      expect((restored as LobbyUpdate).spectators, equals(2));
      expect(restored.toJson(), equals(update.toJson()));
    });
  });

  test('a spectator view contains public counts but no private hand', () {
    final host = _botTable('buraco', 2, seed: 131);
    addTearDown(host.dispose);
    host.start();
    host.runBotsSynchronously(maxActions: 6);
    expect(host.match.actionLog, isNotEmpty);
    expect(host.match.round.roundOver, isFalse);

    final names = [for (final seat in host.seats) seat.name];
    final spectator = buildSpectatorView(host.match, playerNames: names);
    final seated = buildTableView(host.match, 0, playerNames: names);
    final state = host.match.round;

    expect(spectator.seat, equals(-1));
    expect(spectator.side, equals(host.cfg.table.numSides));
    expect(spectator.hand, isEmpty);
    expect(spectator.toJson()['hand'], isEmpty);
    expect(spectator.legalActions, isEmpty);
    expect(spectator.handSizes, [
      for (var seat = 0; seat < host.cfg.table.numPlayers; seat++)
        state.handSize(seat),
    ]);
    expect(spectator.stockCount, equals(state.stock.length));
    expect(spectator.mortoSizes, [
      for (final packet in state.morto) packet?.length ?? 0,
    ]);

    expect(
      spectator.melds.map((meld) => meld.toJson()),
      equals(seated.melds.map((meld) => meld.toJson())),
    );
    expect(spectator.trash, equals(seated.trash));
    expect(spectator.redThrees, equals(seated.redThrees));
    expect(spectator.publicScores, equals(seated.publicScores));
    expect(spectator.matchScores, equals(seated.matchScores));
  });
}

Map<CardId, int> _counts(List<CardId> cards) {
  final out = <CardId, int>{};
  for (final c in cards) {
    out[c] = (out[c] ?? 0) + 1;
  }
  return out;
}
