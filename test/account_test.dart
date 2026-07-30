/// Tests the client identity state machine without touching global SDK state.
///
/// The in-memory backend makes persistence, guest upgrades, failures and a
/// stalled restore reproducible while exercising the same seam production uses.
library;

import 'dart:async';

import 'package:canastra/account/account.dart';
import 'package:canastra/account/auth_backend.dart';
import 'package:canastra/account/fake_auth_backend.dart';
import 'package:flutter_test/flutter_test.dart';

Account _accountFor(
  FakeAuthBackend backend, {
  Duration restoreTimeout = const Duration(seconds: 3),
}) {
  final account = Account(backend: backend, restoreTimeout: restoreTimeout);
  addTearDown(() async {
    account.dispose();
    await backend.close();
  });
  return account;
}

AuthUser _user({required bool anonymous}) => AuthUser(
  id: anonymous ? 'persisted-guest' : 'persisted-player',
  email: anonymous ? null : 'ana@example.com',
  isAnonymous: anonymous,
  displayName: anonymous ? 'Convidado AB12' : 'Ana',
);

class _NeverRestoringBackend extends FakeAuthBackend {
  @override
  Future<AuthUser?> restore() => Completer<AuthUser?>().future;
}

void main() {
  _roomTests();

  test('restore with a persisted guest lands in guest', () async {
    final user = _user(anonymous: true);
    final account = _accountFor(FakeAuthBackend(initialUser: user));

    await account.restore();

    expect(account.state, isA<Guest>());
    expect(account.user, user);
    expect(account.signedIn, isTrue);
  });

  test('restore with a persisted player lands in player', () async {
    final user = _user(anonymous: false);
    final account = _accountFor(FakeAuthBackend(initialUser: user));

    await account.restore();

    expect(account.state, isA<Player>());
    expect(account.user, user);
    expect(account.signedIn, isTrue);
  });

  test('guest sign-in enters guest and notifies listeners', () async {
    final account = _accountFor(FakeAuthBackend());
    var notifications = 0;
    account.addListener(() => notifications += 1);

    await account.signInAnonymously();

    expect(account.state, isA<Guest>());
    expect(account.user?.isAnonymous, isTrue);
    expect(notifications, 1);
  });

  test('linking email upgrades a guest without changing its id', () async {
    final account = _accountFor(FakeAuthBackend());
    await account.signInAnonymously();
    final guestId = account.user!.id;

    await account.linkEmail('ana@example.com');
    expect(account.state, isA<Guest>());
    await account.verifyOtp('ana@example.com', '000000');

    expect(account.state, isA<Player>());
    expect(account.user?.id, guestId);
    expect(account.user?.email, 'ana@example.com');
  });

  test('a wrong otp stays in guest and surfaces bad code', () async {
    final account = _accountFor(FakeAuthBackend());
    await account.signInAnonymously();
    await account.linkEmail('ana@example.com');

    await expectLater(
      account.verifyOtp('ana@example.com', '123456'),
      throwsA(
        isA<AccountException>().having(
          (error) => error.error,
          'error',
          AccountError.badCode,
        ),
      ),
    );

    expect(account.state, isA<Guest>());
  });

  test('sign out enters signed out', () async {
    final account = _accountFor(FakeAuthBackend());
    await account.signInAnonymously();

    await account.signOut();

    expect(account.state, isA<SignedOut>());
    expect(account.user, isNull);
    expect(account.signedIn, isFalse);
  });

  test('display name changes propagate to account', () async {
    final account = _accountFor(FakeAuthBackend());
    await account.signInAnonymously();

    await account.updateDisplayName('Bia');

    expect(account.displayName, 'Bia');
    expect(account.user?.displayName, 'Bia');
  });

  test('restore times out into signed out', () async {
    final backend = _NeverRestoringBackend();
    final account = _accountFor(
      backend,
      restoreTimeout: const Duration(milliseconds: 30),
    );
    final stopwatch = Stopwatch()..start();

    await account.restore();

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    expect(account.state, isA<SignedOut>());
  });
}

/// Appended with the private-table flow: creating a room requires a session
/// and hands back the join code the server minted.
void _roomTests() {
  test('creating a room returns the code and records the rules', () async {
    final backend = FakeAuthBackend();
    final account = Account(backend: backend);
    await account.signInAnonymously();

    final code = await account.createRoom(
      profileId: 'canasta',
      numPlayers: 4,
      matchTarget: 1500,
    );
    expect(code, 'AB23CD');
    expect(backend.createdRoom, ('canasta', 4, 1500));
  });

  test('creating a room while signed out fails', () async {
    final account = Account(backend: FakeAuthBackend());
    await expectLater(
      account.createRoom(profileId: 'buraco', numPlayers: 2, matchTarget: 3000),
      throwsA(isA<AccountException>()),
    );
  });
}
