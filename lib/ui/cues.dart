/// The six things the table says out loud.
///
/// The design specifies six synthesised cues — a soft tick when a card moves, a
/// snap when it lands, a low thud for taking the pile, a rising two-note chime
/// for a canastra, a drop for going out, and a buzz for a refusal. Flutter has
/// no tone generator and the app ships no audio assets, so each cue is played
/// here as the closest thing the platform offers for free: a click plus a
/// haptic weighted to match the cue's force.
///
/// The vocabulary is the real deliverable — one named cue per meaningful event,
/// nothing firing twice for one action. Swapping in real samples later is a
/// change to [_play] alone.
library;

import 'package:flutter/services.dart';

enum Cue {
  /// A card moves: dealt, picked up, put down again.
  deal,

  /// A card lands where it belongs.
  snap,

  /// The whole discard pile, or a morto, comes into a hand.
  take,

  /// A canastra just sealed.
  limpa,

  /// Somebody went out.
  out,

  /// That is not a legal move.
  no,
}

class SoundBoard {
  bool enabled;
  SoundBoard({this.enabled = true});

  void play(Cue cue) {
    if (!enabled) return;
    _play(cue);
  }

  static void _play(Cue cue) {
    switch (cue) {
      case Cue.deal:
        HapticFeedback.selectionClick();
      case Cue.snap:
        SystemSound.play(SystemSoundType.click);
        HapticFeedback.lightImpact();
      case Cue.take:
        HapticFeedback.mediumImpact();
      case Cue.limpa:
        SystemSound.play(SystemSoundType.click);
        HapticFeedback.heavyImpact();
      case Cue.out:
        HapticFeedback.heavyImpact();
      case Cue.no:
        SystemSound.play(SystemSoundType.alert);
        HapticFeedback.vibrate();
    }
  }
}
