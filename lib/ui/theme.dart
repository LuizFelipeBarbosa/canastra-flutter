/// Design tokens.
///
/// Direction: a Brazilian-modernist card table rather than a casino one. The
/// ground is a saturated indigo carrying an Athos Bulcão-style azulejo motif,
/// the cards are warm bone, and the accents come from Hélio Oiticica's palette.
///
/// Colour carries rules, it does not decorate: [Palette.pink] means a card is
/// acting as a wild, [Palette.gold] means a canastra with no wild in it, and
/// [Palette.mint] means "you may play here". Nothing else in the app is allowed
/// to use those three.
///
/// There are two grounds — `mesa noite` and `mesa de sol` — and every colour the
/// app paints comes from whichever [Palette] is in force, so the light table is
/// a real second theme rather than an inversion applied at the end.
library;

import 'package:flutter/material.dart';

/// Every colour in the app, for one of the two tables.
///
/// Deliberately a flat bag of named roles rather than a hierarchy: the names are
/// what the design speaks, and a reader tracing a colour should land on one
/// field rather than walk a tree.
@immutable
class Palette {
  /// Outside the table — the letterbox around the stage.
  final Color shell;

  /// The table surface, as a gradient from its lit centre outward.
  final List<Color> ground;

  /// The azulejo motif, at the very low contrast it is meant to sit at.
  final Color motifInk;

  final Color text;
  final Color ash;
  final Color ashDim;
  final Color line;

  /// A resting surface — a meld box, a zone, an unselected card.
  final Color panel;

  /// The same surface when it is a legal destination.
  final Color panelHot;

  /// The action strip along the bottom of the table.
  final Color strip;

  /// A sheet that covers the table, and the scrim behind it.
  final Color sheet;
  final Color scrim;

  /// Behind a canastra seal, so the stamp reads as printed on paper.
  final Color sealBg;

  // --- the card ---
  final Color cardBg;
  final Color cardEdge;
  final Color cardBack;
  final Color backLine;
  final Color backA;
  final Color backB;
  final List<BoxShadow> cardShadow;

  // --- the three meaningful accents ---

  /// A legal destination for what you are holding.
  final Color mint;
  final Color mintInk;

  /// A canastra with no wilds in it.
  final Color gold;
  final Color goldInk;

  /// A card acting as a wild.
  final Color pink;

  final Color goldLine;
  final Color goldWash;

  /// The glow a legal destination wears.
  final Color glow;

  // --- suit ink on a card face ---
  final Color suitBlack;
  final Color suitRed;

  final Color avatar;
  final Color avatarInk;

  /// The monogram: a filled quarter-tile with the buraco punched through it.
  final Color markFill;
  final Color markVoid;

  const Palette({
    required this.shell,
    required this.ground,
    required this.motifInk,
    required this.text,
    required this.ash,
    required this.ashDim,
    required this.line,
    required this.panel,
    required this.panelHot,
    required this.strip,
    required this.sheet,
    required this.scrim,
    required this.sealBg,
    required this.cardBg,
    required this.cardEdge,
    required this.cardBack,
    required this.backLine,
    required this.backA,
    required this.backB,
    required this.cardShadow,
    required this.mint,
    required this.mintInk,
    required this.gold,
    required this.goldInk,
    required this.pink,
    required this.goldLine,
    required this.goldWash,
    required this.glow,
    required this.suitBlack,
    required this.suitRed,
    required this.avatar,
    required this.avatarInk,
    required this.markFill,
    required this.markVoid,
  });

  /// `mesa noite`.
  static const dark = Palette(
    shell: Color(0xFF06101D),
    ground: [Color(0xFF17496F), Color(0xFF123A5C), Color(0xFF0A1628)],
    motifInk: Color(0x09FFFFFF),
    text: Color(0xFFF4EFE6),
    ash: Color(0xFF8FA6BC),
    ashDim: Color(0xFF5A7189),
    line: Color(0x22FFFFFF),
    panel: Color(0x33000000),
    panelHot: Color(0x1A000000),
    strip: Color(0x4D000000),
    sheet: Color(0xFF0A1628),
    scrim: Color(0x8A000000),
    sealBg: Color(0xFF0A1628),
    cardBg: Color(0xFFF4EFE6),
    cardEdge: Color(0xFFDCD3C4),
    cardBack: Color(0xFF0D2E4A),
    backLine: Color(0x4D35E0B0),
    backA: Color(0x1A35E0B0),
    backB: Color(0x1AFF2E88),
    cardShadow: [
      BoxShadow(color: Color(0x59000000), blurRadius: 6, offset: Offset(0, 3)),
    ],
    mint: Color(0xFF35E0B0),
    mintInk: Color(0xFF0A1628),
    gold: Color(0xFFFFC93C),
    goldInk: Color(0xFF0A1628),
    pink: Color(0xFFFF2E88),
    goldLine: Color(0x73FFC93C),
    goldWash: Color(0x1AFFC93C),
    glow: Color(0x6135E0B0),
    suitBlack: Color(0xFF16202B),
    suitRed: Color(0xFFD92B2B),
    avatar: Color(0x1FFFFFFF),
    avatarInk: Color(0xFFF4EFE6),
    markFill: Color(0xFFF4EFE6),
    markVoid: Color(0xFF123A5C),
  );

