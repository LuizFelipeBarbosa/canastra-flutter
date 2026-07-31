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
import '../../game/move_index.dart';
import '../../multiplayer/table_view.dart';
import '../app_scope.dart';
import '../theme.dart';
import 'controls.dart';

class MeldBox extends StatefulWidget {
  final MeldView meld;
  final Palette palette;
  final double width;
  final double height;

  /// The selection would fit here.
  final bool open;

  /// Points the seal is worth, flown off the meld when it seals. Zero for a
  /// profile with no canastra bonus.
  final int bonus;

  /// Too narrow for the meld's name. The count takes its place: the rank is
  /// already legible on the top card, and the name is still what a screen
  /// reader is given.
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
  });

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
        builder: (hovered) => SizedBox(
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
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.open || hovered
                          ? p.mint
                          : meld.isCanastra
                          ? accent
                          : p.line,
                      width: widget.open ? 2 : 1,
                    ),
                    boxShadow: widget.open ? p.glowShadow() : null,
                  ),
                ),
              ),
              // The caption sits under the cards, which the layout draws on top.
              Positioned(
                left: widget.compact ? 6 : 9,
                right: widget.compact ? 6 : 9,
                bottom: widget.compact ? 4 : 6,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.compact ? '×${meld.size}' : meldLabel(meld),
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: mono(widget.compact ? 8 : 9, color: p.ash),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${meld.points}',
                      style: mono(
                        widget.compact ? 8 : 9,
                        color: meld.isCanastra ? accent : p.ashDim,
                      ),
                    ),
                  ],
                ),
              ),
              if (meld.isCanastra)
                Positioned(
                  right: -8,
                  top: -7,
                  child: _Seal(
                    progress: _stamp,
                    clean: meld.isClean,
                    palette: p,
                  ),
                ),
              if (widget.bonus != 0)
                Positioned(
                  right: -6,
                  top: -16,
                  child: _FlyingScore(
                    progress: _fly,
                    value: widget.bonus,
                    palette: p,
                  ),
                ),
            ],
          ),
        ),
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

  const _Seal({
    required this.progress,
    required this.clean,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final accent = clean ? palette.gold : palette.pink;
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
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: palette.sealBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: accent, width: 1.6),
        ),
        child: Text(clean ? 'LIMPA' : 'SUJA', style: mono(9, color: accent)),
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
