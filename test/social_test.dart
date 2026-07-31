/// Friends and presence through the same fake seam used by account tests.
library;

import 'package:canastra/account/account.dart';
import 'package:canastra/account/auth_backend.dart';
import 'package:canastra/account/fake_auth_backend.dart';
import 'package:canastra/account/presence.dart';
import 'package:canastra/engine/profiles.dart';
import 'package:canastra/multiplayer/local_transport.dart';
import 'package:canastra/ui/account_scope.dart';
import 'package:canastra/ui/app_scope.dart';
import 'package:canastra/ui/copy.dart';
import 'package:canastra/ui/screens/friends_screen.dart';
import 'package:canastra/ui/screens/game_screen.dart';
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

Future<void> _pumpSocial(
  WidgetTester tester,
  FriendsScreen screen,
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
          home: screen,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('friends and requests round through Account', () async {
    final backend = FakeAuthBackend()
      ..friendEntries = const [
        FriendEntry(
          userId: 'ana',
          displayName: 'Ana',
          username: 'aninha',
          online: true,
          status: 'in_game',
        ),
      ]
      ..friendRequestEntries = const [
        FriendRequestEntry(
          id: 4,
          userId: 'bia',
          displayName: 'Bia',
          incoming: true,
        ),
      ];
    final account = _accountFor(backend);

    expect(await account.friends(), backend.friendEntries);
    expect(await account.friendRequests(), backend.friendRequestEntries);
  });

  test('unknown friend username keeps the mapped backend error', () async {
    final backend = FakeAuthBackend()
      ..requestFriendError = const AccountException(
        AccountError.unknown,
        'no such player',
      );
    final account = _accountFor(backend);

    await expectLater(
      account.requestFriend('nobody'),
      throwsA(
        isA<AccountException>()
            .having((error) => error.error, 'error', AccountError.unknown)
            .having((error) => error.message, 'message', 'no such player'),
      ),
    );
  });

  test('accepting a friend request is recorded', () async {
    final backend = FakeAuthBackend();
    final account = _accountFor(backend);

    await account.respondFriendRequest(7, accept: true);

    expect(backend.respondedRequests, [(id: 7, accept: true)]);
  });

  testWidgets('friends render online dots and accepted requests disappear', (
    tester,
  ) async {
    final backend = FakeAuthBackend()
      ..friendEntries = const [
        FriendEntry(
          userId: 'ana',
          displayName: 'Ana',
          online: true,
          status: '',
        ),
        FriendEntry(
          userId: 'bia',
          displayName: 'Bia',
          online: false,
          status: '',
        ),
        FriendEntry(
          userId: 'caio',
          displayName: 'Caio',
          online: true,
          status: 'in_lobby',
        ),
      ]
      ..friendRequestEntries = const [
        FriendRequestEntry(
          id: 11,
          userId: 'duda',
          displayName: 'Duda',
          incoming: true,
        ),
      ];
    final account = _accountFor(backend);
    await account.signInWithPassword('player@example.com', 'password');
    await _pumpSocial(tester, const FriendsScreen(), account);

    final onlineDots = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('online-'),
    );
    expect(onlineDots, findsNWidgets(2));
    expect(find.text('Duda'), findsOneWidget);

    await tester.tap(find.text(Copy.of(Lang.en).social.accept));
    await tester.pump();
    await tester.pump();

    expect(backend.respondedRequests, [(id: 11, accept: true)]);
    expect(find.text('Duda'), findsNothing);
  });

  testWidgets('a room invite banner joins the accepted room', (tester) async {
    final backend = FakeAuthBackend()..acceptedRoomCode = 'ROOM42';
    final account = _accountFor(backend);
    await account.signInWithPassword('ana@example.com', 'password');
    await _pumpSocial(
      tester,
      FriendsScreen(
        transportFactory: (roomCode, playerName) => LocalTransport.singlePlayer(
          cfg: loadProfile('buraco', numPlayers: 2),
          seed: 9,
          playerName: playerName,
          botDelay: Duration.zero,
        ),
      ),
      account,
    );

    backend.emitInvite(
      const RoomInviteEntry(id: 23, roomCode: '', inviterName: 'Bia'),
    );
    await tester.pump();
    expect(find.text(Copy.of(Lang.en).social.invitedBy('Bia')), findsOneWidget);

    await tester.tap(find.text(Copy.of(Lang.en).social.join));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(backend.acceptedRoomInvites, [23]);
    expect(find.byType(GameScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });

  test('presence only beats while started and signed in', () async {
    final backend = FakeAuthBackend();
    final account = _accountFor(backend);
    final heartbeat = PresenceHeartbeat(
      account: account,
      period: const Duration(milliseconds: 5),
    );
    addTearDown(heartbeat.stop);

    await Future<void>.delayed(const Duration(milliseconds: 12));
    expect(backend.heartbeats, isEmpty);

    heartbeat.start();
    await Future<void>.delayed(const Duration(milliseconds: 12));
    expect(backend.heartbeats, isEmpty);

    await account.signInWithPassword('ana@example.com', 'password');
    await Future<void>.delayed(const Duration(milliseconds: 18));
    expect(backend.heartbeats, isNotEmpty);
    expect(backend.heartbeats.every((beat) => beat.status == 'online'), isTrue);

    heartbeat.stop();
    final beatsAfterStop = backend.heartbeats.length;
    await Future<void>.delayed(const Duration(milliseconds: 12));
    expect(backend.heartbeats, hasLength(beatsAfterStop));
  });
}
