/// Design tokens.
///
/// Direction: a Brazilian-modernist card table rather than a casino one. The
/// ground is a saturated indigo carrying an Athos Bulcão-style azulejo motif,
/// the cards are warm bone, and the accents come from Hélio Oiticica's palette.
///
/// Colour carries rules, it does not decorate: [coringa] means a card is acting
/// as a wild, [limpa] means a canastra with no wild in it, [mint] means "you
/// may play here". Nothing else in the app is allowed to use those three.
library;

import 'package:flutter/material.dart';

abstract final class C {
  /// App chrome, the deepest ground.
  static const night = Color(0xFF0A1628);

  /// The table surface.
  static const table = Color(0xFF123A5C);
  static const tableHi = Color(0xFF17496F);

  /// Card face.
  static const bone = Color(0xFFF4EFE6);
  static const boneEdge = Color(0xFFDCD3C4);

  /// The back of a card nobody may see.
  static const cardBack = Color(0xFF0D2E4A);

  // --- the three meaningful accents ---

  /// A card acting as a wild.
  static const coringa = Color(0xFFFF2E88);

  /// A canastra with no wilds in it.
  static const limpa = Color(0xFFFFC93C);

  /// A legal destination for what you are holding.
  static const mint = Color(0xFF35E0B0);

  // --- neutrals on dark ---
  static const ash = Color(0xFF8FA6BC);
  static const ashDim = Color(0xFF5A7189);
  static const line = Color(0x22FFFFFF);

  // --- suit ink on a bone card ---
  static const suitBlack = Color(0xFF16202B);
  static const suitRed = Color(0xFFD92B2B);
}

/// Archivo is variable; weight comes from a font variation rather than a
/// separate file, so every weight below is exact rather than synthesised.
TextStyle _archivo(
  double size,
  double weight, {
  double? tracking,
  Color? color,
  double? height,
}) => TextStyle(
  fontFamily: 'Archivo',
  fontSize: size,
  height: height,
  letterSpacing: tracking,
  color: color,
  fontVariations: [FontVariation('wght', weight)],
);

abstract final class T {
  /// Screen titles and the game's own name.
  static TextStyle display(double size, {Color? color}) =>
      _archivo(size, 800, tracking: -0.5, color: color, height: 1.0);

  /// The rank printed on a card. Heavy and tight so it reads at 14px.
  static TextStyle rank(double size, {Color? color}) =>
      _archivo(size, 800, tracking: -0.8, color: color, height: 1.0);

  static TextStyle title(double size, {Color? color}) =>
      _archivo(size, 700, tracking: -0.2, color: color, height: 1.15);

  static TextStyle body(double size, {Color? color}) =>
      _archivo(size, 400, color: color, height: 1.45);

  /// The data register: scores, counts, eyebrows. Always uppercase and tracked.
  static TextStyle mono(double size, {Color? color, FontWeight? weight}) =>
      TextStyle(
        fontFamily: 'DMMono',
        fontSize: size,
        color: color,
        letterSpacing: 1.2,
        height: 1.2,
        fontWeight: weight ?? FontWeight.w500,
      );
}

/// A small uppercase label. Used for every eyebrow in the app so the register
/// stays consistent.
class Eyebrow extends StatelessWidget {
  final String text;
  final Color? color;
  const Eyebrow(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: T.mono(10, color: color ?? C.ashDim));
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: C.mint,
    onPrimary: C.night,
    secondary: C.coringa,
    surface: C.night,
    onSurface: C.bone,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.night,
    fontFamily: 'Archivo',
    splashFactory: InkSparkle.splashFactory,
    textSelectionTheme: const TextSelectionThemeData(cursorColor: C.mint),
  );
}

/// Motion durations. Every animation in the app is one of these three, which
/// keeps the table feeling like one object rather than a pile of effects.
abstract final class Motion {
  static const quick = Duration(milliseconds: 140);
  static const base = Duration(milliseconds: 260);
  static const stamp = Duration(milliseconds: 520);

  static const curve = Curves.easeOutCubic;

  /// Honour the platform's reduce-motion setting.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;
}
