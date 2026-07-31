/// Ranked play stays deterministic through the account seam.
///
/// These tests drive matchmaking and ladder data through the in-memory backend,
/// so no global Supabase client or network state is involved.
library;

import 'package:canastra/account/account.dart';
import 'package:canastra/multiplayer/local_transport.dart';
import 'package:canastra/engine/profiles.dart';
import 'package:canastra/account/auth_backend.dart';
import 'package:canastra/account/fake_auth_backend.dart';
import 'package:canastra/ui/account_scope.dart';
import 'package:canastra/ui/app_scope.dart';
import 'package:canastra/ui/copy.dart';
import 'package:canastra/ui/screens/game_screen.dart';
import 'package:canastra/ui/screens/leaderboard_screen.dart';
import 'package:canastra/ui/screens/queue_screen.dart';
import 'package:canastra/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _desktop = Size(1280, 820);

/// Own both sides of the fake seam so every controller closes after its test.
Account _accountFor(FakeAuthBackend backend) {
  final account = Account(backend: backend);
  addTearDown(() async {
    account.dispose();
    await backend.close();
  });
  return account;
}

/// Pump a ranked screen with the same inherited state as the real app.
Future<void> _pumpRanked(
  WidgetTester tester,
  Widget home,
  Account account,
) async {
  tester.view.physicalSize = _desktop;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final prefs = AppPrefs();
  await tester.pumpWidget(
    AppScope(
      prefs: prefs,
      child: AccountScope(
        account: account,
        child: MaterialApp(
          theme: buildTheme(prefs.palette, dark: prefs.dark),
          home: home,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('queue emits waiting before the resolved room code', () async {
    final backend = FakeAuthBackend();
    final account = _accountFor(backend);
    final ticketsFuture = account.enqueue('buraco:2:ranked').toList();

    await Future<void>.delayed(Duration.zero);
    expect(backend.enqueuedLadder, 'buraco:2:ranked');

    backend.resolveQueue('AB23CD');
    final tickets = await ticketsFuture;

    expect(tickets, const [
      QueueTicket(ladderId: 'buraco:2:ranked', status: 'waiting'),
      QueueTicket(
        ladderId: 'buraco:2:ranked',
        status: 'matched',
        matchedRoomCode: 'AB23CD',
      ),
    ]);
  });

  test('cancelling the queue is recorded and completes its stream', () async {
    final backend = FakeAuthBackend();
    final account = _accountFor(backend);
    final ticketsFuture = account.enqueue('buraco:4:ranked').toList();
    await Future<void>.delayed(Duration.zero);

    await account.cancelQueue();

    expect(backend.queueCancelled, isTrue);
    expect(await ticketsFuture, const [
      QueueTicket(ladderId: 'buraco:4:ranked', status: 'waiting'),
    ]);
  });

  test('leaderboard and personal rank round through Account', () async {
    final backend = FakeAuthBackend()
      ..leaderboardEntries = const [
        LeaderboardEntry(
          rank: 1,
          userId: 'ana',
          username: 'aninha',
          displayName: 'Ana',
          rating: 1675,
          games: 24,
          wins: 15,
        ),
      ]
      ..rankInfo = const RankInfo(
        rank: 37,
        rating: 1410,
        games: 12,
        percentile: 12,
      );
    final account = _accountFor(backend);

    expect(
      await account.leaderboard('buraco:2:ranked'),
      backend.leaderboardEntries,
    );
    expect(await account.myRank('buraco:2:ranked'), backend.rankInfo);
  });

  testWidgets('queue auto-joins the resolved table', (tester) async {
    final backend = FakeAuthBackend();
    final account = _accountFor(backend);
    await _pumpRanked(
      tester,
      QueueScreen(
        ladderId: 'buraco:2:ranked',
        profileId: 'buraco',
        numPlayers: 2,
        // A local transport in manual-bot mode arms no timers; the real
        // WebSocket transport's connect machinery would leak platform timers
        // into the fake-async zone.
        transportFactory: (roomCode, playerName) => LocalTransport.singlePlayer(
          cfg: loadProfile('buraco', numPlayers: 2),
          seed: 7,
          playerName: playerName,
          botDelay: Duration.zero,
        ),
      ),
      account,
    );

    expect(
      find.textContaining(Copy.of(Lang.en).ranked.searching),
      findsOneWidget,
    );

    backend.resolveQueue('AB23CD');
    // One frame for the ticket, one post-frame push, then the route's 300ms
    // transition plus its completion frame.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.byType(GameScreen), findsOneWidget);

    // Dispose the pushed controller immediately; this test checks routing, not
    // a real WebSocket connection or the game screen's own retry lifecycle.
    await tester.pumpWidget(const SizedBox.shrink());
    // Elapse the local transport's zero-length connect timer so nothing is
    // pending when the binding audits the zone.
    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('queue cancel calls the backend and returns', (tester) async {
    final backend = FakeAuthBackend();
    final account = _accountFor(backend);
    await _pumpRanked(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const QueueScreen(
                  ladderId: 'buraco:2:ranked',
                  profileId: 'buraco',
                  numPlayers: 2,
                ),
              ),
            ),
            child: const Text('open queue'),
          ),
        ),
      ),
      account,
    );

    await tester.tap(find.text('open queue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(QueueScreen), findsOneWidget);

    await tester.tap(find.text(Copy.of(Lang.en).ranked.cancel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(backend.queueCancelled, isTrue);
    expect(find.byType(QueueScreen), findsNothing);
  });

  testWidgets('leaderboard shows canned rows and the unranked message', (
    tester,
  ) async {
    final backend = FakeAuthBackend()
      ..leaderboardEntries = const [
        LeaderboardEntry(
          rank: 1,
          userId: 'ana',
          username: 'aninha',
          displayName: 'Ana',
          rating: 1675,
          games: 24,
          wins: 15,
        ),
        LeaderboardEntry(
          rank: 2,
          userId: 'bia',
          displayName: 'Bia',
          rating: 1612,
          games: 18,
          wins: 10,
        ),
      ];
    final account = _accountFor(backend);
    await _pumpRanked(
      tester,
      const LeaderboardScreen(
        ladderId: 'buraco:2:ranked',
        ladderLabel: 'Buraco · 2',
      ),
      account,
    );
    await tester.pump();

    expect(find.text('aninha'), findsOneWidget);
    expect(find.text('Bia'), findsOneWidget);
    expect(find.text('1675'), findsOneWidget);
    expect(find.text(Copy.of(Lang.en).ranked.unranked), findsOneWidget);

    final highlighted = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).color == Palette.dark.panelHot,
    );
    expect(highlighted, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
