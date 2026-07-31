/// The sole adapter between Supabase's SDK and the app's identity contract.
///
/// Confining the vendor types here prevents authentication concerns from
/// leaking into widgets, game logic, offline builds, or unit tests.
library;

import 'dart:async';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import 'account.dart';
import 'auth_backend.dart';

class SupabaseAuthBackend implements AuthBackend {
  final SupabaseClient _client;

  StreamController<QueueTicket>? _queueController;
  RealtimeChannel? _queueChannel;
  StreamController<QueueTicket>? _queueChannelOwner;
  StreamController<RoomInviteEntry>? _inviteController;
  RealtimeChannel? _inviteChannel;
  StreamController<RoomInviteEntry>? _inviteChannelOwner;

  SupabaseAuthBackend() : _client = Supabase.instance.client;

  static Future<void> initialize({
    required String url,
    required String anonKey,
  }) async {
    await Supabase.initialize(
      url: url,
      // The project still supplies the legacy public anon key.
      // ignore: deprecated_member_use
      anonKey: anonKey,
    );
  }

  @override
  Stream<AuthUser?> get changes => _client.auth.onAuthStateChange
      .map((state) => state.session?.user)
      .map((user) => user == null ? null : _toAuthUser(user))
      .handleError((Object error) => throw _mapError(error));

  @override
  Future<AuthUser?> restore() async {
    try {
      final user = _client.auth.currentSession?.user;
      return user == null ? null : _toAuthUser(user);
    } on Object {
      return null;
    }
  }

  @override
  Future<AuthUser> signInAnonymously() => _guard(() async {
    final response = await _client.auth.signInAnonymously();
    return _requiredUser(response.user);
  });

  @override
  Future<void> sendOtp(String email) =>
      _guard(() => _client.auth.signInWithOtp(email: email));

