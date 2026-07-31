/// Joining a table hosted somewhere else.
///
/// The same [GameScreen] as offline play — only the transport differs. It is also
/// the only way to a four-handed or pass-and-play table, so the seat count is
/// chosen here rather than on the setup screen, which the design keeps to a single
/// head-to-head game.
///
/// Not part of the Buraco Livre design, so it borrows that design's sheet rather
/// than inventing a third look.
library;

import 'package:flutter/material.dart';

import '../../account/account.dart';
import '../../engine/profiles.dart';
import '../../env.dart';
import '../../game/game_controller.dart';
import '../../multiplayer/websocket_transport.dart';
import '../account_scope.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/sheet.dart';
import '../widgets/stage.dart';
import 'game_screen.dart';
import 'leaderboard_screen.dart';
import 'queue_screen.dart';

class OnlineScreen extends StatefulWidget {
  final String profileId;
  final int numPlayers;

  const OnlineScreen({
    super.key,
    required this.profileId,
    required this.numPlayers,
  });

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  final _room = TextEditingController(text: 'mesa-1');
  final _name = TextEditingController();
  String? _error;
  late int _players = widget.numPlayers;
  bool _pushing = false;
  bool _creating = false;
  bool _prefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;

    final account = context.account;
    final name = account.signedIn ? account.displayName?.trim() : null;
    if (name != null && name.isNotEmpty) _name.text = name;
  }

  @override
  void dispose() {
    _room.dispose();
    _name.dispose();
    super.dispose();
  }

  /// Ask the backend for a fresh table and drop its code into the field, so
  /// creating and joining share one path: the code the server minted is the
  /// room code the host sees.
  Future<void> _create() async {
    if (_pushing || _creating) return;

    final account = context.account;
    final target = context.prefs.target;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final code = await account.createRoom(
        profileId: widget.profileId,
        numPlayers: _players,
        matchTarget: target,
      );
      if (!mounted) return;
      _room.text = code;
      await _join();
    } on AccountException {
      if (!mounted) return;
      setState(() => _error = context.copy.auth.somethingBroke);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _join({bool spectate = false}) async {
    if (_pushing) return;

    final l = context.copy;
    final uri = Uri.tryParse(gameHost);
    if (uri == null ||
        !uri.hasScheme ||
        !(uri.isScheme('ws') || uri.isScheme('wss'))) {
      setState(() => _error = l.onlineInvalidHost);
      return;
    }
    if (_room.text.trim().isEmpty) {
      setState(() => _error = l.onlineMissingTableName);
      return;
    }
    setState(() => _error = null);

    final target = context.prefs.target;
    final cfg = loadProfile(
      widget.profileId,
      numPlayers: _players,
    ).withMatchTarget(target);
    // The declared rules only matter when this join creates the room — an
    // existing room ignores them and the lobby reports the real ones, which
    // the controller adopts. Online tables always wait in the lobby.
    final controller = GameController(
      cfg: cfg,
      autoReady: false,
      transport: WebSocketTransport(
        endpoint: uri,
        roomCode: _room.text.trim(),
        playerName: _name.text.trim().isEmpty
            ? l.onlineDefaultPlayer
            : _name.text.trim(),
        spectate: spectate,
        profileId: widget.profileId,
        numPlayers: _players,
        matchTarget: target,
      ),
    );
    _pushing = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GameScreen(controller: controller),
        ),
      );
    } finally {
      _pushing = false;
    }
  }

  void _findMatch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QueueScreen(
          ladderId: '${widget.profileId}:$_players:ranked',
          profileId: widget.profileId,
          numPlayers: _players,
        ),
      ),
    );
  }

  void _leaderboard() {
    final profile = profileById(widget.profileId);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LeaderboardScreen(
          ladderId: '${widget.profileId}:$_players:ranked',
          ladderLabel: '${profile.label} · $_players',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.prefs;
    final p = prefs.palette;
    final l = prefs.copy;
    final counts = profileById(widget.profileId).playerCounts;

    return Scaffold(
      body: Stage(
        palette: p,
        children: [
          Positioned.fill(
            child: SheetCard(
              palette: p,
              children: [
                BackLink(
                  label: l.back,
                  palette: p,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(height: 20),
                Text(
                  l.online,
                  style: T.display(34, tracking: -1.4, color: p.text),
                ),
                const SizedBox(height: 20),
                Text(l.onlineExplainer, style: T.body(13, color: p.ash)),
                const SizedBox(height: 20),
                if (counts.length > 1) ...[
                  ChoiceField(
                    label: l.onlinePlayers,
                    palette: p,
                    children: [
                      for (final n in counts)
                        Segment(
                          label: n == 2
                              ? l.onlineTwoPlayers
                              : l.onlineFourPlayers,
                          selected: n == _players,
                          palette: p,
                          onTap: () => setState(() => _players = n),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
                TextEntry(
                  label: l.onlineTableName,
                  controller: _room,
                  palette: p,
                ),
                const SizedBox(height: 14),
                TextEntry(
                  label: l.onlineYourName,
                  controller: _name,
                  hint: l.onlinePlayerNameHint,
                  palette: p,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: T.body(13, color: p.pink)),
                ],
                const SizedBox(height: 24),
                MintButton(label: l.onlineJoinTable, palette: p, onTap: _join),
                // Ranked play requires a permanent account. Guests and
                // signed-out players get no client entry point, and the enqueue
                // RPC independently enforces the same rule server-side.
                if (context.account.state is Player) ...[
                  const SizedBox(height: 14),
                  Center(
                    child: TextLink(
                      label: l.ranked.findMatch,
                      palette: p,
                      color: p.ashDim,
                      onTap: _findMatch,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: TextLink(
                      label: l.ranked.leaderboard,
                      palette: p,
                      color: p.ashDim,
                      onTap: _leaderboard,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Center(
                  child: TextLink(
                    label: l.onlineWatchTable,
                    palette: p,
                    color: p.ashDim,
                    onTap: () => _join(spectate: true),
                  ),
                ),
                // Creating needs an account: the server mints the code against
                // the signed-in owner. A signed-out player can still join any
                // table whose name or code they were given.
                if (hasBackend && context.account.signedIn) ...[
                  const SizedBox(height: 14),
                  Center(
                    child: TextLink(
                      label: _creating ? l.onlineCreating : l.onlineCreateTable,
                      palette: p,
                      color: p.ashDim,
                      onTap: _create,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
