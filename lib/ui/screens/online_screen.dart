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

  Future<void> _join() async {
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

    final cfg = loadProfile(
      widget.profileId,
      numPlayers: _players,
    ).withMatchTarget(context.prefs.target);
    final controller = GameController(
      cfg: cfg,
      transport: WebSocketTransport(
        endpoint: uri,
        roomCode: _room.text.trim(),
        playerName: _name.text.trim().isEmpty
            ? l.onlineDefaultPlayer
            : _name.text.trim(),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
