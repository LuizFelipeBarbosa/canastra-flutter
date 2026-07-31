/// The ranked ladder, deliberately bounded to one compact table.
library;

import 'package:flutter/material.dart';

import '../../account/account.dart';
import '../../account/auth_backend.dart';
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

typedef _LeaderboardData = ({List<LeaderboardEntry> entries, RankInfo? myRank});

class LeaderboardScreen extends StatefulWidget {
  final String ladderId;
  final String ladderLabel;

  const LeaderboardScreen({
    super.key,
    required this.ladderId,
    required this.ladderLabel,
  });

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  _Fetch<_LeaderboardData> _fetch = const _Loading();
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
      final account = context.account;
      final entriesFuture = account.leaderboard(widget.ladderId, limit: 20);
      final rankFuture = account.myRank(widget.ladderId);
      final entries = await entriesFuture;
      final rank = await rankFuture;
      if (!mounted) return;

      setState(
        () => _fetch = _Ready((
          // Product cap: the Stage is a fixed 1240x790 coordinate space, so
          // ranked play intentionally shows one top-20 page on every device.
          entries: entries.take(20).toList(growable: false),
          myRank: rank,
        )),
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
      body: Stage(
        palette: p,
        children: [
          Positioned.fill(
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
                  l.ranked.leaderboard,
                  style: T.display(34, tracking: -1.4, color: p.text),
                ),
                const SizedBox(height: 5),
                Text(widget.ladderLabel, style: mono(10, color: p.ashDim)),
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
                        label: l.ranked.leaderboard,
                        palette: p,
                        onTap: _load,
                      ),
                    ),
                  ],
                  _Ready(:final value) => _readyRows(
                    value,
                    context.account.user?.id,
                    p,
                    l.ranked,
                  ),
                },
              ],
            ),
          ),
        ],
      ),
    );
  }
}

List<Widget> _readyRows(
  _LeaderboardData data,
  String? userId,
  Palette p,
  RankedCopy copy,
) => [
  Row(
    children: [
      SizedBox(
        width: 44,
        child: Text('#', style: mono(9, color: p.ashDim)),
      ),
      const SizedBox(width: 10),
      const Expanded(child: SizedBox()),
      SizedBox(
        width: 78,
        child: Text(
          copy.rating,
          textAlign: TextAlign.right,
          style: mono(9, color: p.ashDim),
        ),
      ),
      const SizedBox(width: 20),
      const SizedBox(width: 100),
    ],
  ),
  const SizedBox(height: 5),
  for (final entry in data.entries)
    _LeaderboardRow(
      entry: entry,
      highlighted: data.myRank != null && entry.userId == userId,
      palette: p,
      copy: copy,
    ),
  const SizedBox(height: 14),
  if (data.myRank case final rank?)
    Center(
      child: Text(
        copy.yourRank(rank.rank, rank.percentile.round()),
        style: mono(11, color: p.mint),
      ),
    )
  else
    Center(
      child: Text(copy.unranked, style: T.body(12, color: p.ash)),
    ),
];

class _LeaderboardRow extends StatelessWidget {
  final LeaderboardEntry entry;
  final bool highlighted;
  final Palette palette;
  final RankedCopy copy;

  const _LeaderboardRow({
    required this.entry,
    required this.highlighted,
    required this.palette,
    required this.copy,
  });

  @override
  Widget build(BuildContext context) {
    final username = entry.username?.trim();
    final name = username == null || username.isEmpty
        ? entry.displayName
        : username;
    final losses = entry.games - entry.wins;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: highlighted ? palette.panelHot : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              '${entry.rank}',
              style: mono(10, color: highlighted ? palette.mint : palette.ash),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.title(12, color: palette.text),
            ),
          ),
          SizedBox(
            width: 78,
            child: Text(
              '${entry.rating}',
              textAlign: TextAlign.right,
              style: mono(10, color: palette.text),
            ),
          ),
          const SizedBox(width: 20),
          SizedBox(
            width: 100,
            child: Text(
              '${entry.wins}${copy.wins} - $losses${copy.losses}',
              textAlign: TextAlign.right,
              style: mono(9, color: palette.ash),
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
