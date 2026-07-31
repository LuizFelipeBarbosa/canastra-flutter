/// The turn state machine: a draw phase, then a meld/discard phase.
///
/// [applyAction] is the single mutation entry point for a round. It re-checks
/// legality through the same predicates `legal.dart` enumerates with, so an
/// action outside [legalActions] always throws [IllegalAction] and never
/// corrupts state.
library;

import 'action.dart';
import 'cards.dart';
import 'config.dart';
import 'legal.dart';
import 'meld.dart';
import 'scoring.dart';
import 'state.dart';

/// The submitted action is not legal in the current state.
class IllegalAction implements Exception {
  final String message;
  IllegalAction(this.message);
  @override
  String toString() => 'IllegalAction: $message';
}

void applyAction(RoundState state, GameAction action) {
  if (state.roundOver) throw IllegalAction('round is over; reset required');
  switch (state.phase) {
    case Phase.draw:
      _applyDraw(state, action);
    case Phase.play:
      _applyPlay(state, action);
    case Phase.terminal:
      throw IllegalAction('terminal state');
  }
}

/// Apply an encoded action id — the form that travels over the wire.
void applyActionId(RoundState state, int actionId) =>
    applyAction(state, decodeAction(actionId, state.cfg.meld.maxMeldSlots));

// --- draw phase ---------------------------------------------------------------

void _applyDraw(RoundState state, GameAction action) {
  final player = state.currentPlayer;
  final hand = state.hands[player];

  if (action is DrawDeck) {
    if (state.stock.isEmpty) throw IllegalAction('stock is empty');
    final n = state.cfg.turn.drawCount < state.stock.length
        ? state.cfg.turn.drawCount
        : state.stock.length;
    for (var i = 0; i < n; i++) {
      final ct = state.stock.removeLast();
      hand[ct] = (hand[ct] ?? 0) + 1;
    }
    if (resolveRedThrees(state, player)) {
      // A red 3 drawn as the last stock card ends the round.
      _finish(state, EndReason.stockExhausted, null);
      return;
    }
    _maybeConvertMorto(state);
    state.pileBlockedForNext = false;
    state.phase = Phase.play;
  } else if (action is DrawTrash) {
    if (!pileDrawAllowed(state)) {
      throw IllegalAction('cannot draw from the trash pile');
    }
    final rule = state.cfg.discardPile.drawRule;
    if (rule == drawWholePile) {
      if (state.cfg.discardPile.soleBuyRediscardBan &&
          state.trash.length == 1) {
        state.boughtSolePileCard = state.trash.single;
      }
      for (final ct in state.trash) {
        hand[ct] = (hand[ct] ?? 0) + 1;
      }
      state.trash.clear();
    } else if (rule == drawTopCard) {
      final ct = state.trash.removeLast();
      hand[ct] = (hand[ct] ?? 0) + 1;
      state.justDrawnFromPile = ct;
    } else if (rule == drawConditionalMeldTop) {
      if (!canTakeConditionalPile(state)) {
        throw IllegalAction('pile conditions not met');
      }
      final side = state.cfg.table.side(player);
      final top = state.trash.last;
      final pairOnly = effectiveFrozen(state, side);
      for (final ct in state.trash) {
        hand[ct] = (hand[ct] ?? 0) + 1;
      }
      state.trash.clear();
      state.frozen = false;
      // A red 3 buried in the pile (the initial upcard) goes to the tray
      // without replacement.
      for (final red in kRedThreeIds) {
        while ((hand[red] ?? 0) > 0) {
          if (hand[red] == 1) {
            hand.remove(red);
          } else {
            hand[red] = hand[red]! - 1;
          }
          state.redThrees[side].add(red);
        }
      }
      state.pendingPileCard = top;
      state.pendingPilePairOnly = pairOnly;
    } else {
      throw IllegalAction('unknown draw rule $rule');
    }
    state.pileBlockedForNext = false;
    state.phase = Phase.play;
  } else if (action is EndRound) {
    if (state.stock.isNotEmpty) {
      throw IllegalAction('END_ROUND only when the stock is empty');
    }
    _finish(state, EndReason.stockExhausted, null);
  } else {
    throw IllegalAction('expected a draw-phase action, got $action');
  }
}

