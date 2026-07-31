/// The short-lived ranked matchmaking room.
///
/// It owns every timer and subscription it starts, then hands the resolved room
/// to the same online game screen used by a manually entered table code.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../account/account.dart';
import '../../account/auth_backend.dart';
import '../../engine/profiles.dart';
import '../../env.dart';
import '../../game/game_controller.dart';
import '../../multiplayer/transport.dart';
import '../../multiplayer/websocket_transport.dart';
import '../account_scope.dart';
import '../app_scope.dart';
import '../copy.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/sheet.dart';
import '../widgets/stage.dart';
import 'game_screen.dart';

class QueueScreen extends StatefulWidget {
  final String ladderId;
  final String profileId;
  final int numPlayers;

  /// Test seam: widget tests must not open a real socket, whose connect
  /// machinery arms platform timers no dispose of ours can cancel. Defaults
  /// to the WebSocket transport in the app.
  @visibleForTesting
  final GameTransport Function(String roomCode, String playerName)?
  transportFactory;

  const QueueScreen({
    super.key,
    required this.ladderId,
    required this.profileId,
    required this.numPlayers,
    this.transportFactory,
  });

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  StreamSubscription<QueueTicket>? _subscription;
  Timer? _ellipsisTimer;
  Timer? _elapsedTimer;
  int _dots = 1;
  int _seconds = 0;
  bool _subscribed = false;
  bool _cancelling = false;
  bool _matched = false;
  bool _pushing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ellipsisTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (mounted) setState(() => _dots = _dots % 3 + 1);
    });
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds += 1);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_subscribed) return;
    _subscribed = true;
    _listen();
  }

  void _listen() {
    unawaited(_subscription?.cancel());
    setState(() {
      _error = null;
      _matched = false;
    });
    _subscription = context.account
        .enqueue(widget.ladderId)
        .listen(_onTicket, onError: _onStreamError);
  }

  void _onTicket(QueueTicket ticket) {
    final code = ticket.matchedRoomCode?.trim();
    if (!mounted ||
        ticket.status != 'matched' ||
        code == null ||
        code.isEmpty) {
      return;
    }

    setState(() => _matched = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _join(code);
    });
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    if (!mounted) return;
    setState(() => _error = _accountError(context.copy.auth, error));
  }

  void _join(String roomCode) {
    if (_pushing) return;
    final uri = Uri.tryParse(gameHost);
    if (uri == null ||
        !uri.hasScheme ||
        !(uri.isScheme('ws') || uri.isScheme('wss'))) {
      setState(() {
        _matched = false;
        _error = context.copy.auth.somethingBroke;
      });
      return;
    }

    final l = context.copy;
    final accountName = context.account.displayName?.trim();
    final playerName = accountName == null || accountName.isEmpty
        ? l.onlineDefaultPlayer
        : accountName;
    final cfg = loadProfile(
      widget.profileId,
      numPlayers: widget.numPlayers,
    ).withMatchTarget(context.prefs.target);
    final controller = GameController(
      cfg: cfg,
      autoReady: false,
      transport:
          widget.transportFactory?.call(roomCode, playerName) ??
          WebSocketTransport(
            endpoint: uri,
            roomCode: roomCode,
            playerName: playerName,
          ),
    );

    // Matchmaking already created the room with authoritative ladder rules.
    // The local cfg is only an interim rendering guess until the lobby arrives.
    _pushing = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(controller: controller),
      ),
    );
  }

  Future<void> _cancel() async {
    if (_cancelling || _pushing) return;
    setState(() => _cancelling = true);
    try {
      await context.account.cancelQueue();
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _cancelling = false;
        _error = _accountError(context.copy.auth, error);
      });
    }
  }

  @override
  void dispose() {
    _ellipsisTimer?.cancel();
    _elapsedTimer?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final l = context.copy;
    final minutes = (_seconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_seconds % 60).toString().padLeft(2, '0');
    final status = _matched
        ? l.ranked.matchFound
        : '${l.ranked.searching}${List.filled(_dots, '.').join()}';

    return Scaffold(
      body: Stage(
        palette: p,
        children: [
          Positioned.fill(
            child: SheetCard(
              palette: p,
              children: [
                Text(
                  status,
                  style: T.display(34, tracking: -1.4, color: p.text),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    '$minutes:$seconds',
                    style: mono(24, color: p.mint, tracking: 2),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Text(_error!, style: T.body(13, color: p.pink)),
                  const SizedBox(height: 12),
                  Center(
                    child: TextLink(
                      label: l.ranked.findMatch,
                      palette: p,
                      onTap: _listen,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                MintButton(label: l.ranked.cancel, palette: p, onTap: _cancel),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _accountError(AuthCopy auth, Object error) {
  final kind = error is AccountException ? error.error : AccountError.unknown;
  return switch (kind) {
    AccountError.badEmail => auth.badEmail,
    AccountError.badCode => auth.badCode,
    AccountError.expiredCode => auth.expiredCode,
    AccountError.weakPassword => auth.weakPassword,
    AccountError.wrongPassword => auth.wrongPassword,
    AccountError.accountExists => auth.accountExists,
    AccountError.offline => auth.offline,
    AccountError.unknown => auth.somethingBroke,
  };
}
