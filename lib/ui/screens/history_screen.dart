/// The signed-in player's most recent recorded online matches.
library;

import 'package:flutter/material.dart';

import '../../account/account.dart';
import '../../account/auth_backend.dart';
import '../../engine/profiles.dart';
import '../account_scope.dart';
import '../app_scope.dart';
import '../copy.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/sheet.dart';
import '../widgets/stage.dart';

sealed class _Fetch<Value> {
  const _Fetch();
}

class _Loading<Value> extends _Fetch<Value> {
  const _Loading();
}

class _Ready<Value> extends _Fetch<Value> {
  final Value value;
  const _Ready(this.value);
}

class _Failed<Value> extends _Fetch<Value> {
  final Object error;
  const _Failed(this.error);
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  _Fetch<List<MatchHistoryEntry>> _fetch = const _Loading();
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    setState(() => _fetch = const _Loading());
    try {
      final entries = await context.account.matchHistory(limit: 10);
      if (!mounted) return;

      setState(
        () => _fetch = _Ready(
          // Product cap rather than a layout one: this read-only screen is the
          // last ten matches, on every device.
          entries.take(10).toList(growable: false),
        ),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _fetch = _Failed(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final l = context.copy;

    return Scaffold(
      body: Room(
        palette: p,
        child: SheetCard(
          width: 720,
          palette: p,
          children: [
            BackLink(
              label: l.back,
              palette: p,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(height: 14),
            Text(
              l.ranked.history,
              style: T.display(34, tracking: -1.4, color: p.text),
            ),
            const SizedBox(height: 16),
            ...switch (_fetch) {
              _Loading() => [
                Center(child: CircularProgressIndicator(color: p.mint)),
              ],
              _Failed(:final error) => [
                Text(
                  _accountError(l.auth, error),
                  style: T.body(13, color: p.pink),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextLink(
                    label: l.ranked.history,
                    palette: p,
                    onTap: _load,
                  ),
                ),
              ],
              _Ready(value: final entries) when entries.isEmpty => [
                Text(l.ranked.noHistory, style: T.body(13, color: p.ash)),
              ],
              _Ready(value: final entries) => [
                for (final entry in entries)
                  _HistoryRow(entry: entry, palette: p, copy: l.ranked),
              ],
            },
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final MatchHistoryEntry entry;
  final Palette palette;
  final RankedCopy copy;

  const _HistoryRow({
    required this.entry,
    required this.palette,
    required this.copy,
  });

  @override
  Widget build(BuildContext context) {
    final (resultLabel, resultColor) = switch (entry.result) {
      'win' => (copy.won, palette.text),
      'loss' => (copy.lost, palette.ashDim),
      _ => (copy.draw, palette.ash),
    };
    final ratingDelta = entry.ratingDelta;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.line)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(resultLabel, style: mono(9, color: resultColor)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${profileById(entry.profileId).label} · '
                  '${entry.numPlayers}P',
                  style: T.title(11, color: palette.text),
                ),
                const SizedBox(height: 2),
                Text(_scoreLine(entry), style: mono(10, color: palette.ash)),
              ],
            ),
          ),
          SizedBox(
            width: 64,
            child: ratingDelta == null
                ? null
                : Text(
                    _signedDelta(ratingDelta),
                    textAlign: TextAlign.right,
                    style: mono(10, color: palette.text),
                  ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 36,
            child: Text(
              _relativeAge(entry.endedAt),
              textAlign: TextAlign.right,
              style: mono(9, color: palette.ashDim),
            ),
          ),
        ],
      ),
    );
  }
}

String _scoreLine(MatchHistoryEntry entry) {
  final scores = entry.finalScores;
  if (scores.isEmpty) return '—';
  if (entry.mySide < 0 || entry.mySide >= scores.length) {
    return scores.join(' — ');
  }
  return [
    scores[entry.mySide],
    for (var side = 0; side < scores.length; side++)
      if (side != entry.mySide) scores[side],
  ].join(' — ');
}

String _signedDelta(int delta) => delta >= 0 ? '+$delta' : '−${delta.abs()}';

String _relativeAge(DateTime endedAt) {
  final difference = DateTime.now().difference(endedAt);
  final age = difference.isNegative ? Duration.zero : difference;
  if (age.inMinutes < 60) return '${age.inMinutes}m';
  if (age.inHours < 24) return '${age.inHours}h';
  return '${age.inDays}d';
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
