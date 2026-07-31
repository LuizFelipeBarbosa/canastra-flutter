/// Server-side verification of Supabase access tokens.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class AuthedUser {
  final String id;
  final String? email;
  final bool isAnonymous;

  const AuthedUser({required this.id, this.email, required this.isAnonymous});
}

abstract class TokenVerifier {
  /// Null means reject. Implementations must not throw.
  Future<AuthedUser?> verify(String token);
}

class _CachedUser {
  final AuthedUser user;
  final DateTime expiresAt;

  const _CachedUser({required this.user, required this.expiresAt});
}

/// Verifies access tokens against the Supabase Auth user endpoint.
class SupabaseTokenVerifier implements TokenVerifier {
  static const _requestTimeout = Duration(seconds: 5);
  static const _cacheTtl = Duration(minutes: 5);

  final Uri _userUri;
  final String _anonKey;
  final HttpClient _client;
  final Map<String, _CachedUser> _cache = {};

  SupabaseTokenVerifier({
    required String supabaseUrl,
    required String anonKey,
    HttpClient? client,
  }) : this._(
         Uri.parse(
           '${supabaseUrl.endsWith('/') ? supabaseUrl.substring(0, supabaseUrl.length - 1) : supabaseUrl}/auth/v1/user',
         ),
         anonKey,
         client ?? HttpClient(),
       );

  SupabaseTokenVerifier._(this._userUri, this._anonKey, this._client);

  @override
  Future<AuthedUser?> verify(String token) async {
    try {
      final now = DateTime.now();
      _cache.removeWhere((_, cached) => !cached.expiresAt.isAfter(now));
      final cached = _cache[token];
      if (cached != null) return cached.user;

      final user = await _fetchUser(token).timeout(_requestTimeout);
      if (user != null) {
        _cache[token] = _CachedUser(
          user: user,
          expiresAt: DateTime.now().add(_cacheTtl),
        );
      }
      return user;
    } catch (_) {
      return null;
    }
  }

  Future<AuthedUser?> _fetchUser(String token) async {
    final request = await _client.getUrl(_userUri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.set('apikey', _anonKey);

    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      return null;
    }

    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    return AuthedUser(
      id: json['id'] as String,
      email: json['email'] as String?,
      isAnonymous: json['is_anonymous'] as bool,
    );
  }
}
