/// A meld on the table, and the seal it earns at seven cards.
///
/// The box is only a frame and a caption: the cards inside it are placed by the
/// layout, so they can glide in from a hand rather than appear here.
///
/// The seal is the signature moment of the game. Making a canastra is what a whole
/// round is spent working toward, so it gets stamped on, at an angle, the instant
/// it happens — gold for limpa, pink for suja. The colour is the same one used for
/// wilds everywhere else, so the reason a suja is worth half shows up in the badge
/// itself, and the bonus flies off the meld as it lands.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/cards.dart';
import '../../multiplayer/table_view.dart';
import '../app_scope.dart';
import '../copy.dart';
import '../theme.dart';
import 'controls.dart';

class MeldBox extends StatefulWidget {
  final MeldView meld;
  final Palette palette;
  final double width;
  final double height;

  /// Reference width for one card inside the meld.
  ///
  /// Seventy-five keeps the old 12px corner at the default scale; boxes that
  /// are narrower than that cap the value to avoid oversized caption chrome.
  final double meldCardWidth;

  /// Caption sizing remains caller-controlled until the fluid table supplies
  /// the final rendered meld-card width.
  final double captionFontSize;

  /// The selection would fit here.
  final bool open;

  /// Points the seal is worth, flown off the meld when it seals. Zero for a
  /// profile with no canastra bonus.
  final int bonus;

  /// Too narrow for the meld's name. The count takes its place: the rank is
  /// already legible on the top card, and the name is still what a screen
  /// reader is given — and the seal is cut down to match, since a box this
  /// narrow cannot carry a full-size stamp without borrowing its neighbour's
  /// room.
  final bool compact;

  final VoidCallback? onTap;

  const MeldBox({
    super.key,
    required this.meld,
    required this.palette,
    required this.width,
    required this.height,
    required this.bonus,
    this.compact = false,
    this.open = false,
    this.onTap,
    this.meldCardWidth = 75,
    this.captionFontSize = 9,
  }) : assert(meldCardWidth > 0),
       assert(captionFontSize > 0);

  @override
  State<MeldBox> createState() => _MeldBoxState();
}

class _MeldBoxState extends State<MeldBox> with TickerProviderStateMixin {
  // Built eagerly rather than lazily: a `late final` controller whose first read
  // is dispose() would create a ticker against an already-deactivated element,
  // which is exactly what happens to a meld that never becomes a canastra.
  late final AnimationController _stamp;
  late final AnimationController _fly;

  @override
  void initState() {
    super.initState();
    _stamp = AnimationController(
      vsync: this,
      duration: Motion.stamp,
      value: widget.meld.isCanastra ? 1 : 0,
    );
    _fly = AnimationController(vsync: this, duration: Motion.fly);
  }

  @override
  void didUpdateWidget(MeldBox old) {
    super.didUpdateWidget(old);
    if (widget.meld.isCanastra && !old.meld.isCanastra) {
      if (Motion.reduced(context)) {
        _stamp.value = 1;
      } else {
        _stamp.forward(from: 0);
        if (widget.bonus != 0) _fly.forward(from: 0);
      }
    } else if (!widget.meld.isCanastra && old.meld.isCanastra) {
      _stamp.value = 0;
    }
  }

