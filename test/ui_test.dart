/// Smoke tests for the screens.
///
/// Flutter reports overflows and layout failures as test exceptions, so pumping
/// each screen catches the class of bug that static analysis cannot see.
///
/// Every screen is laid out at one fixed size and scaled to fit, so the interesting
/// axis is no longer the viewport — it is the *content*: a hand of 15 rather than
/// 11, four seats rather than two, a row of melds long enough to crowd the play
/// area. Those are what can still overflow, so those are what is pumped here.
library;

import 'package:canastra/ai/agent.dart';
import 'package:canastra/engine/profiles.dart';
import 'package:canastra/game/game_controller.dart';
import 'package:canastra/game/move_index.dart';
import 'package:canastra/multiplayer/local_transport.dart';
import 'package:canastra/ui/app_scope.dart';
import 'package:canastra/ui/screens/game_screen.dart';
import 'package:canastra/ui/screens/landing_screen.dart';
import 'package:canastra/ui/screens/setup_screen.dart';
import 'package:canastra/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Life size, where the stage does not scale at all.
const _desktop = Size(1280, 820);

/// Small enough in portrait that the table asks to be rotated.
const _phone = Size(390, 844);

Future<AppPrefs> _pumpAt(
  WidgetTester tester,
  Size size,
  Widget child, {
  bool dark = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final prefs = AppPrefs();
  if (prefs.dark != dark) prefs.toggleTheme();
  await tester.pumpWidget(
    AppScope(
      prefs: prefs,
      child: ListenableBuilder(
        listenable: prefs,
        builder: (context, _) => MaterialApp(
          theme: buildTheme(prefs.palette, dark: prefs.dark),
          home: child,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  return prefs;
}

/// A controller on a local single-player table, dealt and ready.
///
/// [botDelay] defaults to zero, which the host reads as "manual" — nothing is
/// scheduled and the opponent never moves. That is what a layout test wants. A
/// test that needs the opponent to actually play passes a delay short enough to
/// fire on the next pump.
Future<GameController> _dealt(
  WidgetTester tester,
  String profileId, {
  int? numPlayers,
  int seed = 4,
  Duration botDelay = Duration.zero,
}) async {
  final cfg = loadProfile(profileId, numPlayers: numPlayers);
  final controller = GameController(
    cfg: cfg,
    transport: LocalTransport.singlePlayer(
      cfg: cfg,
      seed: seed,
      botLevel: AgentLevel.normal,
      botDelay: botDelay,
    ),
  );
  return controller;
}

void main() {
  for (final (name, size) in const [
    ('life size', _desktop),
    ('a phone', _phone),
  ]) {
    testWidgets('the landing screen lays out at $name', (tester) async {
      final prefs = await _pumpAt(tester, size, const LandingScreen());
      if (size == _phone) {
        expect(find.text(prefs.copy.rotatePrompt), findsOneWidget);
        expect(find.text('Play now'), findsNothing);
      } else {
        expect(find.text('BURACO'), findsOneWidget);
        expect(find.text('LIVRE'), findsOneWidget);
        expect(find.text('Play now'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the setup screen lays out at $name', (tester) async {
      final prefs = await _pumpAt(tester, size, const SetupScreen());
      if (size == _phone) {
        expect(find.text(prefs.copy.rotatePrompt), findsOneWidget);
        expect(find.text('Deal'), findsNothing);
      } else {
        expect(find.text('Set the table'), findsOneWidget);
        expect(find.text('Deal'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('popping the game screen disposes its session', (tester) async {
    final controller = await _dealt(
      tester,
      'buraco',
      botDelay: const Duration(milliseconds: 400),
    );
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    late BuildContext homeContext;
    await _pumpAt(
      tester,
      _desktop,
      Builder(
        builder: (context) {
          homeContext = context;
          return const Scaffold(body: SizedBox());
        },
      ),
    );
    Navigator.of(homeContext).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(controller: controller),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    controller.play(controller.moves.firstWithTarget(MoveTarget.stock)!);
    await tester.pump();
    controller.play(
      controller.moves.options.firstWhere(
        (move) => move.target == MoveTarget.discard,
      ),
    );
    await tester.pump();
    expect(controller.myTurn, isFalse);

    Navigator.of(tester.element(find.byType(GameScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(GameScreen), findsNothing);

    final notificationsAfterPop = notifications;
    await tester.pump(const Duration(seconds: 1));
    expect(notifications, notificationsAfterPop);
    expect(tester.takeException(), isNull);
  });

  testWidgets('double-tapping Deal pushes one game screen', (tester) async {
    await _pumpAt(tester, _desktop, const SetupScreen());

    await tester.tap(find.text('Deal'));
    await tester.tap(find.text('Deal'));
    await tester.pump();

    expect(find.byType(GameScreen, skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The pushed table starts its own deal-animation timer (and, if it were
    // the bot's turn, a bot-move timer too); the test must let it run to
    // completion or flutter_test's own teardown flags it as a Timer still
    // pending, unrelated to what this test is actually checking.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the game asks for rotation only in tiny portrait', (
    tester,
  ) async {
    final controller = await _dealt(tester, 'buraco');
    final prefs = await _pumpAt(
      tester,
      _phone,
      GameScreen(controller: controller),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(find.text(prefs.copy.rotatePrompt), findsOneWidget);
    expect(find.text(prefs.copy.stock), findsNothing);

    tester.view.physicalSize = _desktop;
    await tester.pump();

    expect(find.text(prefs.copy.rotatePrompt), findsNothing);
    expect(find.text(prefs.copy.stock), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Content, not viewport: Buraco deals 11, two-handed Canasta deals 15, and a
  // four-handed table puts three opponents and two sides of melds on the felt.
  for (final (profile, players) in const [
    ('buraco', 2),
    ('canasta', 2),
    ('buraco', 4),
    ('rummy', 2),
  ]) {
    testWidgets('the $players-handed $profile table lays out', (tester) async {
      final controller = await _dealt(tester, profile, numPlayers: players);
      await _pumpAt(tester, _desktop, GameScreen(controller: controller));
      // Let the deal animation run to the end.
      await tester.pump(const Duration(seconds: 2));

      expect(controller.view, isNotNull, reason: 'the host should have dealt');
      expect(find.text(profile.toUpperCase()), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the light table lays out too', (tester) async {
    final controller = await _dealt(tester, 'buraco');
    await _pumpAt(
      tester,
      _desktop,
      GameScreen(controller: controller),
      dark: false,
    );
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking a variant reveals what makes it different', (
    tester,
  ) async {
    final prefs = await _pumpAt(tester, _desktop, const LandingScreen());
    expect(prefs.variant, equals('buraco'));

    await tester.tap(find.text('Rummy'));
    await tester.pumpAndSettle();

    expect(prefs.variant, equals('rummy'));
    expect(find.textContaining('One deck, no morto'), findsOneWidget);
    // Only the chosen variant explains itself.
    expect(find.textContaining('twos are wild'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the language toggle rewrites the screen', (tester) async {
    await _pumpAt(tester, _desktop, const LandingScreen());
    expect(find.text('Play now'), findsOneWidget);

    await tester.tap(find.text('PT'));
    await tester.pumpAndSettle();

    expect(find.text('Jogar agora'), findsOneWidget);
    expect(find.text('Play now'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a whole round plays out and the sheet offers the next', (
    tester,
  ) async {
    final controller = await _dealt(
      tester,
      'buraco',
      seed: 21,
      botDelay: const Duration(milliseconds: 1),
    );
    await _pumpAt(tester, _desktop, GameScreen(controller: controller));
    await tester.pump(const Duration(seconds: 2));

    // Take every legal move the host offers until the round ends. Not a strategy —
    // the point is that the screen survives a whole round of real states.
    var guard = 0;
    while (!controller.view!.roundOver && guard++ < 3000) {
      final moves = controller.moves.options;
      if (moves.isNotEmpty) {
        // Prefer a discard, so turns actually pass and the round terminates.
        controller.play(
          moves.lastWhere(
            (m) => m.target == MoveTarget.discard,
            orElse: () => moves.first,
          ),
        );
      }
      // An empty move list means it is the opponent's turn; pump and wait.
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.view!.roundOver, isTrue, reason: 'round never ended');

    // The sheet deliberately waits for the last card to land before covering the
    // table, then rises — so it needs a pump for the delay and a pump for the
    // animation before anything of it is on screen.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 400));

    // Playing blind can occasionally settle the whole match in one round.
    final onward = controller.view!.matchOver
        ? 'New match'
        : 'Deal the next round';
    expect(find.text(onward), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text(onward));
    await tester.pump(const Duration(seconds: 2));
    expect(controller.view!.roundOver, isFalse, reason: 'a new round is dealt');
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking cards up and putting them down again', (tester) async {
    final controller = await _dealt(tester, 'buraco', seed: 11);
    await _pumpAt(tester, _desktop, GameScreen(controller: controller));
    await tester.pump(const Duration(seconds: 2));

    // Draw first — you cannot play anything until the draw is done.
    expect(controller.view!.phase, equals('draw'));
    controller.playId(0); // DRAW_DECK
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.view!.phase, equals('play'));

    final card = controller.view!.hand.first;
    controller.toggleCard(card);
    await tester.pump();
    expect(controller.selection, equals([card]));

    controller.toggleCard(card);
    await tester.pump();
    expect(controller.selection, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