  @override
  Future<AuthUser> verifyOtp(String email, String code) => _guard(() async {
    final response = await _client.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.email,
    );
    return _requiredUser(response.user ?? _client.auth.currentUser);
  });

  @override
  Future<AuthUser> signInWithPassword(String email, String password) =>
      _guard(() async {
        final response = await _client.auth.signInWithPassword(
          email: email,
          password: password,
        );
        return _requiredUser(response.user);
      });

  @override
  Future<AuthUser> signUpWithPassword(String email, String password) =>
      _guard(() async {
        final response = await _client.auth.signUp(
          email: email,
          password: password,
        );
        return _requiredUser(response.user);
      });

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _client.auth.resetPasswordForEmail(email));

  @override
  Future<void> linkEmail(String email) => _guard(() async {
    await _client.auth.updateUser(UserAttributes(email: email));
  });

  @override
  Future<AuthUser> updateDisplayName(String name) => _guard(() async {
    final response = await _client.auth.updateUser(
      UserAttributes(data: {'display_name': name}),
    );
    final user = _requiredUser(response.user);

    try {
      await _client.from('profiles').upsert({
        'id': user.id,
        'display_name': name,
      });
    } on Object {
      // The auth metadata is authoritative; the profile mirror is best-effort.
    }
    return user;
  });

  @override
  Future<void> uploadLegacyStats({
    required int played,
    required int won,
    required int best,
  }) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;

      await _client
          .from('profiles')
          .update({
            'legacy_played': played,
            'legacy_won': won,
            'legacy_best': best,
            'legacy_uploaded_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', uid)
          .isFilter('legacy_uploaded_at', null);
    } on Object {
      // Legacy display stats must never make account or offline play fail.
    }
  }

  @override
  Future<String> createRoom({
    required String profileId,
    required int numPlayers,
    required int matchTarget,
  }) => _guard(() async {
    final row = await _client.rpc<Map<String, dynamic>>(
      'create_room',
      params: {
        'p_profile_id': profileId,
        'p_num_players': numPlayers,
        'p_match_target': matchTarget,
      },
    );
    return row['code'] as String;
  });

  @override
  Stream<QueueTicket> enqueue(String ladderId) {
    final previous = _queueController;
    if (previous != null && !previous.isClosed) unawaited(previous.close());
    unawaited(_removeQueueChannel(owner: previous));

    late final StreamController<QueueTicket> controller;
    controller = StreamController<QueueTicket>(
      onListen: () => unawaited(_startQueue(controller, ladderId)),
      onCancel: () => _abandonQueue(controller),
    );
    _queueController = controller;
    return controller.stream;
  }

  Future<void> _startQueue(
    StreamController<QueueTicket> controller,
    String ladderId,
  ) async {
    try {
      await _client.rpc(
        'enqueue_matchmaking',
        params: {'p_ladder_id': ladderId},
      );
      if (!_queueIsActive(controller)) return;

      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        throw StateError('Ranked matchmaking requires a signed-in user.');
      }
      controller.add(QueueTicket(ladderId: ladderId, status: 'waiting'));

      final channel = _client
          .channel('queue:$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'matchmaking_queue',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: uid,
            ),
            callback: (payload) => unawaited(
              _handleQueueUpdate(controller, ladderId, payload.newRecord),
            ),
          );
      if (!_queueIsActive(controller)) return;

      _queueChannel = channel;
      _queueChannelOwner = controller;
      channel.subscribe((status, error) {
        if (!_queueIsActive(controller)) return;
        if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut ||
            status == RealtimeSubscribeStatus.closed) {
          unawaited(
            _failQueue(
              controller,
              error ?? StateError('Ranked queue channel $status.'),
              StackTrace.current,
            ),
          );
        }
      });
    } on Object catch (error, stackTrace) {
      await _failQueue(controller, error, stackTrace);
    }
  }

  Future<void> _handleQueueUpdate(
    StreamController<QueueTicket> controller,
    String ladderId,
    Map<String, dynamic> row,
  ) async {
    if (!_queueIsActive(controller)) return;
    final status = row['status'] as String?;
    if (status == null) return;

    if (status == 'matched') {
      final roomId = row['matched_room_id'];
      if (roomId == null) return;
      try {
        final room = await _client
            .from('rooms')
            .select('code')
            .eq('id', roomId)
            .single();
        if (!_queueIsActive(controller)) return;

        controller.add(
          QueueTicket(
            ladderId: ladderId,
            status: status,
            matchedRoomCode: room['code'] as String,
          ),
        );
        await _completeQueue(controller);
      } on Object catch (error, stackTrace) {
        await _failQueue(controller, error, stackTrace);
      }
      return;
    }

    controller.add(QueueTicket(ladderId: ladderId, status: status));
    if (status == 'cancelled' || status == 'expired') {
      await _completeQueue(controller);
    }
  }

  bool _queueIsActive(StreamController<QueueTicket> controller) =>
      identical(_queueController, controller) && !controller.isClosed;

  Future<void> _failQueue(
    StreamController<QueueTicket> controller,
    Object error,
    StackTrace stackTrace,
  ) async {
    if (!_queueIsActive(controller)) return;
    controller.addError(_mapError(error), stackTrace);
    await _completeQueue(controller);
  }

  Future<void> _completeQueue(StreamController<QueueTicket> controller) async {
    if (!_queueIsActive(controller)) return;
    _queueController = null;
    await _removeQueueChannel(owner: controller);
    if (!controller.isClosed) await controller.close();
  }

  Future<void> _abandonQueue(StreamController<QueueTicket> controller) async {
    if (identical(_queueController, controller)) _queueController = null;
    await _removeQueueChannel(owner: controller);
  }

  Future<void> _removeQueueChannel({
    StreamController<QueueTicket>? owner,
  }) async {
    if (owner != null && !identical(_queueChannelOwner, owner)) return;
    final channel = _queueChannel;
    _queueChannel = null;
    _queueChannelOwner = null;
    if (channel == null) return;
    try {
      await _client.removeChannel(channel);
    } on Object {
      // Cleanup is best-effort after the channel is detached locally.
    }
  }

  @override
  Future<void> cancelQueue() => _guard(() async {
    try {
      await _client.rpc('cancel_matchmaking');
    } finally {
      final controller = _queueController;
      _queueController = null;
      await _removeQueueChannel(owner: controller);
      if (controller != null && !controller.isClosed) {
        await controller.close();
      }
    }
  });

  @override
  Future<List<LeaderboardEntry>> leaderboard(
    String ladderId, {
    int limit = 20,
  }) => _guard(() async {
    final rows = await _client.rpc<List<dynamic>>(
      'leaderboard',
      params: {'p_ladder_id': ladderId, 'p_limit': limit},
    );
    return rows
        .map((row) => _leaderboardEntry(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
  });

  @override
  Future<RankInfo?> myRank(String ladderId) => _guard(() async {
    final rows = await _client.rpc<List<dynamic>>(
      'my_rank',
      params: {'p_ladder_id': ladderId},
    );
    if (rows.isEmpty) return null;
    return _rankInfo(Map<String, dynamic>.from(rows.first as Map));
  });

  @override
  Future<List<FriendEntry>> friends() => _guard(() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('Friends require a signed-in user.');
    }

    final onlineRowsFuture = _client.rpc<List<dynamic>>('friends_online');
    final rosterRowsFuture = _client
        .from('friendships')
        .select(
          'user_id, friend_id, '
          'user_profile:profiles!friendships_user_id_fkey('
          'id, display_name, username), '
          'friend_profile:profiles!friendships_friend_id_fkey('
          'id, display_name, username)',
        )
        .or('user_id.eq.$uid,friend_id.eq.$uid');
    final onlineRows = await onlineRowsFuture;
    final rosterRows = await rosterRowsFuture;

    final onlineById = <String, Map<String, dynamic>>{
      for (final raw in onlineRows)
        if (raw case final Map row when row['user_id'] is String)
          row['user_id'] as String: Map<String, dynamic>.from(row),
    };
    final entries = <FriendEntry>[
      for (final raw in rosterRows)
        _friendEntry(
          Map<String, dynamic>.from(raw),
          uid: uid,
          onlineRow:
              onlineById[_otherFriendId(Map<String, dynamic>.from(raw), uid)],
        ),
    ];
    entries.sort((a, b) => a.displayName.compareTo(b.displayName));
    return entries;
  });

  @override
  Future<List<FriendRequestEntry>> friendRequests() => _guard(() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('Friend requests require a signed-in user.');
    }

    // Assumes the DB lane uses these relationship and profile FK names.
    final rows = await _client
        .from('friend_requests')
        .select(
          'id, requester_id, addressee_id, status, '
          'requester_profile:profiles!friend_requests_requester_id_fkey('
          'id, display_name), '
          'addressee_profile:profiles!friend_requests_addressee_id_fkey('
          'id, display_name)',
        )
        .eq('status', 'pending')
        .or('requester_id.eq.$uid,addressee_id.eq.$uid');
    return [
      for (final raw in rows)
        _friendRequestEntry(Map<String, dynamic>.from(raw), uid),
    ];
  });

  @override
  Future<void> requestFriend(String username) => _guard(() async {
    final profile = await _client
        .from('profiles')
        .select('id')
        .eq('username', username.trim())
        .maybeSingle();
    if (profile == null) {
      throw const AccountException(AccountError.unknown, 'no such player');
    }
    await _client.rpc(
      'request_friend',
      params: {'p_addressee_id': profile['id'] as String},
    );
  });

  @override
  Future<void> respondFriendRequest(int id, {required bool accept}) => _guard(
    () => _client.rpc(
      accept ? 'accept_friend_request' : 'decline_friend_request',
      params: {'p_request_id': id},
    ),
  );

  @override
  Future<void> cancelFriendRequest(int id) => _guard(
    () => _client.rpc('cancel_friend_request', params: {'p_request_id': id}),
  );

  @override
  Future<void> blockUser(String userId) =>
      _guard(() => _client.rpc('block_user', params: {'p_user_id': userId}));

  @override
  Future<void> heartbeat({required String status, String? roomId}) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;
      await _client.from('user_presence').upsert({
        'user_id': uid,
        'status': status,
        'room_id': roomId,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      });
    } on Object {
      // Presence is advisory and must never disrupt auth, navigation or play.
    }
  }

  @override
  Stream<RoomInviteEntry> roomInvites() {
    final previous = _inviteController;
    if (previous != null && !previous.isClosed) unawaited(previous.close());
    unawaited(_removeInviteChannel(owner: previous));

    late final StreamController<RoomInviteEntry> controller;
    controller = StreamController<RoomInviteEntry>(
      onListen: () => _startInvites(controller),
      onCancel: () => _abandonInvites(controller),
    );
    _inviteController = controller;
    return controller.stream;
  }

  void _startInvites(StreamController<RoomInviteEntry> controller) {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        throw StateError('Room invites require a signed-in user.');
      }
      final channel = _client
          .channel('room-invites:$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'room_invites',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'invitee',
              value: uid,
            ),
            callback: (payload) =>
                unawaited(_handleInviteInsert(controller, payload.newRecord)),
          );
      if (!_invitesAreActive(controller)) return;

      _inviteChannel = channel;
      _inviteChannelOwner = controller;
      channel.subscribe((status, error) {
        if (!_invitesAreActive(controller)) return;
        if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut ||
            status == RealtimeSubscribeStatus.closed) {
          unawaited(
            _failInvites(
              controller,
              error ?? StateError('Room invite channel $status.'),
              StackTrace.current,
            ),
          );
        }
      });
    } on Object catch (error, stackTrace) {
      unawaited(_failInvites(controller, error, stackTrace));
    }
  }

  Future<void> _handleInviteInsert(
    StreamController<RoomInviteEntry> controller,
    Map<String, dynamic> row,
  ) async {
    if (!_invitesAreActive(controller)) return;
    try {
      final inviter = await _client
          .from('profiles')
          .select('display_name')
          .eq('id', row['inviter'])
          .single();
      if (!_invitesAreActive(controller)) return;
      controller.add(
        RoomInviteEntry(
          id: (row['id'] as num).toInt(),
          roomCode: '',
          inviterName: inviter['display_name'] as String,
        ),
      );
    } on Object catch (error, stackTrace) {
      await _failInvites(controller, error, stackTrace);
    }
  }

  bool _invitesAreActive(StreamController<RoomInviteEntry> controller) =>
      identical(_inviteController, controller) && !controller.isClosed;

  Future<void> _failInvites(
    StreamController<RoomInviteEntry> controller,
    Object error,
    StackTrace stackTrace,
  ) async {
    if (!_invitesAreActive(controller)) return;
    controller.addError(_mapError(error), stackTrace);
    await _completeInvites(controller);
  }

  Future<void> _completeInvites(
    StreamController<RoomInviteEntry> controller,
  ) async {
    if (!_invitesAreActive(controller)) return;
    _inviteController = null;
    await _removeInviteChannel(owner: controller);
    if (!controller.isClosed) await controller.close();
  }

  Future<void> _abandonInvites(
    StreamController<RoomInviteEntry> controller,
  ) async {
    if (identical(_inviteController, controller)) _inviteController = null;
    await _removeInviteChannel(owner: controller);
  }

  Future<void> _removeInviteChannel({
    StreamController<RoomInviteEntry>? owner,
  }) async {
    if (owner != null && !identical(_inviteChannelOwner, owner)) return;
    final channel = _inviteChannel;
    _inviteChannel = null;
    _inviteChannelOwner = null;
    if (channel == null) return;
    try {
      await _client.removeChannel(channel);
    } on Object {
      // Cleanup is best-effort after the channel is detached locally.
    }
  }

  @override
  Future<String> acceptRoomInvite(int id) => _guard(
    () =>
        _client.rpc<String>('accept_room_invite', params: {'p_invite_id': id}),
  );

  @override
  Future<void> signOut() => _guard(_client.auth.signOut);
}

