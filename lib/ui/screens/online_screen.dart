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
import '../../game/game_controller.dart';
import '../../multiplayer/websocket_transport.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/stage.dart';
import 'game_screen.dart';

/// Where this build looks for its host.
///
/// Baked in at compile time rather than typed by the player:
/// `flutter build web --dart-define=GAME_HOST=wss://your-host`. The default is
/// what `dart run bin/server.dart` gives you during development.
///
/// A build served over https must use `wss://` — browsers refuse a plaintext
/// socket from a secure page.
const gameHost = String.fromEnvironment(
  'GAME_HOST',
  defaultValue: 'ws://localhost:8080',
);

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

  @override
  void dispose() {
    _room.dispose();
    _name.dispose();
    super.dispose();
  }

  void _join() {
    final uri = Uri.tryParse(gameHost);
    if (uri == null ||
        !uri.hasScheme ||
        !(uri.isScheme('ws') || uri.isScheme('wss'))) {
      setState(() => _error = 'This build has no usable host address.');
      return;
    }
    if (_room.text.trim().isEmpty) {
      setState(() => _error = 'Give the table a name so others can find it.');
      return;
    }
    setState(() => _error = null);

    final cfg = loadProfile(
      widget.profileId,
      numPlayers: _players,
    ).withMatchTarget(context.prefs.target);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          controller: GameController(
            cfg: cfg,
            transport: WebSocketTransport(
              endpoint: uri,
              roomCode: _room.text.trim(),
              playerName: _name.text.trim().isEmpty
                  ? 'Player'
                  : _name.text.trim(),
            ),
          ),
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
            child: Center(
              child: Container(
                width: 520,
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 36,
                ),
                decoration: BoxDecoration(
                  color: p.sheet,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: p.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
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
                    Text(
                      'Everyone playing together joins the same table name. '
                      'Pick one and share it — play starts once every seat is '
                      'ready.',
                      style: T.body(13, color: p.ash),
                    ),
                    const SizedBox(height: 20),
                    if (counts.length > 1) ...[
                      Text('PLAYERS', style: mono(10, color: p.ashDim)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (final n in counts) ...[
                            if (n != counts.first) const SizedBox(width: 8),
                            Segment(
                              label: n == 2 ? '2 · HEAD TO HEAD' : '4 · TEAMS',
                              selected: n == _players,
                              palette: p,
                              onTap: () => setState(() => _players = n),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                    _Field(label: 'TABLE NAME', controller: _room, palette: p),
                    const SizedBox(height: 14),
                    _Field(
                      label: 'YOUR NAME',
                      controller: _name,
                      hint: 'How others see you',
                      palette: p,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, style: T.body(13, color: p.pink)),
                    ],
                    const SizedBox(height: 24),
                    MintButton(
                      label: 'Join the table',
                      palette: p,
                      onTap: _join,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final Palette palette;

  const _Field({
    required this.label,
    required this.controller,
    required this.palette,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: mono(10, color: p.ashDim)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          style: T.body(15, color: p.text),
          decoration: InputDecoration(
            filled: true,
            hintText: hint,
            hintStyle: T.body(15, color: p.ashDim),
            fillColor: p.panel,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: p.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: p.mint, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
