/// Renders the screens to PNGs under `test/goldens/`.
///
/// Run with `flutter test --update-goldens test/golden_test.dart` to refresh
/// them after a visual change, then look at the files. They are review aids
/// first and regression guards second, so they are tagged and excluded from the
/// default run — font rasterisation differs enough between machines that
/// failing CI on a pixel would be noise.
@Tags(['golden'])
library;

import 'package:canastra/ai/agent.dart';
import 'package:canastra/engine/profiles.dart';
import 'package:canastra/game/game_controller.dart';
import 'package:canastra/multiplayer/local_transport.dart';
import 'package:canastra/ui/screens/game_screen.dart';
import 'package:canastra/ui/screens/home_screen.dart';
import 'package:canastra/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFonts() async {
  for (final family in const {
    'Archivo': ['assets/fonts/Archivo.ttf'],
    'DMMono': ['assets/fonts/DMMono-Regular.ttf', 'assets/fonts/DMMono-Medium.ttf'],
  }.entries) {
    final loader = FontLoader(family.key);
    for (final path in family.value) {
      loader.addFont(rootBundle.load(path));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget child, {
    Size size = const Size(430, 932),
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), debugShowCheckedModeBanner: false, home: child));
    await tester.pump(const Duration(milliseconds: 60));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('setup', (tester) async {
    await shoot(tester, 'setup', const HomeScreen());
  });

  testWidgets('table', (tester) async {
    final cfg = loadProfile('buraco', numPlayers: 4);
    final transport = LocalTransport.singlePlayer(
      cfg: cfg,
      seed: 12,
      botLevel: AgentLevel.normal,
      botDelay: Duration.zero,
    );
    final controller = GameController(cfg: cfg, transport: transport);
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(430, 932) * 2;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(
            theme: buildTheme(),
            debugShowCheckedModeBanner: false,
            home: GameScreen(controller: controller)));
    await tester.pump(const Duration(milliseconds: 60));

    // Play a few turns so the table has melds on it, then pick up a card so the
    // legal-destination highlighting shows.
    controller.playId(0); // draw
    await tester.pump();
    for (var i = 0; i < 60 && controller.view!.phase == 'play'; i++) {
      final creates = controller.moves.options
          .where((o) => o.label.startsWith('New'))
          .toList();
      if (creates.isEmpty) break;
      controller.play(creates.first);
      await tester.pump();
    }
    if (controller.moves.playableCards.isNotEmpty) {
      controller.selectCard(controller.moves.playableCards.first);
    }
    await tester.pump(const Duration(milliseconds: 600));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/table.png'),
    );
  });

  testWidgets('table on a wide screen', (tester) async {
    final cfg = loadProfile('canasta', numPlayers: 2);
    final controller = GameController(
      cfg: cfg,
      transport: LocalTransport.singlePlayer(
          cfg: cfg, seed: 3, botDelay: Duration.zero),
    );
    addTearDown(controller.dispose);
    await shoot(tester, 'table_wide', GameScreen(controller: controller),
        size: const Size(1200, 820));
  });
}
