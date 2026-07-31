/// The pre-account counters move to a permanent profile once and only once.
///
/// These tests keep the migration independent of Supabase and verify both the
/// persisted client guard and the guest-to-player transition that triggers it.
library;

import 'package:canastra/account/account.dart';
import 'package:canastra/account/auth_backend.dart';
import 'package:canastra/account/fake_auth_backend.dart';
import 'package:canastra/account/legacy_stats.dart';
import 'package:canastra/ui/app_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppPrefs> _prefsFrom(String raw) async {
  SharedPreferences.setMockInitialValues({'bl.prefs': raw});
  final prefs = AppPrefs();
  await prefs.load();
  addTearDown(prefs.dispose);
  return prefs;
}

Account _accountFor(FakeAuthBackend backend) {
  final account = Account(backend: backend);
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
  displayName: anonymous ? 'Convidado' : 'Ana',
);

Future<void> _pumpMicrotasks() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a fresh player with local matches uploads once', () async {
    final prefs = await _prefsFrom('played=4;won=3;best=2');
    final backend = FakeAuthBackend(initialUser: _user(anonymous: false));
    final account = _accountFor(backend);
    await account.restore();

    wireLegacyUpload(account: account, prefs: prefs);
    await _pumpMicrotasks();

    expect(backend.uploadedLegacy, (4, 3, 2));
    expect(prefs.legacySent, isTrue);
  });

  test('a guest never uploads', () async {
    final prefs = await _prefsFrom('played=4;won=3;best=2');
    final backend = FakeAuthBackend(initialUser: _user(anonymous: true));
    final account = _accountFor(backend);
    await account.restore();

    wireLegacyUpload(account: account, prefs: prefs);
    await _pumpMicrotasks();

    expect(backend.uploadedLegacy, isNull);
    expect(prefs.legacySent, isFalse);
  });

  test('nothing to upload sends nothing', () async {
    final prefs = await _prefsFrom('played=0;won=0;best=0');
    final backend = FakeAuthBackend(initialUser: _user(anonymous: false));
    final account = _accountFor(backend);
    await account.restore();

    wireLegacyUpload(account: account, prefs: prefs);
    await _pumpMicrotasks();

    // Whether an empty history is marked is not part of the migration contract.
    expect(backend.uploadedLegacy, isNull);
  });

  test('becoming a player later uploads then', () async {
    final prefs = await _prefsFrom('played=5;won=2;best=1');
    final backend = FakeAuthBackend();
    final account = _accountFor(backend);
    await account.restore();
    wireLegacyUpload(account: account, prefs: prefs);

    await account.signInAnonymously();
    await account.linkEmail('ana@example.com');
    await account.verifyOtp('ana@example.com', '000000', upgrading: true);
    await _pumpMicrotasks();

    expect(backend.uploadedLegacy, (5, 2, 1));
    expect(prefs.legacySent, isTrue);
  });

  test('already sent never uploads again', () async {
    final prefs = await _prefsFrom('played=4;won=3;best=2;legacySent=1');
    final backend = FakeAuthBackend(initialUser: _user(anonymous: false));
    final account = _accountFor(backend);
    await account.restore();

    wireLegacyUpload(account: account, prefs: prefs);
    await _pumpMicrotasks();

    expect(backend.uploadedLegacy, isNull);
    expect(prefs.legacySent, isTrue);
  });
}
