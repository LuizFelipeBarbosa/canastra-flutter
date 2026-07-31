/// Persistence and room-admission services used by the game host.
///
/// The multiplayer engine depends only on this small seam. The default
/// implementation does nothing, keeping local play and unconfigured hosts
/// independent of Supabase.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What the host tells the database.
///
/// Every method is best-effort from the game's point of view: persistence must
/// never delay a move or make a match fail.
abstract class GameBackend {
  /// Redeem a room code for a seat authorization.
  ///
  /// Null means the backend could not be reached and callers may fall back to
  /// open seating. A non-null result with `ok: false` is an explicit refusal.
  Future<Map<String, dynamic>?> authorizeJoin({
    required String roomCode,
    required String userId,
    bool spectator = false,
  });

  /// Deliver a finished match. Implementations retry internally and never
  /// throw.
  Future<void> recordMatchResult(Map<String, dynamic> payload);

  Future<void> dispose();
}

/// Backend used unless persistence is explicitly configured.
class NullBackend implements GameBackend {
  const NullBackend();

  @override
  Future<Map<String, dynamic>?> authorizeJoin({
    required String roomCode,
    required String userId,
    bool spectator = false,
  }) async => null;

  @override
  Future<void> recordMatchResult(Map<String, dynamic> payload) async {}

  @override
  Future<void> dispose() async {}
}

/// Supabase PostgREST implementation for the server process.
class SupabaseGameBackend implements GameBackend {
  static const _requestTimeout = Duration(seconds: 5);
  static const _maxRecordAttempts = 5;

  final Uri _authorizeUri;
  final Uri _recordUri;
  final String _serviceKey;
  final HttpClient _client;
  final Map<Timer, ({String? matchId, Completer<bool> completer})> _backoffs =
      {};
  final Set<String> _cancelledMatchIds = {};
  bool _disposed = false;

  SupabaseGameBackend({
    required String supabaseUrl,
    required String serviceKey,
    HttpClient? client,
  }) : this._(
         _rpcUri(supabaseUrl, 'authorize_room_join'),
         _rpcUri(supabaseUrl, 'record_match_result'),
         serviceKey,
         client ?? HttpClient(),
       );

  SupabaseGameBackend._(
    this._authorizeUri,
    this._recordUri,
    this._serviceKey,
    this._client,
  );

  static Uri _rpcUri(String supabaseUrl, String function) {
    final base = supabaseUrl.endsWith('/')
        ? supabaseUrl.substring(0, supabaseUrl.length - 1)
        : supabaseUrl;
    return Uri.parse('$base/rest/v1/rpc/$function');
  }

  @override
  Future<Map<String, dynamic>?> authorizeJoin({
    required String roomCode,
    required String userId,
    bool spectator = false,
  }) async {
    if (_disposed) return null;
    try {
      final response = await _postJson(_authorizeUri, {
        'p_room_code': roomCode,
        'p_user_id': userId,
        'p_spectator': spectator,
      });
      if (response == null ||
          response.statusCode < HttpStatus.ok ||
          response.statusCode >= HttpStatus.multipleChoices) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      return decoded.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> recordMatchResult(Map<String, dynamic> payload) async {
    if (_disposed) return;
    final rawMatchId = payload['match_id'];
    final matchId = rawMatchId is String ? rawMatchId : null;
    try {
      for (var attempt = 0; attempt < _maxRecordAttempts; attempt++) {
        final response = await _postJson(_recordUri, {'p': payload});
        if (response != null &&
            response.statusCode >= HttpStatus.ok &&
            response.statusCode < HttpStatus.multipleChoices) {
          if (matchId != null) _cancelledMatchIds.remove(matchId);
          return;
        }
        if (_takeCancellation(matchId)) return;

        if (attempt < _maxRecordAttempts - 1) {
          final shouldContinue = await _waitBeforeRetry(
            Duration(seconds: 2 * (1 << attempt)),
            matchId: matchId,
          );
          if (!shouldContinue) {
            if (matchId != null) _cancelledMatchIds.remove(matchId);
            return;
          }
        }
      }
    } catch (_) {
      // The recovery log below is intentionally the final failure path.
    }

    if (!_disposed && !_takeCancellation(matchId)) {
      stdout.writeln('UNRECORDED-MATCH ${jsonEncode(payload)}');
    }
  }

  Future<({int statusCode, String body})?> _postJson(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    if (_disposed) return null;
    try {
      final request = await _client.postUrl(uri).timeout(_requestTimeout);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $_serviceKey',
      );
      request.headers.set('apikey', _serviceKey);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));

      final response = await request.close().timeout(_requestTimeout);
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
      return (statusCode: response.statusCode, body: responseBody);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _waitBeforeRetry(Duration duration, {String? matchId}) {
    if (_disposed ||
        (matchId != null && _cancelledMatchIds.contains(matchId))) {
      return Future.value(false);
    }
    final completer = Completer<bool>();
    late final Timer timer;
    timer = Timer(duration, () {
      _backoffs.remove(timer);
      completer.complete(!_disposed);
    });
    _backoffs[timer] = (matchId: matchId, completer: completer);
    return completer.future;
  }

  /// Cancel retry backoffs for a room-owned match that no longer exists.
  void cancelPendingMatchResult(String matchId) {
    _cancelledMatchIds.add(matchId);
    for (final entry in _backoffs.entries.toList()) {
      if (entry.value.matchId != matchId) continue;
      entry.key.cancel();
      _backoffs.remove(entry.key);
      if (!entry.value.completer.isCompleted) {
        entry.value.completer.complete(false);
      }
    }
  }

  bool _takeCancellation(String? matchId) =>
      matchId != null && _cancelledMatchIds.remove(matchId);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final entry in _backoffs.entries.toList()) {
      entry.key.cancel();
      if (!entry.value.completer.isCompleted) {
        entry.value.completer.complete(false);
      }
    }
    _backoffs.clear();
    _cancelledMatchIds.clear();
    _client.close(force: true);
  }
}
