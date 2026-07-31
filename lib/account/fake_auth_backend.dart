/// A small in-memory identity provider for offline builds and client tests.
///
/// It models the important session transitions, including the two-step guest
/// upgrade, without requiring network access or global SDK state.
library;

import 'dart:async';

import 'account.dart';
import 'auth_backend.dart';

class FakeAuthBackend implements AuthBackend {
  final StreamController<AuthUser?> _changes =
      StreamController<AuthUser?>.broadcast();
  final StreamController<RoomInviteEntry> _invites =
      StreamController<RoomInviteEntry>.broadcast();
  final Map<String, ({String password, AuthUser user})> _passwordUsers = {};

  StreamController<QueueTicket>? _queue;
  AuthUser? _user;
  String? _otpEmail;
  String? _pendingLinkEmail;
  int _nextGuest = 1;
  int _nextPlayer = 1;

  (int played, int won, int best)? uploadedLegacy;

  /// The last room created through this fake, for assertions.
  (String profileId, int numPlayers, int matchTarget)? createdRoom;

  String? enqueuedLadder;
  bool queueCancelled = false;
  List<LeaderboardEntry> leaderboardEntries = [];
  List<MatchHistoryEntry> historyEntries = [];
  RankInfo? rankInfo;
  List<FriendEntry> friendEntries = [];
  List<FriendRequestEntry> friendRequestEntries = [];
  List<String> requestedFriends = [];
  AccountException? requestFriendError;
  List<({int id, bool accept})> respondedRequests = [];
  List<int> cancelledFriendRequests = [];
  List<String> blockedUsers = [];
  List<({String status, String? roomId})> heartbeats = [];
  List<int> acceptedRoomInvites = [];
  String acceptedRoomCode = 'AB23CD';

  FakeAuthBackend({AuthUser? initialUser}) : _user = initialUser;

  @override
  Stream<AuthUser?> get changes => _changes.stream;

  @override
  Future<AuthUser?> restore() async => _user;

  @override
  Future<AuthUser> signInAnonymously() async {
    final user = AuthUser(
      id: 'guest-${_nextGuest++}',
      isAnonymous: true,
      displayName: 'Convidado',
    );
    _setUser(user);
    return user;
  }

  @override
  Future<void> sendOtp(String email) async {
    _otpEmail = email;
  }

  @override
  Future<AuthUser> verifyOtp(String email, String code) async {
    if (code != '000000' || email != _otpEmail) {
      throw const AccountException(
        AccountError.badCode,
        'Código de acesso inválido.',
      );
    }

    final current = _user;
    final AuthUser user;
    if (current != null && current.isAnonymous && email == _pendingLinkEmail) {
      user = AuthUser(
        id: current.id,
        email: email,
        isAnonymous: false,
        displayName: current.displayName,
      );
    } else {
      user = _newPlayer(email);
    }

    _otpEmail = null;
    _pendingLinkEmail = null;
    _setUser(user);
    return user;
  }

  @override
  Future<AuthUser> signInWithPassword(String email, String password) async {
    final user = _passwordUsers[email]?.user ?? _newPlayer(email);
    _setUser(user);
    return user;
  }

  @override
  Future<AuthUser> signUpWithPassword(String email, String password) async {
    if (_passwordUsers.containsKey(email)) {
      throw const AccountException(
        AccountError.accountExists,
        'Esta conta já existe.',
      );
    }
    final user = _newPlayer(email);
    _passwordUsers[email] = (password: password, user: user);
    _setUser(user);
    return user;
  }

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> linkEmail(String email) async {
    if (_user case final user? when user.isAnonymous) {
      _pendingLinkEmail = email;
      _otpEmail = email;
      return;
    }
    throw const AccountException(
      AccountError.unknown,
      'Não há convidado para vincular.',
    );
  }

  @override
  Future<AuthUser> updateDisplayName(String name) async {
    final current = _user;
    if (current == null) {
      throw const AccountException(
        AccountError.unknown,
        'Não há usuário conectado.',
      );
    }
    final user = AuthUser(
      id: current.id,
      email: current.email,
      isAnonymous: current.isAnonymous,
      displayName: name,
    );
    _setUser(user);
    return user;
  }

