/// The front door.
///
/// Two jobs, in this order: say the table is open and free, and let you choose
/// which rules are in force. The variant choice gets the whole right-hand column
/// because it is the only decision on this screen that changes the game — and
/// only the chosen one explains itself, so the column reads as a choice rather
/// than as four paragraphs.
library;

import 'package:flutter/material.dart';

import '../../account/account.dart';
import '../../engine/profiles.dart';
import '../account_scope.dart';
import '../app_scope.dart';
import '../copy.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/stage.dart';
import 'profile_screen.dart';
import 'sign_in_screen.dart';
import 'setup_screen.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.prefs;

    return Scaffold(
      body: Room(
        palette: prefs.palette,
        // The pitch and the variants only work side by side while both columns
        // are at their real width. Narrower than that they read better stacked
        // than squeezed, which is also the only shape a phone has room for.
        child: LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 1040
              ? _Wide(prefs: prefs)
              : _Narrow(prefs: prefs),
        ),
      ),
    );
  }

  static void openSetup(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const SetupScreen()));
}

class _Wide extends StatelessWidget {
  final AppPrefs prefs;
  const _Wide({required this.prefs});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(64, 52, 64, 52),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(prefs: prefs, narrow: false),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _Pitch(prefs: prefs, narrow: false)),
              const SizedBox(width: 64),
              SizedBox(
                width: 430,
                child: _VariantColumn(
                  prefs: prefs,
                  lang: prefs.lang,
                  narrow: false,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Narrow extends StatelessWidget {
  final AppPrefs prefs;
  const _Narrow({required this.prefs});

  @override
  Widget build(BuildContext context) => Column(
    // The room scrolls, so nothing here may ask for the height it is given.
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Header(prefs: prefs, narrow: true),
      const SizedBox(height: 36),
      _Pitch(prefs: prefs, narrow: true),
      const SizedBox(height: 36),
      _VariantColumn(prefs: prefs, lang: prefs.lang, narrow: true),
    ],
  );
}

class _Header extends StatelessWidget {
  final AppPrefs prefs;
  final bool narrow;
  const _Header({required this.prefs, required this.narrow});

  @override
  Widget build(BuildContext context) {
    final account = context.account;
    final p = prefs.palette;
    final l = prefs.copy;
    final accountLabel = switch (account.state) {
      Restoring() || SignedOut() => l.auth.signIn,
      Guest() => l.auth.guest,
      Player() => _playerLabel(account.displayName, l.auth.account),
    };
    final pills = [
      Pill(
        label: accountLabel,
        palette: p,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => switch (account.state) {
              Restoring() || SignedOut() => const SignInScreen(),
              Guest() || Player() => const ProfileScreen(),
            },
          ),
        ),
      ),
      Pill(label: prefs.lang.toggleLabel, palette: p, onTap: prefs.toggleLang),
      Pill(
        label: prefs.dark ? l.themeLight : l.themeDark,
        palette: p,
        onTap: prefs.toggleTheme,
      ),
    ];

    if (narrow) {
      // The wordmark and three pills do not share a phone-width line, so the
      // pills drop below it rather than shrinking to fit.
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BrandMark(size: 44, palette: p),
              const SizedBox(width: 14),
              BrandWord(palette: p),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: pills),
        ],
      );
    }

    return Row(
      children: [
        BrandMark(size: 52, palette: p),
        const SizedBox(width: 16),
        BrandWord(palette: p),
        const Spacer(),
        for (var i = 0; i < pills.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          pills[i],
        ],
      ],
    );
  }
}

String _playerLabel(String? displayName, String fallback) {
  final name = displayName?.trim();
  if (name == null || name.isEmpty) return fallback;

  final upper = name.toUpperCase();
  return upper.length <= 12 ? upper : upper.substring(0, 12);
}

class _Pitch extends StatelessWidget {
  final AppPrefs prefs;
  final bool narrow;
  const _Pitch({required this.prefs, required this.narrow});

  @override
  Widget build(BuildContext context) {
    final p = prefs.palette;
    final l = prefs.copy;

    return Column(
      mainAxisSize: narrow ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.kicker, style: mono(11, color: p.mint, tracking: 2.2)),
        const SizedBox(height: 22),
        Text(
          l.headline,
          style: narrow
              ? T.display(34, tracking: -1.4, color: p.text, height: 0.98)
              : T.display(66, tracking: -3, color: p.text, height: 0.94),
        ),
        const SizedBox(height: 22),
        // The measure is what makes the sub readable; on a phone the column is
        // already narrower than the measure would be.
        _Measure(
          width: narrow ? null : 480,
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

/// A fixed measure, or the full column when there is no room for one.
class _Measure extends StatelessWidget {
  final double? width;
  final Widget child;

  const _Measure({required this.width, required this.child});

  @override
  Widget build(BuildContext context) =>
      width == null ? child : SizedBox(width: width, child: child);
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
  final bool narrow;

  const _VariantColumn({
    required this.prefs,
    required this.lang,
    required this.narrow,
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: narrow ? MainAxisSize.min : MainAxisSize.max,
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