String _otherFriendId(Map<String, dynamic> row, String uid) =>
    row['user_id'] == uid
    ? row['friend_id'] as String
    : row['user_id'] as String;

FriendEntry _friendEntry(
  Map<String, dynamic> row, {
  required String uid,
  required Map<String, dynamic>? onlineRow,
}) {
  final otherIsFriend = row['user_id'] == uid;
  final profile = Map<String, dynamic>.from(
    row[otherIsFriend ? 'friend_profile' : 'user_profile'] as Map,
  );
  final liveStatus = onlineRow?['status'];
  final status = liveStatus == 'in_lobby' || liveStatus == 'in_game'
      ? liveStatus as String
      : '';
  return FriendEntry(
    userId: profile['id'] as String,
    displayName: profile['display_name'] as String,
    username: profile['username'] as String?,
    online: onlineRow != null,
    status: status,
  );
}

FriendRequestEntry _friendRequestEntry(Map<String, dynamic> row, String uid) {
  final incoming = row['addressee_id'] == uid;
  final profile = Map<String, dynamic>.from(
    row[incoming ? 'requester_profile' : 'addressee_profile'] as Map,
  );
  return FriendRequestEntry(
    id: (row['id'] as num).toInt(),
    userId: profile['id'] as String,
    displayName: profile['display_name'] as String,
    incoming: incoming,
  );
}

