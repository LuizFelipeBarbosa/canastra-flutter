/// The four things you can press.
///
/// A pill in the chrome, a segment in a row of choices, the one gold button that
/// starts a game, and a bare text link. Everything pressable in the app is one of
/// these, so a tap target never has to be recognised twice.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// CSS `filter: brightness(k)`, which is what the design's hover states use.
Color brighten(Color c, double k) => Color.from(
  alpha: c.a,
  red: (c.r * k).clamp(0.0, 1.0),
  green: (c.g * k).clamp(0.0, 1.0),
  blue: (c.b * k).clamp(0.0, 1.0),
);

/// Tracks hover so a child can restyle itself, and shows the hand cursor.
class Hoverable extends StatefulWidget {
  final Widget Function(bool hovered) builder;
  final VoidCallback? onTap;

  const Hoverable({super.key, required this.builder, this.onTap});

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: widget.builder(enabled && _hovered),
      ),
    );
  }
}

/// A bordered label in the chrome: the language, theme and sound toggles. On the
/// table these go fully round; on the landing screen they are softly rounded.
class Pill extends StatelessWidget {
  final String label;
  final Palette palette;
  final VoidCallback onTap;

  /// Overrides the resting label colour — the sound pill goes mint when on.
  final Color? color;
  final bool round;

  const Pill({
    super.key,
    required this.label,
    required this.palette,
    required this.onTap,
    this.color,
    this.round = false,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: Hoverable(
      onTap: onTap,
      builder: (hovered) => AnimatedContainer(
        duration: Motion.of(context, Motion.quick),
        padding: round
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 5)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(round ? 999 : 8),
          border: Border.all(color: hovered ? palette.mint : palette.line),
        ),
        child: Text(
          label,
          style: mono(
            round ? 10 : 11,
            color: hovered ? palette.mint : (color ?? palette.ash),
          ),
        ),
      ),
    ),
  );
}

/// One choice in a row of them — a difficulty, a match target, a toggle.
///
/// Every segment takes an equal share of the row, so the row's width does not
/// depend on how long the words in it happen to be.
class Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final Palette palette;
  final VoidCallback onTap;

  const Segment({
    super.key,
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      button: true,
      selected: selected,
      child: Hoverable(
        onTap: onTap,
        builder: (hovered) => AnimatedContainer(
          duration: Motion.of(context, Motion.quick),
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? palette.panelHot : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected || hovered ? palette.mint : palette.line,
            ),
          ),
          child: Text(
            label,
            style: mono(
              11,
              color: selected || hovered ? palette.mint : palette.ash,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The one gold button per screen: the thing that starts a game.
class GoldButton extends StatelessWidget {
  final String label;
  final Palette palette;
  final VoidCallback onTap;
  final double fontSize;
  final EdgeInsets padding;

  /// Fill the row rather than hug the label.
  final bool wide;

  const GoldButton({
    super.key,
    required this.label,
    required this.palette,
    required this.onTap,
    this.fontSize = 18,
    this.padding = const EdgeInsets.symmetric(horizontal: 34, vertical: 18),
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: Hoverable(
      onTap: onTap,
      builder: (hovered) => AnimatedContainer(
        duration: Motion.of(context, Motion.quick),
        width: wide ? double.infinity : null,
        padding: padding,
        alignment: wide ? Alignment.center : null,
        decoration: BoxDecoration(
          color: hovered ? brighten(palette.gold, 1.08) : palette.gold,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: T.display(fontSize, tracking: -0.4, color: palette.goldInk),
        ),
      ),
    ),
  );
}

/// A mint button that is not the gold one: the round sheet's continue.
class MintButton extends StatelessWidget {
  final String label;
  final Palette palette;
  final VoidCallback onTap;

  const MintButton({
    super.key,
    required this.label,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: Hoverable(
      onTap: onTap,
      builder: (hovered) => AnimatedContainer(
        duration: Motion.of(context, Motion.quick),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 17),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hovered ? brighten(palette.mint, 1.08) : palette.mint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label, style: T.title(15, color: palette.mintInk)),
      ),
    ),
  );
}

/// The way back out of a screen.
///
/// The arrow is an icon rather than a "←" in the label: DM Mono has no arrow
/// glyph, so typing one renders an empty box — the same reason the suit pips on a
/// card are painted instead of typed.
class BackLink extends StatelessWidget {
  final String label;
  final Palette palette;
  final VoidCallback onTap;

  const BackLink({
    super.key,
    required this.label,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Hoverable(
      onTap: onTap,
      builder: (hovered) {
        final tint = hovered ? palette.mint : palette.ash;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back, size: 12, color: tint),
            // An empty label leaves the arrow to speak for itself, which is what
            // a bar too narrow for both asks for. The word stays in [Semantics].
            if (label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(label, style: mono(11, color: tint)),
            ],
          ],
        );
      },
    ),
  );
}

/// A word you can press, with nothing drawn around it.
class TextLink extends StatelessWidget {
  final String label;
  final Palette palette;
  final VoidCallback onTap;
  final double fontSize;
  final Color? color;

  const TextLink({
    super.key,
    required this.label,
    required this.palette,
    required this.onTap,
    this.fontSize = 11,
    this.color,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: Hoverable(
      onTap: onTap,
      builder: (hovered) => Text(
        label,
        style: mono(
          fontSize,
          color: hovered ? palette.mint : (color ?? palette.ash),
        ),
      ),
    ),
  );
}