  @override
  Future<void> uploadLegacyStats({
    required int played,
    required int won,
    required int best,
  }) async {
    uploadedLegacy = (played, won, best);
  }

  @override
  Future<String> createRoom({
    required String profileId,
    required int numPlayers,
    required int matchTarget,
  }) async {
    if (_user == null) {
      throw const AccountException(AccountError.unknown, 'not signed in');
    }
    createdRoom = (profileId, numPlayers, matchTarget);
    return 'AB23CD';
  }

  @override
  Stream<QueueTicket> enqueue(String ladderId) {
    final previous = _queue;
    if (previous != null && !previous.isClosed) unawaited(previous.close());

    enqueuedLadder = ladderId;
    queueCancelled = false;
    late final StreamController<QueueTicket> controller;
    controller = StreamController<QueueTicket>(
      onListen: () {
        controller.add(QueueTicket(ladderId: ladderId, status: 'waiting'));
      },
    );
    _queue = controller;
    return controller.stream;
  }

  void resolveQueue(String roomCode) {
    final controller = _queue;
    final ladderId = enqueuedLadder;
    if (controller == null || controller.isClosed || ladderId == null) return;

    controller.add(
      QueueTicket(
        ladderId: ladderId,
        status: 'matched',
        matchedRoomCode: roomCode,
      ),
    );
    unawaited(controller.close());
  }

  @override
  Future<void> cancelQueue() async {
    queueCancelled = true;
    final controller = _queue;
    if (controller != null && !controller.isClosed) await controller.close();
  }

  @override
  Future<List<LeaderboardEntry>> leaderboard(
    String ladderId, {
    int limit = 20,
  }) async => leaderboardEntries.take(limit).toList(growable: false);

  @override
  Future<List<MatchHistoryEntry>> matchHistory({int limit = 10}) async =>
      historyEntries.take(limit).toList(growable: false);

  @override
  Future<RankInfo?> myRank(String ladderId) async => rankInfo;

  @override
  Future<List<FriendEntry>> friends() async => friendEntries;

  @override
  Future<List<FriendRequestEntry>> friendRequests() async =>
      friendRequestEntries;

  @override
  Future<void> requestFriend(String username) async {
    final error = requestFriendError;
    if (error != null) throw error;
    requestedFriends.add(username);
  }

  @override
  Future<void> respondFriendRequest(int id, {required bool accept}) async {
    respondedRequests.add((id: id, accept: accept));
    friendRequestEntries = List.of(friendRequestEntries)
      ..removeWhere((request) => request.id == id);
  }

  @override
  Future<void> cancelFriendRequest(int id) async {
    cancelledFriendRequests.add(id);
    friendRequestEntries = List.of(friendRequestEntries)
      ..removeWhere((request) => request.id == id);
  }

  @override
  Future<void> blockUser(String userId) async {
    blockedUsers.add(userId);
    friendEntries = List.of(friendEntries)
      ..removeWhere((friend) => friend.userId == userId);
  }

  @override
  Future<void> heartbeat({required String status, String? roomId}) async {
    heartbeats.add((status: status, roomId: roomId));
  }

  @override
  Stream<RoomInviteEntry> roomInvites() => _invites.stream;

  void emitInvite(RoomInviteEntry invite) {
    if (!_invites.isClosed) _invites.add(invite);
  }

  @override
  Future<String> acceptRoomInvite(int id) async {
    acceptedRoomInvites.add(id);
    return acceptedRoomCode;
  }

  @override
  Future<void> signOut() async {
    _pendingLinkEmail = null;
    _otpEmail = null;
    _setUser(null);
  }

  AuthUser _newPlayer(String email) => AuthUser(
    id: 'player-${_nextPlayer++}',
    email: email,
    isAnonymous: false,
    displayName: email.split('@').first,
  );

  void _setUser(AuthUser? user) {
    _user = user;
    _changes.add(user);
  }

  Future<void> close() async {
    final queue = _queue;
    if (queue != null && !queue.isClosed) await queue.close();
    await _invites.close();
    await _changes.close();
  }
}