  /// `mesa de sol`.
  static const light = Palette(
    shell: Color(0xFFE8DFCB),
    ground: [Color(0xFFFBF6EA), Color(0xFFEFE6D3), Color(0xFFE0D4BC)],
    // The sun table inverts the motif rather than recolouring it, so the arcs
    // go from a white ghost to a black one at the same 3.5% contrast.
    motifInk: Color(0x09000000),
    text: Color(0xFF16202B),
    ash: Color(0xFF54677A),
    ashDim: Color(0xFF8496A6),
    line: Color(0x29123A5C),
    panel: Color(0x0D123A5C),
    panelHot: Color(0x120E9E79),
    strip: Color(0x0F123A5C),
    sheet: Color(0xFFFFFDF7),
    scrim: Color(0x66281E0A),
    sealBg: Color(0xFFFFFDF7),
    cardBg: Color(0xFFFFFFFF),
    cardEdge: Color(0xFFCFC3AC),
    cardBack: Color(0xFF123A5C),
    backLine: Color(0x59F4EFE6),
    backA: Color(0x3835E0B0),
    backB: Color(0x2EFF2E88),
    cardShadow: [
      BoxShadow(color: Color(0x293C2D14), blurRadius: 8, offset: Offset(0, 3)),
    ],
    mint: Color(0xFF0E9E79),
    mintInk: Color(0xFFFFFFFF),
    gold: Color(0xFFA97900),
    goldInk: Color(0xFFFFFDF7),
    pink: Color(0xFFD8146A),
    goldLine: Color(0x59A97900),
    goldWash: Color(0x14A97900),
    glow: Color(0x730E9E79),
    suitBlack: Color(0xFF16202B),
    suitRed: Color(0xFFC61F1F),
    avatar: Color(0x1F123A5C),
    avatarInk: Color(0xFF123A5C),
    markFill: Color(0xFF123A5C),
    markVoid: Color(0xFFF3EBDA),
  );

  /// A mint halo, for whatever is currently a legal destination.
  List<BoxShadow> glowShadow({double blur = 14, double spread = 0}) => [
    BoxShadow(color: glow, blurRadius: blur, spreadRadius: spread),
  ];
}

/// The table's own gradient. The mock draws it as an 860px circle centred a
/// little above the middle, which is where the light would fall on a real table.
RadialGradient groundGradient(Palette p) => RadialGradient(
  center: const Alignment(0, -0.48),
  radius: 860 / 790,
  colors: p.ground,
  stops: const [0.0, 0.55, 1.0],
);

/// Archivo is variable; weight comes from a font variation rather than a
/// separate file, so every weight below is exact rather than synthesised.
TextStyle archivo(
  double size, {
  double weight = 400,
  double tracking = 0,
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

/// The data register: scores, counts, eyebrows, seals. Always tracked, and in
/// practice always uppercase.
TextStyle mono(
  double size, {
  Color? color,
  double tracking = 1.2,
  double? height,
  FontWeight weight = FontWeight.w500,
}) => TextStyle(
  fontFamily: 'DMMono',
  fontSize: size,
  color: color,
  letterSpacing: tracking,
  height: height ?? 1.2,
  fontWeight: weight,
);

/// The three roles the design reuses with identical settings. Everything else is
/// spelled out with [archivo] or [mono] at the point of use, so the numbers in
/// the code read the same as the numbers in the design.
abstract final class T {
  /// A headline, a screen title, the game's own name, a rank on a card. Tight
  /// tracking is the point of this style, so it is always given explicitly.
  static TextStyle display(
    double size, {
    required double tracking,
    Color? color,
    double height = 1.0,
  }) => archivo(
    size,
    weight: 800,
    tracking: tracking,
    color: color,
    height: height,
  );

  /// A name: a meld's, a player's, a variant's.
  static TextStyle title(double size, {Color? color, double height = 1.15}) =>
      archivo(size, weight: 700, tracking: -0.2, color: color, height: height);

  /// Running prose — the coach line, a blurb, a score line.
  static TextStyle body(double size, {Color? color, double height = 1.45}) =>
      archivo(size, color: color, height: height);
}

ThemeData buildTheme(Palette p, {required bool dark}) {
  final scheme = (dark ? const ColorScheme.dark() : const ColorScheme.light())
      .copyWith(
        primary: p.mint,
        onPrimary: p.mintInk,
        secondary: p.pink,
        surface: p.sheet,
        onSurface: p.text,
      );
  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.shell,
    fontFamily: 'Archivo',
    splashFactory: InkSparkle.splashFactory,
    textSelectionTheme: TextSelectionThemeData(cursorColor: p.mint),
  );
}

/// Motion. Every animation in the app is one of these, which keeps the table
/// feeling like one object rather than a pile of effects.
abstract final class Motion {
  static const quick = Duration(milliseconds: 140);
  static const base = Duration(milliseconds: 260);

  /// A card travelling to where it now belongs.
  static const glide = Duration(milliseconds: 340);

  /// A canastra seal slamming down.
  static const stamp = Duration(milliseconds: 420);

  /// A score flying off a meld that just sealed.
  static const fly = Duration(milliseconds: 1100);

  static const curve = Curves.easeOutCubic;

  /// The card curve: leaves fast, arrives soft.
  static const glideCurve = Cubic(0.22, 0.9, 0.24, 1);

  /// The stamp overshoots, like a rubber stamp on a desk.
  static const stampCurve = Cubic(0.2, 1.5, 0.4, 1);

  /// Honour the platform's reduce-motion setting.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;
}