LeaderboardEntry _leaderboardEntry(Map<String, dynamic> row) =>
    LeaderboardEntry(
      rank: (row['rank'] as num).toInt(),
      userId: row['user_id'] as String,
      username: row['username'] as String?,
      displayName: row['display_name'] as String,
      rating: (row['rating'] as num).toInt(),
      games: (row['games'] as num).toInt(),
      wins: (row['wins'] as num).toInt(),
    );

RankInfo _rankInfo(Map<String, dynamic> row) => RankInfo(
  rank: (row['rank'] as num).toInt(),
  rating: (row['rating'] as num).toInt(),
  games: (row['games'] as num).toInt(),
  percentile: (row['percentile'] as num).toDouble(),
);

Future<T> _guard<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on Object catch (error, stackTrace) {
    Error.throwWithStackTrace(_mapError(error), stackTrace);
  }
}

AccountException _mapError(Object error) {
  if (error is AccountException) return error;

  if (error is SocketException ||
      error is ClientException ||
      error is TimeoutException ||
      error is AuthRetryableFetchException) {
    return AccountException(AccountError.offline, error.toString());
  }

  if (error is AuthWeakPasswordException) {
    return AccountException(AccountError.weakPassword, error.message);
  }

  if (error is AuthApiException) {
    final code = error.code;
    final message = error.message.toLowerCase();

    if (code == 'weak_password') {
      return AccountException(AccountError.weakPassword, error.message);
    }
    if (code == 'otp_expired') {
      return AccountException(AccountError.expiredCode, error.message);
    }
    if (code == 'otp_disabled' ||
        (message.contains('invalid') &&
            (message.contains('otp') ||
                message.contains('token') ||
                message.contains('code')))) {
      return AccountException(AccountError.badCode, error.message);
    }
    if (code == 'invalid_credentials') {
      return AccountException(AccountError.wrongPassword, error.message);
    }
    if (code == 'validation_failed' && message.contains('email')) {
      return AccountException(AccountError.badEmail, error.message);
    }
    if (error.statusCode == '422' ||
        code == 'email_exists' ||
        code == 'user_already_exists') {
      return AccountException(AccountError.accountExists, error.message);
    }
  }

  return AccountException(AccountError.unknown, error.toString());
}

AuthUser _requiredUser(User? user) {
  if (user == null) {
    throw const AccountException(
      AccountError.unknown,
      'A autenticação não retornou um usuário.',
    );
  }
  return _toAuthUser(user);
}

AuthUser _toAuthUser(User user) {
  final metadataName = user.userMetadata?['display_name'];
  final emailName = user.email?.split('@').first;
  final shortId = user.id
      .substring(0, user.id.length.clamp(0, 4))
      .toUpperCase();
  final displayName = switch (metadataName) {
    final String name when name.trim().isNotEmpty => name,
    _ when emailName != null && emailName.isNotEmpty => emailName,
    _ => 'Convidado $shortId',
  };

  return AuthUser(
    id: user.id,
    email: user.email,
    isAnonymous: user.isAnonymous,
    displayName: displayName,
  );
}