/// `CONVERT_MORTO` exhaustion policy: an untaken morto becomes the new stock
/// the moment the stock empties. The side does not count as having taken it.
void _maybeConvertMorto(RoundState state) {
  if (state.stock.isNotEmpty ||
      state.cfg.turn.deckExhaustionPolicy != exhaustionConvertMorto) {
    return;
  }
  for (var side = 0; side < state.morto.length; side++) {
    final packet = state.morto[side];
    if (packet != null && !state.mortoTaken[side]) {
      state.stock = List.of(packet);
      state.morto[side] = null;
      return;
    }
  }
}

// --- meld/discard phase --------------------------------------------------------

void _applyPlay(RoundState state, GameAction action) {
  final cfg = state.cfg;
  final player = state.currentPlayer;
  final side = cfg.table.side(player);
  final hand = state.hands[player];
  final handSize = state.handSize(player);

  final rejection = playActionExtraRejection(state, action);
  if (rejection != null) throw IllegalAction(rejection);

  if (action is CreateSeq || action is CreateSet) {
    if (handSize == 0) {
      throw IllegalAction('hand is empty; only GO_OUT is legal');
    }
    final sideMelds = state.sideMelds(side);
    if (sideMelds.length >= cfg.meld.maxMeldSlots) {
      throw IllegalAction('meld slot cap reached');
    }
    if (!meldResultAllowed(state, side, handSize - 3)) {
      throw IllegalAction('meld would strand the hand');
    }
    if (action is CreateSet && cfg.meld.uniqueSetRankPerSide) {
      if (sideMelds.any(
        (m) => m.kind == MeldKind.set && m.rank == action.rank,
      )) {
        throw IllegalAction('side already owns a set of rank ${action.rank}');
      }
    }
    final Meld meld;
    try {
      if (action is CreateSeq) {
        meld = createSequence(
          cfg,
          hand,
          side,
          state.melds.length,
          action.suit,
          action.start,
          action.wild,
        );
      } else {
        // A pending pile-card obligation must consume the taken top card
        // itself, not a lower-suit copy of its rank.
        meld = createSet(
          cfg,
          hand,
          side,
          state.melds.length,
          (action as CreateSet).rank,
          action.wild,
          prefer: state.pendingPileCard,
        );
      }
    } on MeldError catch (e) {
      throw IllegalAction(e.message);
    }
    state.melds.add(meld);
    _afterMeldAction(state, side, action, meldPoints(cfg, meld));
    _resolveEmptyHand(state, side, viaDiscard: false);
  } else if (action is AddToMeld) {
    if (handSize == 0) {
      throw IllegalAction('hand is empty; only GO_OUT is legal');
    }
    final sideMelds = state.sideMelds(side);
    if (action.slot < 0 || action.slot >= sideMelds.length) {
      throw IllegalAction('no meld in slot ${action.slot}');
    }
    if (!addResultAllowed(state, side, sideMelds[action.slot], action.ct)) {
      throw IllegalAction('add would strand the hand');
    }
    try {
      applyAdd(cfg, hand, sideMelds[action.slot], action.ct);
    } on MeldError catch (e) {
      throw IllegalAction(e.message);
    }
    _afterMeldAction(state, side, action, cfg.cardValue(action.ct));
    _resolveEmptyHand(state, side, viaDiscard: false);
  } else if (action is Discard) {
    if (!discardAllowed(state, action.ct)) {
      throw IllegalAction('cannot discard card type ${action.ct}');
    }
    final n = hand[action.ct]!;
    if (n == 1) {
      hand.remove(action.ct);
    } else {
      hand[action.ct] = n - 1;
    }
    state.trash.add(action.ct);
    if (cfg.discardPile.freezeEnabled && cfg.isWildCard(action.ct)) {
      state.frozen = true;
    }
    if (cfg.specialThrees.blackThreeBlocksPile && isBlackThree(action.ct)) {
      state.pileBlockedForNext = true;
    }
    if (state.handSize(player) == 0) {
      _resolveEmptyHand(state, side, viaDiscard: true);
    } else {
      _endTurn(state);
    }
  } else if (action is GoOut) {
    if (handSize != 0) throw IllegalAction('GO_OUT requires an empty hand');
    if (cfg.goingOut.discardToGoOut == discardOutRequired) {
      throw IllegalAction('profile requires going out with a discard');
    }
    if (!baterReady(state, side)) {
      throw IllegalAction('going-out requirements not met');
    }
    _finish(state, EndReason.bater, side);
  } else {
    throw IllegalAction('expected a play-phase action, got $action');
  }
}

