/// The end-of-round score sheet, and the end-of-match one.
///
/// Buraco scoring is the part people argue about, so every line the engine
/// counted is shown with its sign rather than summarised into a single number.
library;

import 'package:flutter/material.dart';

import '../../multiplayer/table_view.dart';
import '../theme.dart';

class RoundSheet extends StatelessWidget {
  final TableView view;
  final VoidCallback onContinue;

  const RoundSheet({super.key, required this.view, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final result = view.roundResult;
    final matchOver = view.matchOver;
    final iWon = matchOver
        ? view.winnerSide == view.side
        : result?.wentOutSide == view.side;

    final String headline;
    if (matchOver) {
      headline = iWon ? 'You win the match' : 'You lost the match';
    } else if (result?.wentOutSide == null) {
      headline = 'The stock ran out';
    } else {
      headline = iWon ? 'You went out' : 'They went out';
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      decoration: const BoxDecoration(
        color: C.night,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: C.line)),
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
                color: C.ashDim,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Eyebrow(
            matchOver ? 'Final' : 'Round ${(result?.roundIndex ?? 0) + 1}',
          ),
          const SizedBox(height: 6),
          Text(headline, style: T.display(28, color: iWon ? C.limpa : C.bone)),
          const SizedBox(height: 22),
          if (result != null)
            for (final sheet in result.sheets) ...[
              _SideBlock(
                title: _sideName(view, sheet.side),
                sheet: sheet,
                highlight: sheet.side == view.side,
              ),
              const SizedBox(height: 16),
            ],
          const Divider(color: C.line, height: 24),
          Row(
            children: [
              Eyebrow('Match  ·  first to ${view.matchTarget}'),
              const Spacer(),
              for (var side = 0; side < view.matchScores.length; side++)
                Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Text(
                    '${view.matchScores[side]}',
                    style: T.mono(
                      18,
                      color: side == view.side ? C.mint : C.ash,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onContinue,
              style: FilledButton.styleFrom(
                backgroundColor: C.mint,
                foregroundColor: C.night,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                matchOver ? 'Play again' : 'Deal the next round',
                style: T.title(15, color: C.night),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _sideName(TableView view, int side) {
    if (side == view.side) return view.numPlayers == 4 ? 'Your team' : 'You';
    return view.numPlayers == 4 ? 'Their team' : 'Opponent';
  }
}

class _SideBlock extends StatelessWidget {
  final String title;
  final ScoreSheetView sheet;
  final bool highlight;

  const _SideBlock({
    required this.title,
    required this.sheet,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: highlight ? 0.05 : 0.02),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: highlight ? C.mint.withValues(alpha: 0.4) : C.line,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: T.title(15, color: C.bone)),
            const Spacer(),
            Text(
              sheet.total >= 0 ? '+${sheet.total}' : '${sheet.total}',
              style: T.mono(17, color: sheet.total >= 0 ? C.mint : C.coringa),
            ),
          ],
        ),
        if (sheet.lines.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Nothing scored', style: T.body(12, color: C.ashDim)),
          ),
        for (final line in sheet.lines)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(line.$1, style: T.body(13, color: C.ash)),
                ),
                Text(
                  line.$2 >= 0 ? '+${line.$2}' : '${line.$2}',
                  style: T.mono(12, color: line.$2 >= 0 ? C.ash : C.coringa),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
