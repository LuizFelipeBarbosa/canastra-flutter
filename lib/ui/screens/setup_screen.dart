/// Setting the table.
///
/// Three decisions, in the order they matter: how hard the opponent plays, how
/// long the match runs, and how the app looks and sounds while you play it. The
/// rules were already chosen on the way in, so this screen names them once in the
/// corner and then stays out of the way.
library;

import 'package:flutter/material.dart';

import '../../engine/profiles.dart';
import '../../game/game_controller.dart';
import '../../multiplayer/local_transport.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/stage.dart';
import 'game_screen.dart';
import 'online_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool _pushing = false;

  @override
  Widget build(BuildContext context) {
    final prefs = context.prefs;
    final p = prefs.palette;
    final l = prefs.copy;
    final profile = profileById(prefs.variant);

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
                    Row(
                      children: [
                        BackLink(
                          label: l.back,
                          palette: p,
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                        const Spacer(),
                        Text(
                          profile.label,
                          style: mono(10, color: p.mint, tracking: 1.6),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      l.setupTitle,
                      style: T.display(34, tracking: -1.4, color: p.text),
                    ),
                    const SizedBox(height: 20),

                    _Field(
                      label: l.opponent,
                      palette: p,
                      children: [
                        for (var i = 0; i < l.levels.length; i++)
                          Segment(
                            label: l.levels[i],
                            selected: i == prefs.level,
                            palette: p,
                            onTap: () => prefs.setLevel(i),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    _Field(
                      label: l.target,
                      palette: p,
                      children: [
                        for (final t in kTargets)
                          Segment(
                            label: '$t',
                            selected: t == prefs.target,
                            palette: p,
                            onTap: () => prefs.setTarget(t),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    _Row(
                      children: [
                        Segment(
                          label: prefs.sound ? l.soundOn : l.soundOff,
                          selected: prefs.sound,
                          palette: p,
                          onTap: prefs.toggleSound,
                        ),
                        Segment(
                          label: prefs.dark ? l.themeLight : l.themeDark,
                          selected: false,
                          palette: p,
                          onTap: prefs.toggleTheme,
                        ),
                        Segment(
                          label: prefs.lang.toggleLabel,
                          selected: false,
                          palette: p,
                          onTap: prefs.toggleLang,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    GoldButton(
                      label: l.deal,
                      palette: p,
                      wide: true,
                      fontSize: 19,
                      padding: const EdgeInsets.symmetric(vertical: 19),
                      onTap: () => _deal(prefs),
                    ),
                    const SizedBox(height: 14),
                    // The design has one flow, against the house opponent. Online
                    // play — and with it the four-handed and pass-and-play
                    // tables — keeps a way in rather than being taken out.
                    Center(
                      child: TextLink(
                        label: l.online,
                        palette: p,
                        color: p.ashDim,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => OnlineScreen(
                              profileId: prefs.variant,
                              numPlayers: profile.playerCounts.first,
                            ),
                          ),
                        ),
                      ),
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

  Future<void> _deal(AppPrefs prefs) async {
    if (_pushing) return;

    final profile = profileById(prefs.variant);
    final cfg = profile
        .build(numPlayers: profile.playerCounts.first)
        .withMatchTarget(prefs.target);
    // A visible seed would let players compare deals; an invisible one just has
    // to differ between games.
    final seed = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;

    _pushing = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GameScreen(
            controller: GameController(
              cfg: cfg,
              transport: LocalTransport.singlePlayer(
                cfg: cfg,
                seed: seed,
                botLevel: prefs.agentLevel,
              ),
            ),
          ),
        ),
      );
    } finally {
      _pushing = false;
    }
  }
}

/// A labelled row of choices.
class _Field extends StatelessWidget {
  final String label;
  final Palette palette;
  final List<Widget> children;

  const _Field({
    required this.label,
    required this.palette,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: mono(10, color: palette.ashDim)),
      const SizedBox(height: 8),
      _Row(children: children),
    ],
  );
}

/// Segments sit 8px apart, always.
class _Row extends StatelessWidget {
  final List<Widget> children;
  const _Row({required this.children});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        children[i],
      ],
    ],
  );
}