/// Post-meld bookkeeping: clear a satisfied pending-pile obligation and
/// accumulate initial-meld staging.
void _afterMeldAction(
  RoundState state,
  int side,
  GameAction action,
  int points,
) {
  if (state.pendingPileCard != null) {
    final pendingRank = idRank(state.pendingPileCard!);
    // A create of the pending rank consumed the card itself (createSet runs
    // with prefer=pending); an add satisfies only with that exact card.
    final satisfied =
        (action is CreateSet && action.rank == pendingRank) ||
        (action is AddToMeld && action.ct == state.pendingPileCard);
    if (satisfied) {
      state.pendingPileCard = null;
      state.pendingPilePairOnly = false;
    }
  }
  final cfg = state.cfg;
  if (cfg.initialMeld.enabled && !state.initialMeldDone[side]) {
    state.stagedPoints += points;
    if (state.stagedPoints >= state.initialMeldMin[side]) {
      state.initialMeldDone[side] = true;
      state.openedOnTurn[side] = state.turnNumber;
    }
  }
}

/// The hand-emptying resolver. Only runs in the play phase.
void _resolveEmptyHand(RoundState state, int side, {required bool viaDiscard}) {
  final player = state.currentPlayer;
  if (state.handSize(player) != 0) {
    if (viaDiscard) _endTurn(state);
    return;
  }

  if (mortoAvailable(state, side)) {
    final packet = state.morto[side]!;
    final hand = <CardId, int>{};
    for (final ct in packet) {
      hand[ct] = (hand[ct] ?? 0) + 1;
    }
    state.hands[player] = hand;
    state.morto[side] = null;
    state.mortoTaken[side] = true;
    // Batida indireta: the new hand waits for the next turn.
    // Batida direta: the same turn continues with the morto in hand.
    if (viaDiscard) _endTurn(state);
    return;
  }

  if (viaDiscard) {
    // `discardAllowed` already guaranteed bater readiness.
    _finish(state, EndReason.bater, side);
  }
  // Otherwise the hand stays empty and the only legal follow-up is GO_OUT.
}

void _endTurn(RoundState state) {
  state.currentPlayer = (state.currentPlayer + 1) % state.cfg.table.numPlayers;
  state.phase = Phase.draw;
  state.turnNumber += 1;
  state.justDrawnFromPile = null;
  state.boughtSolePileCard = null;
  // Staging is per-turn; a turn cannot end mid-staging.
  state.stagedPoints = 0;

  // Termination guarantee, not a rule of any variant — see [TurnConfig
  // .truncationCap]. This is a deliberate divergence from the reference Python
  // engine, which leaves truncation to its RL environment; a game has to end.
  if (state.turnNumber >= state.cfg.turn.truncationCap) {
    _finish(state, EndReason.stockExhausted, null);
  }
}

void _finish(RoundState state, EndReason reason, int? wentOutSide) {
  state.roundOver = true;
  state.phase = Phase.terminal;
  state.endReason = reason;
  state.wentOutSide = wentOutSide;
}
