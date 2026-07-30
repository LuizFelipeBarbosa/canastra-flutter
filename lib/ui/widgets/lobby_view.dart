/// The table before the cards are dealt.
///
/// A lobby belongs on the felt, but unlike the card table it remains useful in
/// portrait: this is where a phone player reads and shares the room code.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../game/game_controller.dart';
import '../../multiplayer/protocol.dart';
import '../copy.dart';
import '../theme.dart';
import 'controls.dart';
import 'sheet.dart';
import 'stage.dart';

class LobbyView extends StatefulWidget {
  final GameController controller;
  final Palette palette;
  final Copy copy;
  final VoidCallback? onLeave;

  const LobbyView({
    super.key,
    required this.controller,
    required this.palette,
    required this.copy,
    this.onLeave,
  });

  @override
  State<LobbyView> createState() => _LobbyViewState();
}

class _LobbyViewState extends State<LobbyView> {
  Timer? _copiedTimer;
  bool _codeCopied = false;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    _copiedTimer?.cancel();
    setState(() => _codeCopied = true);
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _codeCopied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final lobby = controller.lobby;
    if (lobby == null) return const SizedBox.shrink();

    final p = widget.palette;
    final l = widget.copy.lobby;
    final seats = [
      for (var seat = 0; seat < lobby.numPlayers; seat++)
        _seatAt(lobby.seats, seat),
    ];
    final everyoneReady = seats.every(
      (seat) => seat != null && (seat.kind == SeatKind.bot || seat.ready),
    );
    final target = lobby.matchTarget ?? controller.cfg.scoring.matchTarget;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: groundGradient(p)),
        child: CustomPaint(
          painter: AzulejoPainter(ink: p.motifInk),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final panelWidth = (constraints.maxWidth - 32)
                    .clamp(0.0, 520.0)
                    .toDouble();
                final minHeight = (constraints.maxHeight - 32)
                    .clamp(0.0, double.infinity)
                    .toDouble();
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minHeight),
                    child: SheetCard(
                      width: panelWidth,
                      palette: p,
                      children: [
                        Text(
                          l.title,
                          style: T.display(28, tracking: -0.8, color: p.text),
                        ),
                        const SizedBox(height: 28),
                        FieldLabel(label: l.codeLabel, palette: p),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                lobby.roomCode,
                                overflow: TextOverflow.ellipsis,
                                style: mono(30, tracking: 4, color: p.text),
                              ),
                            ),
                            const SizedBox(width: 16),
                            TextLink(
                              label: l.copyCode,
                              palette: p,
                              onTap: () => _copyCode(lobby.roomCode),
                            ),
                          ],
                        ),
                        SizedBox(
                          height: 20,
                          child: _codeCopied
                              ? Text(
                                  l.codeCopied,
                                  style: mono(9, color: p.mint),
                                )
                              : null,
                        ),
                        Text(
                          l.tableLine(_profileLabel(lobby.profile), target),
                          style: T.body(14, color: p.ash),
                        ),
                        const SizedBox(height: 20),
                        for (var seat = 0; seat < seats.length; seat++) ...[
                          _SeatRow(
                            info: seats[seat],
                            mine: controller.seat == seat,
                            palette: p,
                            copy: l,
                          ),
                          if (seat != seats.length - 1)
                            const SizedBox(height: 8),
                        ],
                        if (controller.notice != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            controller.notice!,
                            style: T.body(12, color: p.pink),
                          ),
                        ],
                        const SizedBox(height: 24),
                        MintButton(
                          label: controller.myReady ? l.unready : l.ready,
                          palette: p,
                          onTap: () => controller.setReady(!controller.myReady),
                        ),
                        if (!everyoneReady) ...[
                          const SizedBox(height: 12),
                          Center(
                            child: Text(
                              l.waiting,
                              style: T.body(12, color: p.ashDim),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Center(
                          child: TextLink(
                            label: l.leave,
                            palette: p,
                            color: p.ashDim,
                            onTap: widget.onLeave ?? controller.leave,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SeatRow extends StatelessWidget {
  final SeatInfo? info;
  final bool mine;
  final Palette palette;
  final LobbyCopy copy;

  const _SeatRow({
    required this.info,
    required this.mine,
    required this.palette,
    required this.copy,
  });

  @override
  Widget build(BuildContext context) {
    final seat = info;
    final occupied = seat != null && seat.kind != SeatKind.empty;
    final connected = occupied && seat.connected;
    final name = occupied && seat.name.trim().isNotEmpty
        ? seat.name
        : copy.openSeat;

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: mine ? palette.panelHot : palette.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        children: [
          Semantics(
            label: connected ? copy.connected : copy.disconnected,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: connected ? palette.mint : palette.ashDim,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: occupied
                  ? T.title(14, color: palette.text)
                  : T.body(14, color: palette.ashDim),
            ),
          ),
          SizedBox(
            width: 24,
            child: Text(
              seat?.ready == true ? '✓' : '',
              textAlign: TextAlign.center,
              style: mono(16, color: palette.mint),
            ),
          ),
        ],
      ),
    );
  }
}

SeatInfo? _seatAt(List<SeatInfo> seats, int number) {
  for (final seat in seats) {
    if (seat.seat == number) return seat;
  }
  return null;
}

String _profileLabel(String profile) {
  final words = profile
      .trim()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(RegExp(r'\s+'));
  return [
    for (final word in words)
      if (word.isNotEmpty)
        '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
  ].join(' ');
}
