/// Renders the screens to PNGs under `test/goldens/`.
///
/// Run with `flutter test --run-skipped --update-goldens test/golden_test.dart` to refresh them
/// after a visual change, then look at the files. They are review aids first and
/// regression guards second, so they are tagged and excluded from the default run —
/// font rasterisation differs enough between machines that failing CI on a pixel
/// would be noise.
///
/// Both tables are shot, because the light one is a real second theme rather than
/// an inversion and can break on its own.
@Tags(['golden'])
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
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The stage's own size, so a golden is pixel-for-pixel with the design.
const _stage = Size(1280, 820);

Future<void> _loadFonts() async {
  for (final family in const {
    'Archivo': ['assets/fonts/Archivo.ttf'],
    'DMMono': [
      'assets/fonts/DMMono-Regular.ttf',
      'assets/fonts/DMMono-Medium.ttf',
    ],
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

  Future<AppPrefs> mount(
    WidgetTester tester,
    Widget child, {
    Size size = _stage,
    bool dark = true,
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2.0;
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
            debugShowCheckedModeBanner: false,
            home: child,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    return prefs;
  }

  Future<void> shoot(WidgetTester tester, String name) => expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );

  testWidgets('landing', (tester) async {
    await mount(tester, const LandingScreen());
    await shoot(tester, 'landing');
  });

  testWidgets('landing on the sun table', (tester) async {
    await mount(tester, const LandingScreen(), dark: false);
    await shoot(tester, 'landing_light');
  });

  testWidgets('setup', (tester) async {
    await mount(tester, const SetupScreen());
    await shoot(tester, 'setup');
  });

  /// A table with melds on it and a run half-selected, which is the state the
  /// design is really about: something picked up, and everywhere it can go lit.
  Future<GameController> playedOut(WidgetTester tester, String profile) async {
    final cfg = loadProfile(profile, numPlayers: 2);
    final controller = GameController(
      cfg: cfg,
      transport: LocalTransport.singlePlayer(
        cfg: cfg,
        seed: 12,
        botLevel: AgentLevel.normal,
        botDelay: Duration.zero,
      ),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<void> playAFewMelds(
    WidgetTester tester,
    GameController controller,
  ) async {
    // Skip the deal animation.
    await tester.pump(const Duration(seconds: 2));
    controller.playId(0); // draw
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      final creates = controller.moves.options
          .where((o) => o.label.startsWith('New'))
          .toList();
      if (creates.isEmpty) break;
      controller.play(creates.first);
      await tester.pump();
    }
    // Pick a card up so the legal destinations light.
    if (controller.view!.hand.isNotEmpty) {
      controller.toggleCard(controller.view!.hand.first);
    }
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('table', (tester) async {
    final controller = await playedOut(tester, 'buraco');
    await mount(tester, GameScreen(controller: controller));
    await playAFewMelds(tester, controller);
    await shoot(tester, 'table');
  });

  testWidgets('table on the sun table', (tester) async {
    final controller = await playedOut(tester, 'buraco');
    await mount(tester, GameScreen(controller: controller), dark: false);
    await playAFewMelds(tester, controller);
    await shoot(tester, 'table_light');
  });

  testWidgets('round sheet', (tester) async {
    final cfg = loadProfile('buraco', numPlayers: 2);
    final controller = GameController(
      cfg: cfg,
      transport: LocalTransport.singlePlayer(
        cfg: cfg,
        seed: 21,
        botLevel: AgentLevel.normal,
        // Non-zero, or the host leaves bots in manual mode and nobody moves.
        botDelay: const Duration(milliseconds: 1),
      ),
    );
    addTearDown(controller.dispose);
    await mount(tester, GameScreen(controller: controller));
    await tester.pump(const Duration(seconds: 2));

    var guard = 0;
    while (!controller.view!.roundOver && guard++ < 3000) {
      final moves = controller.moves.options;
      if (moves.isNotEmpty) {
        controller.play(
          moves.lastWhere(
            (m) => m.target == MoveTarget.discard,
            orElse: () => moves.first,
          ),
        );
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Past the sheet's hold and its rise.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 400));
    await shoot(tester, 'round_sheet');
  });
}
