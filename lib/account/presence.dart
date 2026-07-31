/// Coarse best-effort presence while the app is open.
library;

import 'dart:async';

import 'account.dart';

/// Beats while the app is open so friends see an online dot. Deliberately
/// coarse: a 30-second timer, 'online' by default, stopped on dispose.
/// Never throws, never blocks anything.
class PresenceHeartbeat {
  final Account _account;
  final Duration _period;
  Timer? _timer;

  factory PresenceHeartbeat({
    required Account account,
    Duration period = const Duration(seconds: 30),
  }) => PresenceHeartbeat._(account, period);

  PresenceHeartbeat._(this._account, this._period);

  /// Starts one immediate beat and the periodic timer. No-op once started.
  void start() {
    if (_timer != null) return;
    try {
      _beat();
      _timer = Timer.periodic(_period, (_) => _beat());
    } on Object {
      stop();
    }
  }

  /// Stops future beats. Safe to call more than once.
  void stop() {
    try {
      _timer?.cancel();
    } on Object {
      // Timer cleanup is best-effort, matching presence itself.
    } finally {
      _timer = null;
    }
  }

  void _beat() {
    if (!_account.signedIn) return;
    unawaited(_account.heartbeat(status: 'online'));
  }
}
