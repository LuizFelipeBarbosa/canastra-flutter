/// The identity boundary the rest of the client can depend on.
///
/// Keeping SDK types out of this contract lets the game run offline and keeps
/// account tests deterministic without initialising a platform backend.
library;

class AuthUser {
  final String id;
  final String? email;
  final bool isAnonymous;
  final String displayName;

  const AuthUser({
    required this.id,
    this.email,
    required this.isAnonymous,
    required this.displayName,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'isAnonymous': isAnonymous,
    'displayName': displayName,
  };

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
    id: j['id'] as String,
    email: j['email'] as String?,
    isAnonymous: j['isAnonymous'] as bool,
    displayName: j['displayName'] as String,
  );

  @override
  bool operator ==(Object other) =>
      other is AuthUser &&
      other.id == id &&
      other.email == email &&
      other.isAnonymous == isAnonymous &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(id, email, isAnonymous, displayName);
}

class LeaderboardEntry {
  final int rank;
  final String userId;
  final String? username;
  final String displayName;
  final int rating;
  final int games;
  final int wins;

  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    this.username,
    required this.displayName,
    required this.rating,
    required this.games,
    required this.wins,
  });

  Map<String, dynamic> toJson() => {
    'rank': rank,
    'userId': userId,
    'username': username,
    'displayName': displayName,
    'rating': rating,
    'games': games,
    'wins': wins,
  };

  factory LeaderboardEntry.fromJson(Map<String, dynamic> j) => LeaderboardEntry(
    rank: (j['rank'] as num).toInt(),
    userId: j['userId'] as String,
    username: j['username'] as String?,
    displayName: j['displayName'] as String,
    rating: (j['rating'] as num).toInt(),
    games: (j['games'] as num).toInt(),
    wins: (j['wins'] as num).toInt(),
  );

  @override
  bool operator ==(Object other) =>
      other is LeaderboardEntry &&
      other.rank == rank &&
      other.userId == userId &&
      other.username == username &&
      other.displayName == displayName &&
      other.rating == rating &&
      other.games == games &&
      other.wins == wins;

  @override
  int get hashCode =>
      Object.hash(rank, userId, username, displayName, rating, games, wins);
}

class MatchHistoryEntry {
  final String matchId;
  final String profileId;
  final int numPlayers;

  /// One of win, loss or draw.
  final String result;

  /// Final match score for each engine side.
  final List<int> finalScores;
  final int mySide;
  final int? ratingDelta;
  final bool isRanked;
  final DateTime endedAt;

  const MatchHistoryEntry({
    required this.matchId,
    required this.profileId,
    required this.numPlayers,
    required this.result,
    required this.finalScores,
    required this.mySide,
    required this.ratingDelta,
    required this.isRanked,
    required this.endedAt,
  });

  Map<String, dynamic> toJson() => {
    'matchId': matchId,
    'profileId': profileId,
    'numPlayers': numPlayers,
    'result': result,
    'finalScores': finalScores,
    'mySide': mySide,
    'ratingDelta': ratingDelta,
    'isRanked': isRanked,
    'endedAt': endedAt.toIso8601String(),
  };

  factory MatchHistoryEntry.fromJson(Map<String, dynamic> j) =>
      MatchHistoryEntry(
        matchId: j['matchId'] as String,
        profileId: j['profileId'] as String,
        numPlayers: (j['numPlayers'] as num).toInt(),
        result: j['result'] as String,
        finalScores: (j['finalScores'] as List<dynamic>)
            .map((score) => (score as num).toInt())
            .toList(growable: false),
        mySide: (j['mySide'] as num).toInt(),
        ratingDelta: (j['ratingDelta'] as num?)?.toInt(),
        isRanked: j['isRanked'] as bool,
        endedAt: DateTime.parse(j['endedAt'] as String),
      );

  @override
  bool operator ==(Object other) =>
      other is MatchHistoryEntry &&
      other.matchId == matchId &&
      other.profileId == profileId &&
      other.numPlayers == numPlayers &&
      other.result == result &&
      _sameScores(other.finalScores, finalScores) &&
      other.mySide == mySide &&
      other.ratingDelta == ratingDelta &&
      other.isRanked == isRanked &&
      other.endedAt == endedAt;

