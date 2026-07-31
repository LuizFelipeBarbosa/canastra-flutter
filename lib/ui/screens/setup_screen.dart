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
import '../account_scope.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/sheet.dart';
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
      body: Room(
        palette: p,
        child: SheetCard(
          palette: p,
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

            ChoiceField(
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

            ChoiceField(
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

            if (profile.playerCounts.length > 1) ...[
              ChoiceField(
                label: l.onlinePlayers,
                palette: p,
                children: [
                  for (final n in profile.playerCounts)
                    Segment(
                      label: n == 2 ? l.onlineTwoPlayers : l.onlineFourPlayers,
                      selected: n == prefs.playersFor(profile),
                      palette: p,
                      onTap: () => prefs.setPlayers(n),
                    ),
                ],
              ),
              const SizedBox(height: 20),
            ],

            ChoiceField(
              label: l.handOrder,
              palette: p,
              children: [
                Segment(
                  label: l.orderBySuit,
                  selected: prefs.handOrder == HandOrder.suit,
                  palette: p,
                  onTap: () => prefs.setHandOrder(HandOrder.suit),
                ),
                Segment(
                  label: l.orderByRank,
                  selected: prefs.handOrder == HandOrder.rank,
                  palette: p,
                  onTap: () => prefs.setHandOrder(HandOrder.rank),
                ),
              ],
            ),
            const SizedBox(height: 20),

            ChoiceRow(
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
                      numPlayers: prefs.playersFor(profile),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deal(AppPrefs prefs) async {
    if (_pushing) return;

    final accountName = context.account.signedIn
        ? context.account.displayName?.trim()
        : null;
    final playerName = accountName == null || accountName.isEmpty
        ? 'You'
        : accountName;
    final profile = profileById(prefs.variant);
    final cfg = profile
        .build(numPlayers: prefs.playersFor(profile))
        .withMatchTarget(prefs.target);
    // A visible seed would let players compare deals; an invisible one just has
    // to differ between games.
    final seed = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
    final controller = GameController(
      cfg: cfg,
      transport: LocalTransport.singlePlayer(
        cfg: cfg,
        seed: seed,
        botLevel: prefs.agentLevel,
        playerName: playerName,
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
}
