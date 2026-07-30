/// The front door.
///
/// Two jobs, in this order: say the table is open and free, and let you choose
/// which rules are in force. The variant choice gets the whole right-hand column
/// because it is the only decision on this screen that changes the game — and
/// only the chosen one explains itself, so the column reads as a choice rather
/// than as four paragraphs.
library;

import 'package:flutter/material.dart';

import '../../engine/profiles.dart';
import '../app_scope.dart';
import '../copy.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/stage.dart';
import 'setup_screen.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.prefs;
    final p = prefs.palette;

    return Scaffold(
      body: Stage(
        palette: p,
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(64, 52, 64, 52),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(prefs: prefs),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _Pitch(prefs: prefs)),
                        const SizedBox(width: 64),
                        SizedBox(
                          width: 430,
                          child: _VariantColumn(prefs: prefs, lang: prefs.lang),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void openSetup(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const SetupScreen()));
}

class _Header extends StatelessWidget {
  final AppPrefs prefs;
  const _Header({required this.prefs});

  @override
  Widget build(BuildContext context) {
    final p = prefs.palette;
    return Row(
      children: [
        BrandMark(size: 52, palette: p),
        const SizedBox(width: 16),
        BrandWord(palette: p),
        const Spacer(),
        Pill(
          label: prefs.lang.toggleLabel,
          palette: p,
          onTap: prefs.toggleLang,
        ),
        const SizedBox(width: 8),
        Pill(
          label: prefs.dark ? 'LIGHT' : 'DARK',
          palette: p,
          onTap: prefs.toggleTheme,
        ),
      ],
    );
  }
}

class _Pitch extends StatelessWidget {
  final AppPrefs prefs;
  const _Pitch({required this.prefs});

  @override
  Widget build(BuildContext context) {
    final p = prefs.palette;
    final l = prefs.copy;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.kicker, style: mono(11, color: p.mint, tracking: 2.2)),
        const SizedBox(height: 22),
        Text(
          l.headline,
          style: T.display(66, tracking: -3, color: p.text, height: 0.94),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: 480,
          child: Text(l.sub, style: T.body(18, color: p.ash, height: 1.5)),
        ),
        const SizedBox(height: 28),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GoldButton(
              label: l.play,
              palette: p,
              onTap: () => LandingScreen.openSetup(context),
            ),
            const SizedBox(width: 14),
            Flexible(
              child: Text(l.free, style: mono(11, color: p.ashDim)),
            ),
          ],
        ),
        // The counters only exist once there is something to count; an empty
        // scoreboard on a first visit is worse than no scoreboard.
        if (prefs.played > 0) ...[
          const SizedBox(height: 36),
          _Stats(prefs: prefs),
        ],
      ],
    );
  }
}

class _Stats extends StatelessWidget {
  final AppPrefs prefs;
  const _Stats({required this.prefs});

  @override
  Widget build(BuildContext context) {
    final p = prefs.palette;
    final l = prefs.copy;
    final stats = [
      (l.played, '${prefs.played}', p.text),
      (l.won, '${prefs.won}', p.mint),
      (l.best, '${prefs.best}', p.gold),
    ];

    return Row(
      children: [
        for (final (label, value, color) in stats)
          Padding(
            padding: EdgeInsets.only(right: label == l.best ? 0 : 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: mono(26, color: color, tracking: 1)),
                Text(label, style: mono(10, color: p.ashDim)),
              ],
            ),
          ),
      ],
    );
  }
}

class _VariantColumn extends StatelessWidget {
  final AppPrefs prefs;
  final Lang lang;

  const _VariantColumn({required this.prefs, required this.lang});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (final profile in kProfiles)
        Padding(
          padding: EdgeInsets.only(bottom: profile == kProfiles.last ? 0 : 10),
          child: _VariantCard(
            profile: profile,
            copy: variantCopy(lang, profile.id),
            selected: profile.id == prefs.variant,
            palette: prefs.palette,
            onTap: () => prefs.setVariant(profile.id),
          ),
        ),
    ],
  );
}

class _VariantCard extends StatelessWidget {
  final GameProfile profile;
  final VariantCopy copy;
  final bool selected;
  final Palette palette;
  final VoidCallback onTap;

  const _VariantCard({
    required this.profile,
    required this.copy,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Semantics(
      button: true,
      selected: selected,
      child: Hoverable(
        onTap: onTap,
        builder: (hovered) => AnimatedContainer(
          duration: Motion.of(context, Motion.quick),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: selected ? p.panelHot : p.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected || hovered ? p.mint : p.line,
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
                    style: archivo(
                      19,
                      weight: 700,
                      tracking: -0.3,
                      color: selected ? p.text : p.ash,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // The tagline yields first when the card is too narrow for
                  // both; the game's name must never be the thing that clips.
                  Expanded(
                    child: Text(
                      copy.tagline,
                      overflow: TextOverflow.ellipsis,
                      style: mono(10, color: selected ? p.mint : p.ashDim),
                    ),
                  ),
                ],
              ),
              if (selected) ...[
                const SizedBox(height: 8),
                Text(copy.blurb, style: T.body(13, color: p.ash)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
