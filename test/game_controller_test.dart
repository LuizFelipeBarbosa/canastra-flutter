/// Tests for the controller's command queue and local selection lifecycle.
///
/// The controller still talks through a real [LocalTransport] and [MatchHost].
/// The small wrapper below can hold a host response long enough to exercise the
/// narrow intervals that exist on a network connection.
library;

import 'dart:async';

import 'package:canastra/engine/cards.dart';
import 'package:canastra/engine/config.dart';
import 'package:canastra/engine/meld.dart';
import 'package:canastra/engine/profiles.dart';
import 'package:canastra/engine/state.dart';
import 'package:canastra/game/game_controller.dart';
import 'package:canastra/game/selection_plan.dart';
import 'package:canastra/multiplayer/local_transport.dart';
import 'package:canastra/multiplayer/match_host.dart';
import 'package:canastra/multiplayer/protocol.dart';
import 'package:canastra/multiplayer/table_view.dart';
import 'package:canastra/multiplayer/transport.dart';
import 'package:flutter_test/flutter_test.dart';

const aceClubs = 0;
const fiveClubs = 4;
const sixClubs = 5;
const sevenClubs = 6;
const eightClubs = 7;
const nineClubs = 8;
const twoDiamonds = 14;
const kingClubs = 12;
const kingDiamonds = 25;
const kingHearts = 38;
const aceSpades = 39;
const kingSpades = 51;

const ballast = [aceSpades, kingSpades];

class _TestTransport implements GameTransport {
  final LocalTransport _delegate;
  final StreamController<ServerEvent> _events =
      StreamController<ServerEvent>.broadcast();
  final List<ServerEvent> _held = [];

  StreamSubscription<ServerEvent>? _subscription;
  bool holdEvents = false;
  bool throwOnSend = false;
  int submitCount = 0;

  _TestTransport(MatchHost host)
    : _delegate = LocalTransport(host: host, mySeat: 0);

  @override
  Stream<ServerEvent> get events => _events.stream;

  @override
  int? get seat => _delegate.seat;

  @override
  bool get isConnected => _delegate.isConnected;

  @override
  Future<void> connect() async {
    _subscription ??= _delegate.events.listen((event) {
      if (holdEvents) {
        _held.add(event);
      } else {
        _events.add(event);
      }
    });
    await _delegate.connect();
  }

  @override
  void send(ClientCommand command) {
    if (throwOnSend) throw TransportException('down');
    if (command is SubmitAction) submitCount += 1;
    _delegate.send(command);
  }

  /// Drop the held stale response and deliver the authoritative view supplied
  /// by the test, as a server reconnect or intervening table update could.
  void replaceHeldWith(TableView view) {
    _held.clear();
    holdEvents = false;
    _events.add(TableUpdate(view: view));
  }

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    await _delegate.dispose();
    await _events.close();
  }
}

class _Table {
  final RulesConfig cfg;
  final MatchHost host;
  final _TestTransport transport;
  final GameController controller;

  const _Table({
    required this.cfg,
    required this.host,
    required this.transport,
    required this.controller,
  });
}

