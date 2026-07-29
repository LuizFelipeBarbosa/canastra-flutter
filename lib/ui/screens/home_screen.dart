/// Table setup.
///
/// Four games share one engine, so the choice that matters is which rules are
/// in force — that gets the most room, with each variant described by what
/// actually differs at the table rather than by a genre label.
library;

import 'package:flutter/material.dart';

import '../../ai/agent.dart';
import '../../engine/profiles.dart';
import '../../game/game_controller.dart';
import '../../multiplayer/local_transport.dart';
import '../theme.dart';
import '../widgets/table_surface.dart';
import 'game_screen.dart';
import 'online_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _profileId = 'buraco';
  int _players = 2;
  AgentLevel _level = AgentLevel.normal;
  bool _hotSeat = false;

  GameProfile get _profile => profileById(_profileId);

  void _selectProfile(GameProfile p) {
    setState(() {
      _profileId = p.id;
      if (!p.playerCounts.contains(_players)) _players = p.playerCounts.first;
      if (!p.playerCounts.contains(2) && _hotSeat) _hotSeat = false;
    });
  }

  void _deal() {
    final cfg = _profile.build(numPlayers: _players);
    // A visible seed would let players compare deals; an invisible one just has
    // to differ between games.
    final seed = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;

    final transport = _hotSeat
        ? HotSeatTransport.table(
            cfg: cfg,
            seed: seed,
            names: [for (var i = 0; i < _players; i++) 'Player ${i + 1}'],
            botLevel: _level,
          )
        : LocalTransport.singlePlayer(cfg: cfg, seed: seed, botLevel: _level);

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
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('The Buraco family'),
                  const SizedBox(height: 8),
                  Text('CANASTRA', style: T.display(52, color: C.bone)),
                  const SizedBox(height: 6),
                  Text(
                    'Four games, one deck of rules. Pick your table.',
                    style: T.body(15, color: C.ash),
                  ),
                  const SizedBox(height: 28),

                  for (final p in kProfiles) ...[
                    _ProfileCard(
                      profile: p,
                      selected: p.id == _profileId,
                      onTap: () => _selectProfile(p),
                    ),
                    const SizedBox(height: 10),
                  ],

                  const SizedBox(height: 18),
                  const Eyebrow('Players'),
                  const SizedBox(height: 8),
                  _Segmented<int>(
                    values: _profile.playerCounts,
                    selected: _players,
                    label: (n) => n == 2 ? '2 · head to head' : '4 · two teams',
                    onChanged: (n) => setState(() => _players = n),
                  ),

                  const SizedBox(height: 18),
                  const Eyebrow('Opponents'),
                  const SizedBox(height: 8),
                  _Segmented<AgentLevel>(
                    values: AgentLevel.values,
                    selected: _level,
                    label: (l) => switch (l) {
                      AgentLevel.easy => 'Loose',
                      AgentLevel.normal => 'Steady',
                      AgentLevel.hard => 'Sharp',
                    },
                    onChanged: (l) => setState(() => _level = l),
                  ),

                  const SizedBox(height: 18),
                  _PassAndPlay(
                    value: _hotSeat,
                    onChanged: (v) => setState(() => _hotSeat = v),
                  ),

                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _deal,
                      style: FilledButton.styleFrom(
                        backgroundColor: C.limpa,
                        foregroundColor: C.night,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text('Deal', style: T.display(18, color: C.night)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => OnlineScreen(
                            profileId: _profileId,
                            numPlayers: _players,
                          ),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: C.mint,
                        side: const BorderSide(color: C.line),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Play online',
                        style: T.title(15, color: C.mint),
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

class _ProfileCard extends StatelessWidget {
  final GameProfile profile;
  final bool selected;
  final VoidCallback onTap;

  const _ProfileCard({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.quick),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: selected ? 0.34 : 0.18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? C.mint : C.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  profile.label,
                  style: T.title(20, color: selected ? C.bone : C.ash),
                ),
                const SizedBox(width: 10),
                // The tagline yields first when the card is too narrow for
                // both; the game's name must never be the thing that clips.
                Flexible(
                  child: Text(
                    profile.tagline.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: T.mono(10, color: selected ? C.mint : C.ashDim),
                  ),
                ),
              ],
            ),
            if (selected) ...[
              const SizedBox(height: 8),
              Text(profile.blurb, style: T.body(13, color: C.ash)),
            ],
          ],
        ),
      ),
    ),
  );
}

class _Segmented<V> extends StatelessWidget {
  final List<V> values;
  final V selected;
  final String Function(V) label;
  final ValueChanged<V> onChanged;

  const _Segmented({
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final v in values)
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: v == values.last ? 0 : 8),
            child: GestureDetector(
              onTap: () => onChanged(v),
              child: AnimatedContainer(
                duration: Motion.of(context, Motion.quick),
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: v == selected
                      ? C.mint.withValues(alpha: 0.16)
                      : Colors.black.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: v == selected ? C.mint : C.line),
                ),
                child: Text(
                  label(v),
                  style: T.mono(11, color: v == selected ? C.mint : C.ash),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _PassAndPlay extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PassAndPlay({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onChanged(!value),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: value ? C.mint : C.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pass and play', style: T.title(14, color: C.bone)),
                const SizedBox(height: 2),
                Text(
                  'Everyone shares this device, one seat at a time.',
                  style: T.body(12, color: C.ashDim),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: C.night,
            activeTrackColor: C.mint,
          ),
        ],
      ),
    ),
  );
}
