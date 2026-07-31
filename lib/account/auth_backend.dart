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

  /// Null when unranked (fewer than 10 games or no row).
  Future<RankInfo?> myRank(String ladderId);

  /// External session changes such as refreshes, returns and revocations.
  Stream<AuthUser?> get changes;
}