Future<void> _settle() async {
  // Host, local transport, wrapper and controller each add one asynchronous
  // stream hop. Several zero-duration turns also let a queued plan fully drain.
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<_Table> _table({
  String profile = 'buraco',
  RulesConfig? config,
  required void Function(MatchHost host) rig,
}) async {
  final cfg = config ?? loadProfile(profile, numPlayers: 2);
  final host = MatchHost(
    roomCode: 'TEST',
    cfg: cfg,
    seed: 3,
    seats: const [
      SeatInfo(seat: 0, name: 'You', kind: SeatKind.human),
      SeatInfo(seat: 1, name: 'Bruno', kind: SeatKind.bot, ready: true),
    ],
    botDelay: Duration.zero,
  );
  rig(host);

  final transport = _TestTransport(host);
  final controller = GameController(cfg: cfg, transport: transport);
  await controller.start();
  await _settle();
  expect(controller.view, isNotNull, reason: 'the host should have dealt');

  addTearDown(() async {
    controller.dispose();
    await _settle();
  });
  return _Table(
    cfg: cfg,
    host: host,
    transport: transport,
    controller: controller,
  );
}

void _setPlayHand(MatchHost host, Iterable<CardId> cards) {
  final state = host.match.round;
  final hand = state.hands[0]..clear();
  for (final card in cards) {
    hand[card] = (hand[card] ?? 0) + 1;
  }
  state
    ..currentPlayer = 0
    ..phase = Phase.play;
}

void main() {
  test(
    'a queued multi-step meld drains as authoritative views return',
    () async {
      final run = [fiveClubs, sixClubs, sevenClubs, eightClubs, nineClubs];
      final table = await _table(
        rig: (host) => _setPlayHand(host, [...run, ...ballast]),
      );

      for (final card in run) {
        table.controller.toggleCard(card);
      }
      table.controller.meldSelection();
      expect(table.controller.busy, isTrue);

      await _settle();
      expect(table.controller.busy, isFalse);
      expect(table.controller.selection, isEmpty);
      expect(table.controller.view!.myMelds.single.size, equals(5));
      expect(table.transport.submitCount, equals(3));
    },
  );

  test(
    'a live-view change drops a stale plan and retains unplayed cards',
    () async {
      final run = [fiveClubs, sixClubs, sevenClubs, eightClubs, nineClubs];
      final table = await _table(
        rig: (host) => _setPlayHand(host, [...run, ...ballast]),
      );
      for (final card in run) {
        table.controller.toggleCard(card);
      }

      table.transport.holdEvents = true;
      table.controller.meldSelection();
      expect(table.controller.busy, isTrue);

      // The create has reached the host, but its response is held. Model an
      // intervening authoritative restriction before the controller sees a view:
      // the next queued add is no longer in that view's legal-action list.
      table.host.match.round.pendingPileCard = aceSpades;
      await _settle();
      table.transport.replaceHeldWith(
        buildTableView(
          table.host.match,
          0,
          playerNames: const ['You', 'Bruno'],
        ),
      );
      await _settle();

      expect(table.controller.busy, isFalse);
      expect(
        table.controller.selection,
        equals([eightClubs, nineClubs]),
        reason: 'cards the accepted create did not spend stay selected',
      );
      expect(table.controller.refusal, equals(Refusal.notAllowedYet));
    },
  );

  test('busy blocks both toggling and clearing the selection', () async {
    final run = [fiveClubs, sixClubs, sevenClubs, eightClubs, nineClubs];
    final table = await _table(
      rig: (host) => _setPlayHand(host, [...run, ...ballast]),
    );
    for (final card in run) {
      table.controller.toggleCard(card);
    }

    table.controller.meldSelection();
    expect(table.controller.busy, isTrue);
    final selected = table.controller.selection;

    table.controller.toggleCard(aceSpades);
    table.controller.clearSelection();
    expect(table.controller.selection, equals(selected));

    await _settle();
  });

  test('both copies of a twice-held card can be picked up', () async {
    final table = await _table(
      rig: (host) => _setPlayHand(host, [fiveClubs, fiveClubs, ...ballast]),
    );
    final controller = table.controller;

    // The table reports which copy a tap landed on: a copy still resting in
    // the hand picks up, a lifted one goes back down. Tapping the second
    // resting copy must add it, not put its twin back down.
    controller.toggleCard(fiveClubs, selected: false, copy: 0);
    expect(controller.selection, equals([fiveClubs]));

    controller.toggleCard(fiveClubs, selected: false, copy: 1);
    expect(controller.selection, equals([fiveClubs, fiveClubs]));

    controller.toggleCard(fiveClubs, selected: true, copy: 0);
    expect(controller.selection, equals([fiveClubs]));

    controller.toggleCard(fiveClubs, selected: true, copy: 1);
    expect(controller.selection, isEmpty);
  });

  test('tapping the second twin lifts that copy, not the first', () async {
    final table = await _table(
      rig: (host) => _setPlayHand(host, [fiveClubs, fiveClubs, ...ballast]),
    );
    final controller = table.controller;

    controller.toggleCard(fiveClubs, selected: false, copy: 1);
    expect(controller.picked, equals([(ct: fiveClubs, copy: 1)]));

    // Putting the untouched first copy's twin down leaves nothing lifted.
    controller.toggleCard(fiveClubs, selected: true, copy: 1);
    expect(controller.picked, isEmpty);
  });

  test(
    'a duplicate single-step submission is ignored until a view arrives',
    () async {
      final table = await _table(
        rig: (host) => _setPlayHand(host, [fiveClubs, ...ballast]),
      );
      final turn = table.controller.view!.turnNumber;
      table.controller.toggleCard(fiveClubs);

      table.controller.discardSelection();
      table.controller.discardSelection();
      expect(table.transport.submitCount, equals(1));

      await _settle();
      expect(table.controller.notice, isNull);
      expect(table.controller.view!.turnNumber, equals(turn + 1));
      expect(table.host.match.round.trash.last, equals(fiveClubs));
    },
  );

  test(
    'a synchronous send failure does not block the next submission',
    () async {
      final table = await _table(
        rig: (host) => _setPlayHand(host, [fiveClubs, ...ballast]),
      );
      table.controller.toggleCard(fiveClubs);
      table.transport.throwOnSend = true;

      expect(table.controller.discardSelection, returnsNormally);
      expect(table.controller.notice, equals('down'));
      expect(table.controller.busy, isFalse);
      expect(table.transport.submitCount, isZero);

      table.transport.throwOnSend = false;
      table.controller.discardSelection();
      expect(table.transport.submitCount, equals(1));

      await _settle();
      expect(table.host.match.round.trash.last, equals(fiveClubs));
    },
  );

  test(
    'a synchronous queued send failure drops the plan for a retry',
    () async {
      final run = [fiveClubs, sixClubs, sevenClubs, eightClubs, nineClubs];
      final table = await _table(
        rig: (host) => _setPlayHand(host, [...run, ...ballast]),
      );
      for (final card in run) {
        table.controller.toggleCard(card);
      }
      table.transport.throwOnSend = true;

      expect(table.controller.meldSelection, returnsNormally);
      expect(table.controller.notice, equals('down'));
      expect(table.controller.busy, isFalse);
      expect(table.transport.submitCount, isZero);

      table.transport.throwOnSend = false;
      table.controller.meldSelection();
      await _settle();

      expect(table.controller.busy, isFalse);
      expect(table.controller.selection, isEmpty);
      expect(table.controller.view!.myMelds.single.size, equals(5));
      expect(table.transport.submitCount, equals(3));
    },
  );

  test('a direct morto refill does not reattach old selection types', () async {
    final run = [fiveClubs, sixClubs, sevenClubs, eightClubs, nineClubs];
    final table = await _table(
      rig: (host) {
        _setPlayHand(host, run);
        host.match.round.morto[0] = [nineClubs, aceSpades, kingSpades];
        host.match.round.mortoTaken[0] = false;
      },
    );
    for (final card in run) {
      table.controller.toggleCard(card);
    }

    table.controller.meldSelection();
    await _settle();

    expect(table.controller.view!.mortoTaken[0], isTrue);
    expect(table.controller.view!.hand, contains(nineClubs));
    expect(
      table.controller.selection,
      isEmpty,
      reason: 'the new nine came from the morto and was never selected',
    );
  });

  test(
    'discarding the just-bought sole pile card is refused as such',
    () async {
      final table = await _table(
        rig: (host) {
          _setPlayHand(host, [kingHearts, fiveClubs, ...ballast]);
          host.match.round.boughtSolePileCard = kingHearts;
        },
      );
      table.controller.toggleCard(kingHearts);

      table.controller.discardSelection();
      expect(table.controller.refusal, equals(Refusal.justBought));
      expect(table.transport.submitCount, isZero);
    },
  );

  test(
    'discarding the sole remaining bought card reports the going-out refusal',
    () async {
      final table = await _table(
        rig: (host) {
          _setPlayHand(host, [kingHearts]);
          host.match.round
            ..boughtSolePileCard = kingHearts
            ..mortoTaken[0] = true;
        },
      );
      table.controller.toggleCard(kingHearts);

      table.controller.discardSelection();
      expect(table.controller.refusal, equals(Refusal.needCanastra));
      expect(table.controller.refusal, isNot(Refusal.justBought));
      expect(table.transport.submitCount, isZero);
    },
  );

  test('dirty canastras do not satisfy a clean-canastra requirement', () async {
    final base = loadProfile('buraco', numPlayers: 2);
    final cleanRequired = RulesConfig(
      name: base.name,
      table: base.table,
      deck: base.deck,
      wildcard: base.wildcard,
      meld: base.meld,
      morto: base.morto,
      discardPile: base.discardPile,
      goingOut: GoingOutConfig(
        requireCanastra: base.goingOut.requireCanastra,
        requireCleanCanastra: true,
        requireMortoTaken: base.goingOut.requireMortoTaken,
        discardToGoOut: base.goingOut.discardToGoOut,
        goOutBonus: base.goingOut.goOutBonus,
        concealedBonus: base.goingOut.concealedBonus,
        goOutMinCanastras: base.goingOut.goOutMinCanastras,
      ),
      initialMeld: base.initialMeld,
      specialThrees: base.specialThrees,
      scoring: base.scoring,
      turn: base.turn,
    );
    final table = await _table(
      config: cleanRequired,
      rig: (host) {
        _setPlayHand(host, [aceClubs]);
        final state = host.match.round;
        state.morto[0] = null;
        state.mortoTaken[0] = true;
        state.melds.add(
          Meld(
            meldId: 0,
            owner: 0,
            kind: MeldKind.set,
            rank: Rank.king,
            slots: [
              Slot(kingClubs, SlotRole.natural),
              Slot(kingDiamonds, SlotRole.natural),
              Slot(kingHearts, SlotRole.natural),
              Slot(kingSpades, SlotRole.natural),
              Slot(kingClubs, SlotRole.natural),
              Slot(kingDiamonds, SlotRole.natural),
              Slot(twoDiamonds, SlotRole.wild),
            ],
          ),
        );
      },
    );
    table.controller.toggleCard(aceClubs);

    expect(table.controller.view!.myMelds.single.isCanastra, isTrue);
    expect(table.controller.view!.myMelds.single.isClean, isFalse);
    expect(table.controller.discardGoesOut, isFalse);
    expect(table.controller.goOutRefusal, equals(Refusal.needCanastra));
  });
}
