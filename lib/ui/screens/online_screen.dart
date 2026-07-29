/// Joining a table hosted somewhere else.
///
/// This is the same [GameScreen] as offline play — only the transport differs.
/// It is wired end to end against `bin/server.dart`; point it at a deployed
/// host and nothing here changes.
library;

import 'package:flutter/material.dart';

import '../../engine/profiles.dart';
import '../../game/game_controller.dart';
import '../../multiplayer/websocket_transport.dart';
import '../theme.dart';
import '../widgets/table_surface.dart';
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
  final _server = TextEditingController(text: 'ws://localhost:8080');
  final _room = TextEditingController(text: 'mesa-1');
  final _name = TextEditingController(text: 'Luiz');
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _room.dispose();
    _name.dispose();
    super.dispose();
  }

  void _join() {
    final uri = Uri.tryParse(_server.text.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !(uri.isScheme('ws') || uri.isScheme('wss'))) {
      setState(
        () => _error = 'The address needs to start with ws:// or wss://',
      );
      return;
    }
    if (_room.text.trim().isEmpty) {
      setState(() => _error = 'Give the table a name so others can find it');
      return;
    }
    setState(() => _error = null);

    final cfg = loadProfile(widget.profileId, numPlayers: widget.numPlayers);
    final transport = WebSocketTransport(
      endpoint: uri,
      roomCode: _room.text.trim(),
      playerName: _name.text.trim().isEmpty ? 'Player' : _name.text.trim(),
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          controller: GameController(cfg: cfg, transport: transport),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TableSurface(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(
                          Icons.arrow_back,
                          color: C.ash,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text('Play online', style: T.display(26, color: C.bone)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: C.line),
                    ),
                    child: Text(
                      'Everyone at a table joins the same host with the same '
                      'table name. To run one on your own machine:\n\n'
                      'dart run bin/server.dart --profile '
                      '${widget.profileId} --players ${widget.numPlayers}',
                      style: T.body(12, color: C.ash),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _Field(label: 'Host address', controller: _server),
                  const SizedBox(height: 14),
                  _Field(label: 'Table name', controller: _room),
                  const SizedBox(height: 14),
                  _Field(label: 'Your name', controller: _name),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!, style: T.body(13, color: C.coringa)),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _join,
                      style: FilledButton.styleFrom(
                        backgroundColor: C.mint,
                        foregroundColor: C.night,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Join the table',
                        style: T.title(15, color: C.night),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const _Field({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Eyebrow(label),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        style: T.body(15, color: C.bone),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.black.withValues(alpha: 0.24),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: C.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: C.mint, width: 2),
          ),
        ),
      ),
    ],
  );
}
