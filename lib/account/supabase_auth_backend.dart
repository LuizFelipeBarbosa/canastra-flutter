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
  Future<void> signOut() => _guard(_client.auth.signOut);
}

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
