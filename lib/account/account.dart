/// The observable client identity used by presentation code.
///
/// It turns backend-specific failures and session events into a small stable
/// state machine, so widgets never need to know which identity provider is in
/// use or whether this build has one at all.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_backend.dart';

sealed class AuthState {
  const AuthState();
}

class Restoring extends AuthState {
  const Restoring();
}

class SignedOut extends AuthState {
  const SignedOut();
}

class Guest extends AuthState {
  final AuthUser user;
  const Guest(this.user);
}

class Player extends AuthState {
  final AuthUser user;
  const Player(this.user);
}

enum AccountError {
  badEmail,
  badCode,
  expiredCode,
  weakPassword,
  wrongPassword,
  accountExists,
  offline,
  unknown,
}

class AccountException implements Exception {
  final AccountError error;
  final String message;

  const AccountException(this.error, this.message);

  @override
  String toString() => message;
}

class Account extends ChangeNotifier {
  final AuthBackend _backend;
  final Duration _restoreTimeout;

  AuthState _state = const Restoring();
  StreamSubscription<AuthUser?>? _changesSubscription;
  int _backendRevision = 0;

  factory Account({
    required AuthBackend backend,
    Duration restoreTimeout = const Duration(seconds: 3),
  }) => Account._(backend, restoreTimeout);

  Account._(this._backend, this._restoreTimeout);

  AuthState get state => _state;

  AuthUser? get user => switch (_state) {
    Guest(:final user) || Player(:final user) => user,
    Restoring() || SignedOut() => null,
  };

  String? get displayName => user?.displayName;

  bool get signedIn => switch (_state) {
    Guest() || Player() => true,
    Restoring() || SignedOut() => false,
  };

  /// Restores promptly even when local session recovery gets stuck.
  ///
  /// External changes win a race with the initial snapshot: a revocation that
  /// arrives while restore is pending must not be overwritten by stale data.
  Future<void> restore() async {
    try {
      _changesSubscription ??= _backend.changes.listen(
        _handleBackendChange,
        onError: (Object _, StackTrace _) {},
      );
    } on Object {
      // A broken event stream must not prevent the offline signed-out path.
    }

    final revision = _backendRevision;
    AuthUser? restored;
    try {
      restored = await _backend.restore().timeout(_restoreTimeout);
    } on Object {
      restored = null;
    }

    if (revision == _backendRevision) _setUser(restored);
  }

  Future<void> signInAnonymously() async {
    _setUser(await _run(_backend.signInAnonymously));
  }

  Future<void> sendOtp(String email) => _run(() => _backend.sendOtp(email));

  Future<void> verifyOtp(String email, String code) async {
    _setUser(await _run(() => _backend.verifyOtp(email, code)));
  }

  Future<void> signInWithPassword(String email, String password) async {
    _setUser(await _run(() => _backend.signInWithPassword(email, password)));
  }

  Future<void> signUpWithPassword(String email, String password) async {
    _setUser(await _run(() => _backend.signUpWithPassword(email, password)));
  }

  Future<void> sendPasswordReset(String email) =>
      _run(() => _backend.sendPasswordReset(email));

  Future<void> linkEmail(String email) => _run(() => _backend.linkEmail(email));

  Future<void> updateDisplayName(String name) async {
    _setUser(await _run(() => _backend.updateDisplayName(name)));
  }

  /// Fire-and-forget; never throws. No state change, no notifyListeners.
  Future<void> uploadLegacyStats({
    required int played,
    required int won,
    required int best,
  }) => _backend.uploadLegacyStats(played: played, won: won, best: best);

  /// Create a private table and return its shareable join code.
  Future<String> createRoom({
    required String profileId,
    required int numPlayers,
    required int matchTarget,
  }) => _run(
    () => _backend.createRoom(
      profileId: profileId,
      numPlayers: numPlayers,
      matchTarget: matchTarget,
    ),
  );

  /// Streams do not fit [_run], which only guards one future. An async
  /// generator keeps cancellation wired to the backend while applying the
  /// same stable exception mapping to both synchronous and streamed failures.
  Stream<QueueTicket> enqueue(String ladderId) async* {
    try {
      yield* _backend.enqueue(ladderId);
    } on AccountException {
      rethrow;
    } on TimeoutException catch (error) {
      throw AccountException(AccountError.offline, error.toString());
    } on Object catch (error) {
      throw AccountException(AccountError.unknown, error.toString());
    }
  }

  Future<void> cancelQueue() => _run(_backend.cancelQueue);

  Future<List<LeaderboardEntry>> leaderboard(
    String ladderId, {
    int limit = 20,
  }) => _run(() => _backend.leaderboard(ladderId, limit: limit));

  Future<List<MatchHistoryEntry>> matchHistory({int limit = 10}) =>
      _run(() => _backend.matchHistory(limit: limit));

  Future<RankInfo?> myRank(String ladderId) =>
      _run(() => _backend.myRank(ladderId));

  Future<List<FriendEntry>> friends() => _run(_backend.friends);

  Future<List<FriendRequestEntry>> friendRequests() =>
      _run(_backend.friendRequests);

  Future<void> requestFriend(String username) =>
      _run(() => _backend.requestFriend(username));

  Future<void> respondFriendRequest(int id, {required bool accept}) =>
      _run(() => _backend.respondFriendRequest(id, accept: accept));

  Future<void> cancelFriendRequest(int id) =>
      _run(() => _backend.cancelFriendRequest(id));

  Future<void> blockUser(String userId) =>
      _run(() => _backend.blockUser(userId));

  Future<void> heartbeat({required String status, String? roomId}) =>
      _backend.heartbeat(status: status, roomId: roomId);

  Stream<RoomInviteEntry> roomInvites() async* {
    try {
      yield* _backend.roomInvites();
    } on AccountException {
      rethrow;
    } on TimeoutException catch (error) {
      throw AccountException(AccountError.offline, error.toString());
    } on Object catch (error) {
      throw AccountException(AccountError.unknown, error.toString());
    }
  }

  Future<String> acceptRoomInvite(int id) =>
      _run(() => _backend.acceptRoomInvite(id));

  Future<void> signOut() async {
    await _run(_backend.signOut);
    _setUser(null);
  }

  Future<T> _run<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on AccountException {
      rethrow;
    } on TimeoutException catch (error) {
      throw AccountException(AccountError.offline, error.toString());
    } on Object catch (error) {
      throw AccountException(AccountError.unknown, error.toString());
    }
  }

  void _handleBackendChange(AuthUser? user) {
    _backendRevision += 1;
    _setUser(user);
  }

  void _setUser(AuthUser? user) {
    final next = switch (user) {
      null => const SignedOut(),
      AuthUser(isAnonymous: true) => Guest(user),
      AuthUser(isAnonymous: false) => Player(user),
    };
    if (_sameState(_state, next)) return;
    _state = next;
    notifyListeners();
  }

  bool _sameState(AuthState left, AuthState right) => switch ((left, right)) {
    (Restoring(), Restoring()) || (SignedOut(), SignedOut()) => true,
    (Guest(user: final a), Guest(user: final b)) ||
    (Player(user: final a), Player(user: final b)) => a == b,
    _ => false,
  };

  @override
  void dispose() {
    final subscription = _changesSubscription;
    if (subscription != null) unawaited(subscription.cancel());
    super.dispose();
  }
}
