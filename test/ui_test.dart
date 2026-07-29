/// Smoke tests for the screens.
///
/// Flutter reports overflows and layout failures as test exceptions, so pumping
/// each screen at a small phone and a wide desktop catches the class of bug
/// that static analysis cannot see. Buraco deals 11 cards and Canasta 15, so
/// the narrow case is the one that matters.
library;

import 'package:canastra/ai/agent.dart';
import 'package:canastra/engine/profiles.dart';
import 'package:canastra/game/game_controller.dart';
import 'package:canastra/multiplayer/local_transport.dart';
import 'package:canastra/ui/screens/game_screen.dart';
import 'package:canastra/ui/screens/home_screen.dart';
import 'package:canastra/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _phone = Size(390, 844); // iPhone 14
const _small = Size(320, 640); // the narrowest we support
const _desktop = Size(1280, 900);

Future<void> _pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: child));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  for (final (name, size) in const [
    ('a small phone', _small),
    ('a phone', _phone),
    ('a desktop', _desktop),
  ]) {
    testWidgets('the setup screen lays out on $name', (tester) async {
      await _pumpAt(tester, size, const HomeScreen());
      expect(find.text('CANASTRA'), findsOneWidget);
      expect(find.text('Deal'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the table lays out on $name', (tester) async {
      final cfg = loadProfile('canasta', numPlayers: 4); // 15-card hands
      final controller = GameController(
        cfg: cfg,
        transport: LocalTransport.singlePlayer(
          cfg: cfg,
          seed: 4,
          botLevel: AgentLevel.normal,
          botDelay: Duration.zero,
        ),
      );
      addTearDown(controller.dispose);

      await _pumpAt(tester, size, GameScreen(controller: controller));
      await tester.pump(const Duration(milliseconds: 100));

      expect(controller.view, isNotNull, reason: 'the host should have dealt');
      expect(find.text('CANASTA'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('picking a variant reveals what makes it different',
      (tester) async {
    await _pumpAt(tester, _phone, const HomeScreen());
    await tester.tap(find.text('Rummy'));
    await tester.pumpAndSettle();

    expect(find.textContaining('One deck, no wilds'), findsOneWidget);
    // Rummy is two-player only, so the table size must have followed along.
    expect(find.text('4 · TWO TEAMS'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a card offers only moves that spend it', (tester) async {
    final cfg = loadProfile('buraco', numPlayers: 2);
    final controller = GameController(
      cfg: cfg,
      transport: LocalTransport.singlePlayer(
        cfg: cfg,
        seed: 11,
        botDelay: Duration.zero,
      ),
    );
    addTearDown(controller.dispose);

    await _pumpAt(tester, _phone, GameScreen(controller: controller));
    await tester.pump(const Duration(milliseconds: 100));

    // Draw first — nothing in hand is playable until the draw is done.
    expect(controller.view!.phase, equals('draw'));
    controller.playId(0); // DRAW_DECK
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.view!.phase, equals('play'));

    final card = controller.moves.playableCards.first;
    controller.selectCard(card);
    await tester.pump();

    expect(controller.selectedCard, equals(card));
    for (final move in controller.moves.forCard(card)) {
      expect(move.consumes, contains(card));
    }
    expect(tester.takeException(), isNull);
  });
}
