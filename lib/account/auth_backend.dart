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

  /// External session changes such as refreshes, returns and revocations.
  Stream<AuthUser?> get changes;
}