  @override
  int get hashCode => Object.hash(
    matchId,
    profileId,
    numPlayers,
    result,
    Object.hashAll(finalScores),
    mySide,
    ratingDelta,
    isRanked,
    endedAt,
  );
}

bool _sameScores(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

class RankInfo {
  final int rank;
  final int rating;
  final int games;
  final double percentile;

  const RankInfo({
    required this.rank,
    required this.rating,
    required this.games,
    required this.percentile,
  });

  Map<String, dynamic> toJson() => {
    'rank': rank,
    'rating': rating,
    'games': games,
    'percentile': percentile,
  };

  factory RankInfo.fromJson(Map<String, dynamic> j) => RankInfo(
    rank: (j['rank'] as num).toInt(),
    rating: (j['rating'] as num).toInt(),
    games: (j['games'] as num).toInt(),
    percentile: (j['percentile'] as num).toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      other is RankInfo &&
      other.rank == rank &&
      other.rating == rating &&
      other.games == games &&
      other.percentile == percentile;

  @override
  int get hashCode => Object.hash(rank, rating, games, percentile);
}

class QueueTicket {
  final String ladderId;

  /// One of waiting, matched, cancelled or expired.
  final String status;

  /// The resolved room code once [status] is matched.
  final String? matchedRoomCode;

  const QueueTicket({
    required this.ladderId,
    required this.status,
    this.matchedRoomCode,
  });

  Map<String, dynamic> toJson() => {
    'ladderId': ladderId,
    'status': status,
    'matchedRoomCode': matchedRoomCode,
  };

  factory QueueTicket.fromJson(Map<String, dynamic> j) => QueueTicket(
    ladderId: j['ladderId'] as String,
    status: j['status'] as String,
    matchedRoomCode: j['matchedRoomCode'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is QueueTicket &&
      other.ladderId == ladderId &&
      other.status == status &&
      other.matchedRoomCode == matchedRoomCode;

  @override
  int get hashCode => Object.hash(ladderId, status, matchedRoomCode);
}

class FriendEntry {
  final String userId;
  final String displayName;
  final String? username;
  final bool online;

  /// One of '', 'in_lobby', 'in_game' — '' when offline.
  final String status;

  const FriendEntry({
    required this.userId,
    required this.displayName,
    this.username,
    required this.online,
    required this.status,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'displayName': displayName,
    'username': username,
    'online': online,
    'status': status,
  };

  factory FriendEntry.fromJson(Map<String, dynamic> j) => FriendEntry(
    userId: j['userId'] as String,
    displayName: j['displayName'] as String,
    username: j['username'] as String?,
    online: j['online'] as bool,
    status: j['status'] as String,
  );

  @override
  bool operator ==(Object other) =>
      other is FriendEntry &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.username == username &&
      other.online == online &&
      other.status == status;

  @override
  int get hashCode =>
      Object.hash(userId, displayName, username, online, status);
}

class FriendRequestEntry {
  final int id;

  /// The other party to the request (never the caller).
  final String userId;
  final String displayName;

  /// True when the caller is the invitee (someone else sent this request).
  final bool incoming;

  const FriendRequestEntry({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.incoming,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'displayName': displayName,
    'incoming': incoming,
  };

  factory FriendRequestEntry.fromJson(Map<String, dynamic> j) =>
      FriendRequestEntry(
        id: (j['id'] as num).toInt(),
        userId: j['userId'] as String,
        displayName: j['displayName'] as String,
        incoming: j['incoming'] as bool,
      );

  @override
  bool operator ==(Object other) =>
      other is FriendRequestEntry &&
      other.id == id &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.incoming == incoming;

  @override
  int get hashCode => Object.hash(id, userId, displayName, incoming);
}

class RoomInviteEntry {
  final int id;

  /// Resolved to the joinable room code only once accepted; '' until then.
  final String roomCode;
  final String inviterName;

  const RoomInviteEntry({
    required this.id,
    required this.roomCode,
    required this.inviterName,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'roomCode': roomCode,
    'inviterName': inviterName,
  };

  factory RoomInviteEntry.fromJson(Map<String, dynamic> j) => RoomInviteEntry(
    id: (j['id'] as num).toInt(),
    roomCode: j['roomCode'] as String,
    inviterName: j['inviterName'] as String,
  );

  @override
  bool operator ==(Object other) =>
      other is RoomInviteEntry &&
      other.id == id &&
      other.roomCode == roomCode &&
      other.inviterName == inviterName;

  @override
  int get hashCode => Object.hash(id, roomCode, inviterName);
}

abstract class AuthBackend {
  /// Restore a persisted session. Null when signed out. Must not throw.
  Future<AuthUser?> restore();

  Future<AuthUser> signInAnonymously();

  /// Sends either the six-digit email code or the magic-link email.
  Future<void> sendOtp(String email);

  Future<AuthUser> verifyOtp(String email, String code);
  Future<AuthUser> signInWithPassword(String email, String password);
  Future<AuthUser> signUpWithPassword(String email, String password);
  Future<void> sendPasswordReset(String email);

  /// Starts an anonymous-to-permanent upgrade without changing the user id.
  Future<void> linkEmail(String email);

  Future<AuthUser> updateDisplayName(String name);

  /// Push pre-account local counters into the profile, once. Server-side the
  /// columns are first-write-only; calling again is harmless. Must not throw on
  /// network failure — the caller treats this as fire-and-forget.
  Future<void> uploadLegacyStats({
    required int played,
    required int won,
    required int best,
  });

  Future<void> signOut();

  /// Create a private table server-side and return its shareable join code.
  ///
  /// Lives on the auth backend because the room row belongs to the signed-in
  /// user — the database rejects the call without a session. Throws the same
  /// mapped exceptions as the sign-in methods.
  Future<String> createRoom({
    required String profileId,
    required int numPlayers,
    required int matchTarget,
  });

  /// Join the ranked queue for a ladder. The stream reports the ticket's state
  /// and completes (or errors) when it resolves; cancel() to leave.
  Stream<QueueTicket> enqueue(String ladderId);

  Future<void> cancelQueue();

  Future<List<LeaderboardEntry>> leaderboard(String ladderId, {int limit = 20});

  /// Newest first. Empty when signed out or nothing recorded.
  Future<List<MatchHistoryEntry>> matchHistory({int limit = 10});

  /// Null when unranked (fewer than 10 games or no row).
  Future<RankInfo?> myRank(String ladderId);

  /// The full friends list, offline and online. Online status/status word come
  /// from the friends_online RPC; the rest of the roster (including offline
  /// friends) comes from a second query against the friends relationship
  /// joined to profiles. The two are merged client-side by user id — a friend
  /// missing from the online set is offline with status ''.
  Future<List<FriendEntry>> friends();

  /// Pending requests only, both directions.
  Future<List<FriendRequestEntry>> friendRequests();

  /// Resolves [username] to a profile id, then sends a friend request.
  /// Throws AccountException(AccountError.unknown, 'no such player') when the
  /// username does not resolve to a profile.
  Future<void> requestFriend(String username);

  /// Accepts or declines the pending request identified by [id].
  Future<void> respondFriendRequest(int id, {required bool accept});

  /// Cancels an outgoing pending request.
  Future<void> cancelFriendRequest(int id);

  /// Blocks [userId], removing any friendship or pending requests server-side.
  Future<void> blockUser(String userId);

  /// Upserts this user's own presence row. Never throws — presence must never
  /// break anything else in the app.
  Future<void> heartbeat({required String status, String? roomId});

  /// Realtime INSERTs on room_invites where the caller is the invitee, each
  /// resolved to a display name for the inviter. The channel is torn down when
  /// the stream is cancelled.
  Stream<RoomInviteEntry> roomInvites();

  /// Accepts a room invite and returns the joinable room code.
  Future<String> acceptRoomInvite(int id);

  /// External session changes such as refreshes, returns and revocations.
  Stream<AuthUser?> get changes;
}