  @override
  void dispose() {
    _stamp.dispose();
    _fly.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meld = widget.meld;
    final p = widget.palette;
    final l = context.copy;
    final accent = meld.isClean ? p.gold : p.pink;
    final mcw = math.min(widget.meldCardWidth, widget.width);
    final cornerRadius = mcw * 0.16;
    final captionPad = mcw * 0.11;
    final captionBottom = math.max(5.0, mcw * 0.11);
    final captionGap = math.max(4.0, mcw * 0.09);
    final capFs = widget.compact
        ? widget.captionFontSize * 8 / 9
        : widget.captionFontSize;
    final strongBorderWidth = math.max(1.75, p.cardBorderW * 1.3);
    final spokenName = meld.isSequence
        ? l.runName(
            rankAt(meld.startPos!),
            rankAt(meld.startPos! + meld.size - 1),
            meld.suit!,
          )
        : l.setName(meld.rank!);

    return Semantics(
      label:
          '$spokenName, ${l.countCards(meld.size)}'
          '${meld.isCanastra ? ', ${l.canastra}' : ''}',
      button: widget.onTap != null,
      child: Hoverable(
        onTap: widget.onTap,
        builder: (hovered) {
          final active = widget.open || hovered;
          final borderColor = meld.isCanastra
              ? accent
              : active
              ? p.mint
              : p.line;
          final borderWidth = meld.isCanastra || active
              ? strongBorderWidth
              : p.cardBorderW;

          return SizedBox(
            width: widget.width,
            height: widget.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: Motion.of(context, Motion.quick),
                    decoration: BoxDecoration(
                      color: widget.open ? p.panelHot : p.panel,
                      borderRadius: BorderRadius.circular(cornerRadius),
                      border: Border.all(
                        color: borderColor,
                        width: borderWidth,
                      ),
                      boxShadow: widget.open ? p.glowShadow() : null,
                    ),
                  ),
                ),
                // Keeping the complete caption inside the frame prevents a
                // newly earned seal from borrowing space from its neighbour.
                Positioned(
                  left: captionPad,
                  right: captionPad,
                  bottom: captionBottom,
                  // Every variable-width child below is Flexible (loose) so
                  // the row can only ever be squeezed, never overflow: a
                  // heuristically undersized box must degrade the caption to
                  // ellipsis, not throw a RenderFlex overflow.
                  child: Row(
                    children: [
                      Flexible(
                        fit: FlexFit.loose,
                        child: Text(
                          widget.compact
                              ? '×${meld.size}'
                              : shortMeldLabel(context.prefs.lang, meld),
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: mono(
                            capFs,
                            tracking: capFs * 0.05,
                            color: p.ash,
                          ).copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                      SizedBox(width: captionGap),
                      if (meld.isCanastra) ...[
                        Flexible(
                          fit: FlexFit.loose,
                          child: _Seal(
                            progress: _stamp,
                            clean: meld.isClean,
                            palette: p,
                            captionFontSize: capFs,
                            meldCardWidth: mcw,
                          ),
                        ),
                        SizedBox(width: captionGap),
                      ],
                      Flexible(
                        fit: FlexFit.loose,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${meld.points}',
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            textAlign: TextAlign.right,
                            style: mono(
                              capFs,
                              color: meld.isCanastra ? accent : p.ashDim,
                            ).copyWith(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.bonus != 0)
                  Positioned(
                    right: captionPad,
                    bottom: captionBottom + capFs,
                    child: _FlyingScore(
                      progress: _fly,
                      value: widget.bonus,
                      palette: p,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// LIMPA or SUJA, slammed down like a rubber stamp: in from far too big,
/// undershooting once before it settles.
class _Seal extends StatelessWidget {
  final Animation<double> progress;
  final bool clean;
  final Palette palette;
  final double captionFontSize;
  final double meldCardWidth;

  const _Seal({
    required this.progress,
    required this.clean,
    required this.palette,
    required this.captionFontSize,
    required this.meldCardWidth,
  });

  @override
  Widget build(BuildContext context) {
    final accent = clean ? palette.gold : palette.pink;
    final ink = clean ? palette.goldInk : Colors.white;
    final sealFontSize = captionFontSize * 0.86;
    final horizontalPadding = math.max(4.0, meldCardWidth * 0.09);
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) {
        final t = progress.value.clamp(0.0, 1.0);
        // 2.6 → 0.92 over the first 55%, then 0.92 → 1.
        final scale = t < 0.55
            ? 2.6 + (0.92 - 2.6) * Motion.stampCurve.transform(t / 0.55)
            : 0.92 + 0.08 * ((t - 0.55) / 0.45);
        return Opacity(
          opacity: t < 0.1 ? t / 0.1 : 1,
          child: Transform.rotate(
            angle: -12 * math.pi / 180,
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 1,
        ),
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          clean ? 'LIMPA' : 'SUJA',
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: mono(
            sealFontSize,
            tracking: sealFontSize * 0.09,
            color: ink,
          ).copyWith(fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

/// The bonus, drifting up off the meld that just earned it and fading out.
class _FlyingScore extends StatelessWidget {
  final Animation<double> progress;
  final int value;
  final Palette palette;

  const _FlyingScore({
    required this.progress,
    required this.value,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: progress,
    builder: (context, child) {
      final t = progress.value;
      if (t == 0 || t == 1) return const SizedBox.shrink();
      final eased = Curves.easeOut.transform(t);
      return Transform.translate(
        offset: Offset(0, 6 - 44 * eased),
        // Fades in over the first quarter, then out across the rest.
        child: Opacity(
          opacity: t < 0.25 ? t / 0.25 : 1 - (t - 0.25) / 0.75,
          child: child,
        ),
      );
    },
    child: Text('+$value', style: mono(15, color: palette.gold)),
  );
}
