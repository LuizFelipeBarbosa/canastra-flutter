/// The end-of-round score sheet, and the end-of-match one.
///
/// Buraco scoring is the part people argue about, so every line the engine counted
/// is shown with its sign rather than summarised into a single number. The sheet
/// rises over the final state of the table rather than replacing it, because the
/// cards are the evidence for the arithmetic.
library;

import 'package:flutter/material.dart';

import '../../multiplayer/table_view.dart';
import '../copy.dart';
import '../theme.dart';
import '../widgets/controls.dart';

class RoundSheet extends StatefulWidget {
  final TableView view;
  final Palette palette;
  final Copy copy;
  final VoidCallback onContinue;

  const RoundSheet({
    super.key,
    required this.view,
    required this.palette,
    required this.copy,
    required this.onContinue,
  });

  @override
  State<RoundSheet> createState() => _RoundSheetState();
}

class _RoundSheetState extends State<RoundSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rise = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  bool _started = false;

  // Reduce-motion comes from the MediaQuery, which is not readable from
  // initState.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
      _rise.value = 1;
      return;
    }
    // Let the last card land before the sheet covers it.
    Future<void>.delayed(const Duration(milliseconds: 450), () {
      if (mounted) _rise.forward();
    });
  }

  @override
  void dispose() {
    _rise.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final view = widget.view;
    final l = widget.copy;
    final result = view.roundResult;

    final iWon = view.matchOver
        ? view.winnerSide == view.side
        : result?.wentOutSide == view.side;

    final String headline;
    if (view.matchOver) {
      headline = iWon ? l.youWinMatch : l.youLostMatch;
    } else if (result?.wentOutSide == null) {
      headline = l.stockRanOut;
    } else {
      headline = iWon
          ? l.youWent
          : l.theyWent(_sideName(view, l, result!.wentOutSide!));
    }

    return AnimatedBuilder(
      animation: _rise,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_rise.value);
        if (t == 0) return const SizedBox.shrink();
        return ColoredBox(
          color: p.scrim.withValues(alpha: p.scrim.a * t),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Transform.translate(
              offset: Offset(0, 10 * (1 - t)),
              child: Opacity(opacity: t, child: child),
            ),
          ),
        );
      },
      child: Container(
        width: 620,
        padding: const EdgeInsets.fromLTRB(32, 22, 32, 34),
        decoration: BoxDecoration(
          color: p.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: p.line)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: p.ashDim,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '${l.round} ${(result?.roundIndex ?? view.roundIndex) + 1}',
              style: mono(10, color: p.ashDim),
            ),
            const SizedBox(height: 6),
            Text(
              headline,
              style: T.display(
                30,
                tracking: -1.2,
                color: iWon ? p.gold : p.ash,
              ),
            ),
            const SizedBox(height: 22),
            if (result != null)
              for (final sheet in result.sheets) ...[
                _SideBlock(
                  name: _sideName(view, l, sheet.side),
                  sheet: sheet,
                  mine: sheet.side == view.side,
                  winner: sheet.side == result.wentOutSide,
                  palette: p,
                  copy: l,
                ),
                const SizedBox(height: 14),
              ],
            Container(height: 1, color: p.line),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${l.matchLine}${view.matchTarget}',
                    style: mono(10, color: p.ashDim),
                  ),
                ),
                for (var side = 0; side < view.matchScores.length; side++)
                  Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: Text(
                      '${view.matchScores[side]}',
                      style: mono(
                        18,
                        color: side == view.side ? p.mint : p.ash,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            MintButton(
              label: view.matchOver ? l.newMatch : l.nextRound,
              palette: p,
              onTap: widget.onContinue,
            ),
          ],
        ),
      ),
    );
  }

  static String _sideName(TableView view, Copy l, int side) {
    if (side == view.side) return l.you;
    // A named opponent beats "them" — it is who you actually played.
    final seats = [
      for (var seat = 0; seat < view.numPlayers; seat++)
        if (seat != view.seat && seat != view.partnerSeat) seat,
    ];
    if (view.numPlayers == 2 &&
        seats.isNotEmpty &&
        seats.first < view.playerNames.length) {
      return view.playerNames[seats.first];
    }
    return l.them;
  }
}

class _SideBlock extends StatelessWidget {
  final String name;
  final ScoreSheetView sheet;
  final bool mine;
  final bool winner;
  final Palette palette;
  final Copy copy;

  const _SideBlock({
    required this.name,
    required this.sheet,
    required this.mine,
    required this.winner,
    required this.palette,
    required this.copy,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: mine ? p.panelHot : p.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: winner ? p.mint : p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name, style: T.title(15, color: p.text)),
              ),
              Text(
                sheet.total >= 0 ? '+${sheet.total}' : '${sheet.total}',
                style: mono(
                  17,
                  color: sheet.total < 0
                      ? p.pink
                      : mine
                      ? p.mint
                      : p.ash,
                ),
              ),
            ],
          ),
          for (final line in sheet.lines)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      // The engine names its own lines; this only translates
                      // them, and shows the engine's wording if a new line
                      // appears that this file has not been taught yet.
                      copy.scoreLines[line.$1] ?? line.$1,
                      style: T.body(13, color: p.ash),
                    ),
                  ),
                  Text(
                    line.$2 >= 0 ? '+${line.$2}' : '${line.$2}',
                    style: mono(12, color: line.$2 < 0 ? p.pink : p.ash),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
