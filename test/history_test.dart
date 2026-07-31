/// Match history stays deterministic through the account seam.
library;

import 'dart:async';

import 'package:canastra/account/account.dart';
import 'package:canastra/account/auth_backend.dart';
import 'package:canastra/account/fake_auth_backend.dart';
import 'package:canastra/ui/account_scope.dart';
import 'package:canastra/ui/app_scope.dart';
import 'package:canastra/ui/copy.dart';
import 'package:canastra/ui/screens/history_screen.dart';
import 'package:canastra/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _desktop = Size(1280, 820);

Account _accountFor(FakeAuthBackend backend) {
  final account = Account(backend: backend);
  addTearDown(() async {
    account.dispose();
    await backend.close();
  });
  return account;
}

MatchHistoryEntry _entry({
  required String matchId,
  required String result,
  required List<int> scores,
  required int mySide,
  int? ratingDelta,
  String profileId = 'buraco',
  int numPlayers = 2,
  DateTime? endedAt,
}) => MatchHistoryEntry(
  matchId: matchId,
  profileId: profileId,
  numPlayers: numPlayers,
  result: result,
  finalScores: scores,
  mySide: mySide,
  ratingDelta: ratingDelta,
  isRanked: ratingDelta != null,
  endedAt: endedAt ?? DateTime.utc(2026, 7, 30, 12),
);

Future<void> _pumpHistory(WidgetTester tester, Account account) async {
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
          home: const HistoryScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
}

class _PendingHistoryBackend extends FakeAuthBackend {
  final historyCompleter = Completer<List<MatchHistoryEntry>>();

  @override
  Future<List<MatchHistoryEntry>> matchHistory({int limit = 10}) async =>
      (await historyCompleter.future).take(limit).toList(growable: false);
}

void main() {
  test('history round-trips through Account and respects the limit', () async {
    final first = _entry(
      matchId: '0198-first',
      result: 'win',
      scores: const [3020, 1755],
      mySide: 0,
      ratingDelta: 20,
    );
    final second = _entry(
      matchId: '0197-second',
      result: 'loss',
      scores: const [3010, 1770],
      mySide: 1,
      ratingDelta: -12,
    );
    final backend = FakeAuthBackend()..historyEntries = [first, second];
    final account = _accountFor(backend);

    expect(await account.matchHistory(limit: 1), [first]);
    expect(MatchHistoryEntry.fromJson(first.toJson()), first);
    expect(MatchHistoryEntry.fromJson(first.toJson()).hashCode, first.hashCode);
  });

  testWidgets('canned history renders results, scores and rating deltas', (
    tester,
  ) async {
    final now = DateTime.now();
    final backend = FakeAuthBackend()
      ..historyEntries = [
        _entry(
          matchId: 'win',
          result: 'win',
          scores: const [3020, 1755],
          mySide: 0,
          ratingDelta: 20,
          endedAt: now.subtract(const Duration(hours: 2)),
        ),
        _entry(
          matchId: 'loss',
          result: 'loss',
          scores: const [3010, 1770],
          mySide: 1,
          ratingDelta: -12,
          profileId: 'canasta',
          numPlayers: 4,
          endedAt: now.subtract(const Duration(days: 3)),
        ),
        _entry(
          matchId: 'draw',
          result: 'draw',
          scores: const [2200, 2200],
          mySide: 0,
          endedAt: now.subtract(const Duration(minutes: 8)),
        ),
      ];
    final account = _accountFor(backend);

    await _pumpHistory(tester, account);

    final copy = Copy.of(Lang.en).ranked;
    expect(find.text(copy.won), findsOneWidget);
    expect(find.text(copy.lost), findsOneWidget);
    expect(find.text(copy.draw), findsOneWidget);
    expect(find.text('3020 — 1755'), findsOneWidget);
    expect(find.text('1770 — 3010'), findsOneWidget);
    expect(find.text('+20'), findsOneWidget);
    expect(find.text('−12'), findsOneWidget);
    expect(find.text('2h'), findsOneWidget);
    expect(find.text('3d'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty history shows the empty state', (tester) async {
    final account = _accountFor(FakeAuthBackend());

    await _pumpHistory(tester, account);

    expect(find.text(Copy.of(Lang.en).ranked.noHistory), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading history resolves without leaving a spinner', (
    tester,
  ) async {
    final backend = _PendingHistoryBackend();
    final account = _accountFor(backend);

    await _pumpHistory(tester, account);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    backend.historyCompleter.complete([
      _entry(
        matchId: 'resolved',
        result: 'win',
        scores: const [1500, 900],
        mySide: 0,
      ),
    ]);
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('1500 — 900'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
