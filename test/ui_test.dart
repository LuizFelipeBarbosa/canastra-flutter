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

import 'package:canastra/account/account.dart';
import 'package:canastra/account/auth_backend.dart';
import 'package:canastra/account/fake_auth_backend.dart';
import 'package:canastra/ai/agent.dart';
import 'package:canastra/engine/cards.dart';
import 'package:canastra/engine/profiles.dart';
import 'package:canastra/game/game_controller.dart';
import 'package:canastra/game/move_index.dart';
import 'package:canastra/multiplayer/local_transport.dart';
import 'package:canastra/multiplayer/table_view.dart';
import 'package:canastra/ui/account_scope.dart';
import 'package:canastra/ui/app_scope.dart';
import 'package:canastra/ui/copy.dart';
import 'package:canastra/ui/screens/friends_screen.dart';
import 'package:canastra/ui/screens/game_screen.dart';
import 'package:canastra/ui/screens/history_screen.dart';
import 'package:canastra/ui/screens/landing_screen.dart';
import 'package:canastra/ui/screens/leaderboard_screen.dart';
import 'package:canastra/ui/screens/online_screen.dart';
import 'package:canastra/ui/screens/otp_screen.dart';
import 'package:canastra/ui/screens/profile_screen.dart';
import 'package:canastra/ui/screens/queue_screen.dart';
import 'package:canastra/ui/screens/setup_screen.dart';
import 'package:canastra/ui/screens/sign_in_screen.dart';
import 'package:canastra/ui/theme.dart';
import 'package:canastra/ui/widgets/meld_box.dart';
import 'package:canastra/ui/widgets/playing_card.dart';
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
  Account? account,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final prefs = AppPrefs();
  if (prefs.dark != dark) prefs.toggleTheme();
  await tester.pumpWidget(
    AppScope(
      prefs: prefs,
      child: AccountScope(
        account: account ?? Account(backend: FakeAuthBackend()),
        child: ListenableBuilder(
          listenable: prefs,
          builder: (context, _) => MaterialApp(
            theme: buildTheme(prefs.palette, dark: prefs.dark),
            home: child,
          ),
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
  int? matchTarget,
}) async {
  final profile = loadProfile(profileId, numPlayers: numPlayers);
  final cfg = matchTarget == null
      ? profile
      : profile.withMatchTarget(matchTarget);
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

Future<void> _finishRound(
  WidgetTester tester,
  GameController controller,
) async {
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
}

String _semanticsLabel(WidgetTester tester, Finder widget) {
  final semantics = find.descendant(
    of: widget,
    matching: find.byType(Semantics),
  );
  return tester.widget<Semantics>(semantics.first).properties.label!;
}

void main() {
  test('count-aware copy follows each language naturally', () {
    final en = Copy.of(Lang.en);
    final pt = Copy.of(Lang.pt);

    expect(en.spotsOpen(1), '1 SPOT OPEN FOR WHAT YOU HOLD');
    expect(en.spotsOpen(2), '2 SPOTS OPEN FOR WHAT YOU HOLD');
    expect(pt.spotsOpen(1), '1 LUGAR ABERTO PARA O QUE VOCÊ TEM');
    expect(pt.spotsOpen(2), '2 LUGARES ABERTOS PARA O QUE VOCÊ TEM');
    expect(en.countLeft(24), '24 left');
    expect(pt.countLeft(1), 'resta 1');
    expect(pt.countLeft(24), 'restam 24');
  });

  test('an unknown variant gets a readable localized fallback', () {
    final en = variantCopy(Lang.en, 'house_rules');
    final pt = variantCopy(Lang.pt, 'house_rules');

    expect(en.tagline, 'HOUSE RULES');
    expect(en.blurb, 'A custom house rules variant.');
    expect(pt.tagline, 'HOUSE RULES');
    expect(pt.blurb, 'Uma variante personalizada de house rules.');
  });

  testWidgets('card and meld semantics follow the language toggle', (
    tester,
  ) async {
    // ensureSemantics()'s handle must be disposed inside the test body: Flutter's
    // own end-of-test verification for stray SemanticsHandles runs before
    // addTearDown callbacks would fire, so disposing it there is too late.
    final semantics = tester.ensureSemantics();
    final run = MeldView(
      owner: 0,
      isSequence: true,
      suit: Suit.hearts,
      rank: null,
      startPos: 2,
      cards: [
        cardId(Rank.two, Suit.hearts),
        cardId(Rank.three, Suit.hearts),
        cardId(Rank.four, Suit.hearts),
      ],
      wildIndices: const [],
      isCanastra: false,
      isClean: true,
      points: 15,
    );
    final prefs = await _pumpAt(
      tester,
      _desktop,
      Scaffold(
        body: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PlayingCard(
              card: cardId(Rank.two, Suit.hearts),
              palette: Palette.dark,
              asWild: true,
            ),
            PlayingCard(card: kJoker, palette: Palette.dark),
            PlayingCard(
              card: cardId(Rank.ace, Suit.clubs),
              palette: Palette.dark,
              faceDown: true,
            ),
            MeldBox(
              meld: run,
              palette: Palette.dark,
              width: 180,
              height: 90,
              bonus: 0,
            ),
          ],
        ),
      ),
    );

    final cards = find.byType(PlayingCard);
    final meld = find.byType(MeldBox);
    expect(_semanticsLabel(tester, cards.at(0)), 'Two of hearts, wild');
    expect(_semanticsLabel(tester, cards.at(1)), 'Joker');
    expect(_semanticsLabel(tester, cards.at(2)), 'Face-down card');
    expect(
      _semanticsLabel(tester, meld),
      'Two through Four of hearts, 3 cards',
    );
    expect(find.text('WILD'), findsNWidgets(2));

    prefs.toggleLang();
    await tester.pump();

    expect(_semanticsLabel(tester, cards.at(0)), 'dois de copas, curinga');
    expect(_semanticsLabel(tester, cards.at(1)), 'coringa');
    expect(_semanticsLabel(tester, cards.at(2)), 'carta virada para baixo');
    expect(_semanticsLabel(tester, meld), 'dois a quatro de copas, 3 cartas');
    expect(find.text('CURINGA'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

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

  testWidgets('the landing header offers sign in', (tester) async {
    await _pumpAt(tester, _desktop, const LandingScreen());

    expect(find.text('SIGN IN'), findsOneWidget);
  });

  testWidgets('sign in as guest lands back with a guest pill', (tester) async {
    final account = Account(backend: FakeAuthBackend());
    await _pumpAt(tester, _desktop, const LandingScreen(), account: account);

    await tester.tap(find.text('SIGN IN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(Copy.of(Lang.en).auth.playAsGuest));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('GUEST'), findsOneWidget);
  });

  for (final (screenName, screen) in const [
    ('sign in', SignInScreen()),
    ('code', OtpScreen(email: 'a@b.com')),
    ('profile', ProfileScreen()),
  ]) {
    for (final (sizeName, size) in const [
      ('life size', _desktop),
      ('a phone', _phone),
    ]) {
      testWidgets('the $screenName screen lays out at $sizeName', (
        tester,
      ) async {
        await _pumpAt(tester, size, screen);

        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('the code screen rejects a wrong code', (tester) async {
    final account = Account(backend: FakeAuthBackend());
    await account.sendOtp('a@b.com');
    await _pumpAt(
      tester,
      _desktop,
      const OtpScreen(email: 'a@b.com'),
      account: account,
    );

    await tester.enterText(find.byType(TextField), '111111');
    await tester.tap(find.text(Copy.of(Lang.en).auth.verify));
    await tester.pump();
    await tester.pump();

    expect(find.text(Copy.of(Lang.en).auth.badCode), findsOneWidget);
  });

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

  testWidgets('reduced motion leaves the thinking label fully opaque', (
    tester,
  ) async {
    final controller = await _dealt(tester, 'buraco');
    final prefs = await _pumpAt(
      tester,
      _desktop,
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: GameScreen(controller: controller),
      ),
    );

    controller.play(controller.moves.firstWithTarget(MoveTarget.stock)!);
    await tester.pump();
    controller.play(
      controller.moves.options.firstWhere(
        (move) => move.target == MoveTarget.discard,
      ),
    );
    await tester.pump();

    final pulseFade = find
        .ancestor(
          of: find.text(prefs.copy.thinking),
          matching: find.byType(FadeTransition),
        )
        .first;
    expect(pulseFade, findsOneWidget);
    expect(tester.widget<FadeTransition>(pulseFade).opacity.value, 1);
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
      matchTarget: 1000000,
    );
    await _pumpAt(tester, _desktop, GameScreen(controller: controller));
    await tester.pump(const Duration(seconds: 2));

    await _finishRound(tester, controller);
    expect(controller.view!.matchOver, isFalse);
    expect(find.text('Deal the next round'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Deal the next round'));
    await tester.pump(const Duration(seconds: 2));
    expect(controller.view!.roundOver, isFalse, reason: 'a new round is dealt');
    expect(tester.takeException(), isNull);
  });

  testWidgets('each rematch records its finished match', (tester) async {
    final controller = await _dealt(
      tester,
      'buraco',
      seed: 21,
      botDelay: const Duration(milliseconds: 1),
      matchTarget: 1,
    );
    final prefs = await _pumpAt(
      tester,
      _desktop,
      GameScreen(controller: controller),
    );
    await tester.pump(const Duration(seconds: 2));

    await _finishRound(tester, controller);
    expect(controller.view!.matchOver, isTrue);
    expect(find.text('New match'), findsOneWidget);
    expect(prefs.played, equals(1));

    await tester.tap(find.text('New match'));
    await tester.pump(const Duration(seconds: 2));
    expect(controller.view!.matchNumber, equals(1));
    expect(controller.view!.roundOver, isFalse);

    await _finishRound(tester, controller);
    expect(controller.view!.matchOver, isTrue);
    expect(find.text('New match'), findsOneWidget);
    expect(prefs.played, equals(2));
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

  for (final (name, size) in const [
    ('life size', _desktop),
    ('a phone', _phone),
  ]) {
    testWidgets('the online lobby lays out at $name', (tester) async {
      final cfg = loadProfile('buraco', numPlayers: 2);
      final controller = GameController(
        cfg: cfg,
        transport: LocalTransport.singlePlayer(
          cfg: cfg,
          seed: 12,
          botDelay: Duration.zero,
        ),
        autoReady: false,
      );
      final prefs = await _pumpAt(
        tester,
        size,
        GameScreen(controller: controller),
      );

      expect(find.text('LOCAL'), findsOneWidget);
      expect(find.text(prefs.copy.lobby.ready), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text(prefs.copy.lobby.ready));
      await tester.pump();
      // Finish the table's opening deal so its periodic timer cannot outlive
      // the widget test.
      await tester.pump(const Duration(seconds: 2));

      expect(controller.view, isNotNull);
      if (size == _phone) {
        expect(find.text(prefs.copy.rotatePrompt), findsOneWidget);
      } else {
        expect(find.text(prefs.copy.stock), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final (name, size) in const [
    ('life size', _desktop),
    ('a phone', _phone),
  ]) {
    testWidgets('the ranked queue lays out at $name', (tester) async {
      await _pumpAt(
        tester,
        size,
        const QueueScreen(
          ladderId: 'buraco:2:ranked',
          profileId: 'buraco',
          numPlayers: 2,
        ),
      );

      expect(tester.takeException(), isNull);
      // Queue owns periodic timers, so dispose it inside the test body.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('the leaderboard lays out at $name', (tester) async {
      await _pumpAt(
        tester,
        size,
        const LeaderboardScreen(
          ladderId: 'buraco:2:ranked',
          ladderLabel: 'Buraco · 2',
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ranked links appear only for players', (tester) async {
    final playerBackend = FakeAuthBackend();
    final player = Account(backend: playerBackend);
    await player.signInWithPassword('ana@example.com', 'password');
    final guestBackend = FakeAuthBackend();
    final guest = Account(backend: guestBackend);
    await guest.signInAnonymously();
    final signedOutBackend = FakeAuthBackend();
    final signedOut = Account(backend: signedOutBackend);
    addTearDown(() async {
      player.dispose();
      guest.dispose();
      signedOut.dispose();
      await playerBackend.close();
      await guestBackend.close();
      await signedOutBackend.close();
    });

    await _pumpAt(
      tester,
      _desktop,
      const OnlineScreen(profileId: 'buraco', numPlayers: 2),
      account: player,
    );
    expect(find.text(Copy.of(Lang.en).ranked.findMatch), findsOneWidget);
    expect(find.text(Copy.of(Lang.en).ranked.leaderboard), findsOneWidget);

    await _pumpAt(
      tester,
      _desktop,
      const OnlineScreen(profileId: 'buraco', numPlayers: 2),
      account: guest,
    );
    expect(find.text(Copy.of(Lang.en).ranked.findMatch), findsNothing);
    expect(find.text(Copy.of(Lang.en).ranked.leaderboard), findsNothing);

    await _pumpAt(
      tester,
      _desktop,
      const OnlineScreen(profileId: 'buraco', numPlayers: 2),
      account: signedOut,
    );
    expect(find.text(Copy.of(Lang.en).ranked.findMatch), findsNothing);
    expect(find.text(Copy.of(Lang.en).ranked.leaderboard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (name, size) in const [
    ('life size', _desktop),
    ('a phone', _phone),
  ]) {
    testWidgets('the friends screen lays out at $name', (tester) async {
      final backend = FakeAuthBackend()
        ..friendEntries = List.generate(
          29,
          (index) => FriendEntry(
            userId: 'friend-$index',
            displayName: 'Friend $index',
            username: 'friend$index',
            online: index.isEven,
            status: index % 5 == 0 ? 'in_game' : '',
          ),
        )
        ..friendRequestEntries = const [
          FriendRequestEntry(
            id: 1,
            userId: 'incoming-1',
            displayName: 'Incoming One',
            incoming: true,
          ),
          FriendRequestEntry(
            id: 2,
            userId: 'incoming-2',
            displayName: 'Incoming Two',
            incoming: true,
          ),
          FriendRequestEntry(
            id: 3,
            userId: 'outgoing-1',
            displayName: 'Outgoing One',
            incoming: false,
          ),
        ];
      final account = Account(backend: backend);
      addTearDown(() async {
        account.dispose();
        await backend.close();
      });

      await _pumpAt(tester, size, const FriendsScreen(), account: account);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('friends link appears only for players', (tester) async {
    final playerBackend = FakeAuthBackend();
    final player = Account(backend: playerBackend);
    await player.signInWithPassword('ana@example.com', 'password');
    final guestBackend = FakeAuthBackend();
    final guest = Account(backend: guestBackend);
    await guest.signInAnonymously();
    final signedOutBackend = FakeAuthBackend();
    final signedOut = Account(backend: signedOutBackend);
    addTearDown(() async {
      player.dispose();
      guest.dispose();
      signedOut.dispose();
      await playerBackend.close();
      await guestBackend.close();
      await signedOutBackend.close();
    });

    await _pumpAt(
      tester,
      _desktop,
      const OnlineScreen(profileId: 'buraco', numPlayers: 2),
      account: player,
    );
    expect(find.text(Copy.of(Lang.en).social.friends), findsOneWidget);

    await _pumpAt(
      tester,
      _desktop,
      const OnlineScreen(profileId: 'buraco', numPlayers: 2),
      account: guest,
    );
    expect(find.text(Copy.of(Lang.en).social.friends), findsNothing);

    await _pumpAt(
      tester,
      _desktop,
      const OnlineScreen(profileId: 'buraco', numPlayers: 2),
      account: signedOut,
    );
    expect(find.text(Copy.of(Lang.en).social.friends), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (name, size) in const [
    ('life size', _desktop),
    ('a phone', _phone),
  ]) {
    testWidgets('the history screen lays out at $name', (tester) async {
      final backend = FakeAuthBackend()
        ..historyEntries = List.generate(
          10,
          (index) => MatchHistoryEntry(
            matchId: 'match-$index',
            profileId: index.isEven ? 'buraco' : 'canasta',
            numPlayers: index.isEven ? 2 : 4,
            result: index % 3 == 0 ? 'win' : 'loss',
            finalScores: [3000 + index, 1700 + index],
            mySide: index.isEven ? 0 : 1,
            ratingDelta: index.isEven ? 20 : -12,
            isRanked: true,
            endedAt: DateTime.now().subtract(Duration(hours: index + 1)),
          ),
        );
      final account = Account(backend: backend);
      addTearDown(() async {
        account.dispose();
        await backend.close();
      });

      await _pumpAt(tester, size, const HistoryScreen(), account: account);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  }
}
