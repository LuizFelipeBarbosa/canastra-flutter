/// Legal-action enumeration and the shared legality predicates.
///
/// [legalActions] returns structured actions in stable id order. The predicates
/// here are also used by `turns.dart`'s `applyAction`, so enumeration and
/// application can never disagree.
///
/// The anti-stranding guard: no legal action may leave the player unable to
/// finish their turn legally. Melding down to 1 card is legal only if the
/// forced final discard will itself be legal (morto pickup or bater); melding
/// to 0 is legal only if it triggers a morto pickup or a permitted meld-out.
library;

import 'action.dart';
import 'cards.dart';
import 'config.dart';
import 'meld.dart';
import 'state.dart';

bool mortoAvailable(RoundState state, int side) =>
    side < state.morto.length &&
    !state.mortoTaken[side] &&
    state.morto[side] != null;

/// Whether the side meets the going-out requirements (canastra / morto).
///
/// [melds] overrides the side's meld list — used to evaluate readiness on a
/// hypothetical post-add state.
bool baterReady(RoundState state, int side, {List<Meld>? melds}) {
  final g = state.cfg.goingOut;
  if (g.requireMortoTaken &&
      state.mortoTaken.length > side &&
      !state.mortoTaken[side]) {
    return false;
  }
  if (g.requireCanastra) {
    final minSize = state.cfg.meld.canastraMinSize;
    final source = melds ?? state.sideMelds(side);
    final qualifying = source
        .where((m) =>
            m.isCanastra(minSize) && (m.isClean || !g.requireCleanCanastra))
        .length;
    if (qualifying < g.goOutMinCanastras) return false;
  }
  return true;
}

/// Anti-stranding guard for a CREATE leaving [resultingHand] cards.
///
/// Pre-state evaluation is correct for CREATE: a fresh minimum-size meld can
/// never itself be a canastra. ADDs use [addResultAllowed] instead.
bool meldResultAllowed(RoundState state, int side, int resultingHand) {
  if (resultingHand >= 2) return true;
  if (mortoAvailable(state, side)) return true;
  if (!baterReady(state, side)) return false;
  final policy = state.cfg.goingOut.discardToGoOut;
  // A meld-out ends via GO_OUT; otherwise the forced last discard goes out.
  if (resultingHand == 0) return policy != discardOutRequired;
  return policy != discardOutForbidden;
}

/// Anti-stranding guard for a specific ADD, evaluated on the POST-add state:
/// the added card may itself complete the qualifying canastra, and a
/// `TO_HAND` swap returns the freed wild so the net hand change is zero.
bool addResultAllowed(RoundState state, int side, Meld meld, CardId ct) {
  final cfg = state.cfg;
  final player = state.currentPlayer;
  final hand = state.hands[player];
  final plan = planAdd(cfg, hand, meld, ct);
  // Not this guard's concern; application rejects it properly.
  if (plan == null) return true;

  final resulting = state.handSize(player) - 1 + (plan.wildToHand ? 1 : 0);
  if (resulting >= 2) return true;
  if (mortoAvailable(state, side)) return true;

  // Simulate the add on copies to judge bater readiness afterwards.
  final meldCopy = meld.copy();
  final handCopy = Map.of(hand);
  applyAdd(cfg, handCopy, meldCopy, ct);
  final meldsAfter = [
    for (final m in state.sideMelds(side)) identical(m, meld) ? meldCopy : m,
  ];
  if (!baterReady(state, side, melds: meldsAfter)) return false;

  final policy = cfg.goingOut.discardToGoOut;
  if (resulting == 0) return policy != discardOutRequired;
  return policy != discardOutForbidden;
}

bool discardAllowed(RoundState state, CardId ct) {
  final player = state.currentPlayer;
  final side = state.cfg.table.side(player);
  if ((state.hands[player][ct] ?? 0) <= 0 || ct >= kPad) return false;
  if (state.cfg.discardPile.noImmediateRedrawDiscard &&
      ct == state.justDrawnFromPile) {
    return false;
  }
  if (state.handSize(player) == 1) {
    // Emptying discard.
    if (mortoAvailable(state, side)) return true; // batida indireta
    return baterReady(state, side) &&
        state.cfg.goingOut.discardToGoOut != discardOutForbidden;
  }
  return true;
}

bool pileDrawAllowed(RoundState state) {
  if (state.trash.isEmpty || state.pileBlockedForNext) return false;
  final rule = state.cfg.discardPile.drawRule;
  if (rule == drawWholePile || rule == drawTopCard) return true;
  if (rule == drawConditionalMeldTop) return canTakeConditionalPile(state);
  return false;
}

// --- Canasta mechanics -----------------------------------------------------

bool isBlackThree(CardId ct) =>
    idRank(ct) == Rank.three && !isRedThree(ct) && idSuit(ct) != null;

/// The pile is frozen for a side that has not opened, and for everyone while it
/// holds a wild or red-3 upcard.
bool effectiveFrozen(RoundState state, int side) {
  if (state.frozen) return true;
  return state.cfg.initialMeld.enabled && !state.initialMeldDone[side];
}

/// Constructive lower bound of meld points layable from [hand] (sets only)
/// while leaving at least [reserve] cards unmelded.
///
/// The bound is a strict-prefix construction over atoms in dependency order
/// (staged-rank adds, fresh-set cores then extensions, pair-openings, wild
/// placements), so every counted point corresponds to a playable action whose
/// intermediate states all keep at least [reserve] cards. The staging guard's
/// "the mask is never empty" induction rests on this: with `reserve = 2` every
/// permitted line ends with 2+ cards, so the closing discard is always legal.
/// The bound may under-count (safe); it never counts an unrealisable line.
///
/// [stagedSetRanks] and [stagedWildCapacity] describe sets the side has already
/// laid this turn: any natural of a staged rank is addable, and their remaining
/// wild slots extend the wild-placement capacity.
int maxStageablePoints(
  RulesConfig cfg,
  Map<CardId, int> hand, {
  Set<int> stagedSetRanks = const {},
  int stagedWildCapacity = 0,
  int reserve = 0,
}) {
  if (!cfg.meld.allowSets) return 0;
  final budget = hand.values.fold(0, (a, b) => a + b) - reserve;
  if (budget <= 0) return 0;

  final limit = cfg.wildcard.wildcardLimitPerMeld;
  final wildValues = <int>[
    for (final e in hand.entries)
      if (cfg.isWildCard(e.key))
        for (var i = 0; i < e.value; i++) cfg.cardValue(e.key),
  ]..sort((a, b) => b.compareTo(a));

  // (cards, points) atoms in construction order.
  final atoms = <(int, int)>[];
  var capacity = stagedWildCapacity;
  final pairs = <int>[]; // value of each openable 2-natural rank

  for (final rank in Rank.values) {
    if (cfg.wildcard.wildRanks.contains(rank)) continue;
    if (cfg.specialThrees.blackThreeMeldOnlyGoingOut && rank == Rank.three) {
      continue;
    }
    var n = 0;
    for (final s in Suit.values) {
      n += hand[cardId(rank, s)] ?? 0;
    }
    final value = cfg.cardValue(cardId(rank, Suit.clubs));
    if (stagedSetRanks.contains(rank)) {
      for (var i = 0; i < n; i++) {
        atoms.add((1, value)); // every copy is addable
      }
    } else if (n >= 3) {
      atoms.add((3, 3 * value)); // fresh natural core
      for (var i = 0; i < n - 3; i++) {
        atoms.add((1, value));
      }
      capacity += limit;
    } else if (n == 2 && cfg.wildcard.minNaturalsPerMeld <= 2) {
      pairs.add(value);
    }
  }

  pairs.sort((a, b) => b.compareTo(a));
  var wildsUsed = 0;
  if (limit >= 1) {
    for (final value in pairs) {
      if (wildsUsed >= wildValues.length) break;
      atoms.add((3, 2 * value + wildValues[wildsUsed]));
      wildsUsed++;
      capacity += limit - 1;
    }
  }
  for (final wildValue in wildValues.skip(wildsUsed)) {
    if (capacity <= 0) break;
    atoms.add((1, wildValue));
    capacity--;
  }

  var total = 0;
  var used = 0;
  for (final (cards, points) in atoms) {
    if (used + cards > budget) break; // strict prefix keeps dependency order valid
    used += cards;
    total += points;
  }
  return total;
}

Map<CardId, int> _removeNaturals(Map<CardId, int> hand, int rank, int count) {
  final remaining = Map.of(hand);
  for (final suit in Suit.values) {
    final ct = cardId(rank, suit);
    final have = remaining[ct] ?? 0;
    final take = have < count ? have : count;
    if (take != 0) {
      remaining[ct] = have - take;
      count -= take;
    }
    if (count == 0) break;
  }
  return remaining;
}

/// `CONDITIONAL_MELD_TOP` take-pile legality, including the anti-stranding and
/// initial-meld feasibility guards.
bool canTakeConditionalPile(RoundState state) {
  final cfg = state.cfg;
  if (state.trash.isEmpty || state.pileBlockedForNext) return false;
  final player = state.currentPlayer;
  final side = cfg.table.side(player);
  final top = state.trash.last;
  if (cfg.isWildCard(top) || isBlackThree(top) || isRedThree(top)) return false;

  final hand = state.hands[player];
  final rank = idRank(top)!;
  var naturals = 0;
  for (final s in Suit.values) {
    naturals += hand[cardId(rank, s)] ?? 0;
  }
  final frozenFor = effectiveFrozen(state, side);
  final openSet = state
      .sideMelds(side)
      .any((m) => m.kind == MeldKind.set && m.rank == rank);
  final hasWild =
      hand.entries.any((e) => cfg.isWildCard(e.key) && e.value > 0);

  final List<int> consumptions;
  if (frozenFor) {
    if (naturals < 2) return false;
    // Forced use: join the existing rank set (1 card), or lay a fresh natural
    // set (top card + two hand naturals).
    consumptions = openSet ? [1] : [3];
  } else {
    if (!(naturals >= 2 || (naturals >= 1 && hasWild) || openSet)) return false;
    consumptions = [
      if (openSet) 1, // add the top card to the open set
      if (naturals >= 2 || (naturals >= 1 && hasWild)) 3,
    ];
  }

  // Unopened side: taking the pile must leave the threshold reachable — every
  // in-hand card counts. Evaluated after the forced meld.
  if (cfg.initialMeld.enabled && !state.initialMeldDone[side]) {
    final combined = Map.of(hand);
    for (final ct in state.trash) {
      combined[ct] = (combined[ct] ?? 0) + 1;
    }
    final forcedPoints = 3 * cfg.cardValue(top);
    final remaining = _removeNaturals(combined, rank, 3);
    final bound = maxStageablePoints(
      cfg,
      remaining,
      stagedSetRanks: {rank},
      stagedWildCapacity: cfg.wildcard.wildcardLimitPerMeld,
      reserve: 2,
    );
    if (forcedPoints + bound < state.initialMeldMin[side]) return false;
  }

  // Anti-stranding: at least one forced-meld option must leave a finishable
  // turn (2+ cards for a normal discard, or a permitted going-out line).
  // Buried red 3s go to the tray on take, not to the hand.
  final buriedRedThrees = state.trash.where(isRedThree).length;
  final totalAfterTake =
      state.handSize(player) + state.trash.length - buriedRedThrees;
  final policy = cfg.goingOut.discardToGoOut;
  for (final consumed in consumptions) {
    final left = totalAfterTake - consumed;
    if (left >= 2) return true;
    if (left == 1 && baterReady(state, side) && policy != discardOutForbidden) {
      return true;
    }
    if (left == 0 && baterReady(state, side) && policy != discardOutRequired) {
      return true;
    }
  }
  return false;
}

/// Card-point value a meld action would stage; null if it cannot apply.
int? _actionPoints(RoundState state, GameAction action) {
  final cfg = state.cfg;
  final hand = state.hands[state.currentPlayer];
  final CreatePlan? plan;
  switch (action) {
    case CreateSeq(:final suit, :final start, :final wild):
      plan = planSequence(cfg, hand, suit, start, wild);
    case CreateSet(:final rank, :final wild):
      plan = planSet(cfg, hand, rank, wild);
    case AddToMeld(:final ct):
      return cfg.cardValue(ct);
    default:
      return null;
  }
  if (plan == null) return null;
  return plan.consumed.fold<int>(0, (sum, ct) => sum + cfg.cardValue(ct));
}

/// Canasta-mode restrictions layered over base legality: the forced
/// pending-pile meld, black-three limits and initial-meld staging. Returns a
/// rejection reason, or null when the action passes. A no-op for Buraco-family
/// configs.
String? playActionExtraRejection(RoundState state, GameAction action) {
  final cfg = state.cfg;
  final player = state.currentPlayer;
  final side = cfg.table.side(player);

  if (state.pendingPileCard != null) {
    final pending = state.pendingPileCard!;
    final rank = idRank(pending);
    bool ok;
    if (action is AddToMeld) {
      // Only the taken top card itself discharges the obligation — a same-rank
      // card from hand would leave the top card stranded.
      ok = action.ct == pending;
    } else if (action is CreateSet && action.rank == rank) {
      // Frozen take: a fresh natural set (the natural pair was verified at take
      // time). Either way the created set must consume the pending card itself
      // — canonical lowest-suit-first selection could otherwise meld a
      // different copy of its rank.
      if (state.pendingPilePairOnly && action.wild != setWildNone) {
        ok = false;
      } else {
        ok = planSet(cfg, state.hands[player], action.rank, action.wild,
                prefer: pending) !=
            null;
      }
    } else {
      ok = false;
    }
    if (!ok) return "must meld the taken pile's top card itself";
    return null; // the forced meld is exempt from the staging guard
  }

  if (cfg.specialThrees.blackThreeMeldOnlyGoingOut) {
    if (action is CreateSet && action.rank == Rank.three) {
      if (action.wild != setWildNone) return 'black-three sets take no wilds';
      final resulting = state.handSize(player) - 3;
      if (resulting > 1 || !meldResultAllowed(state, side, resulting)) {
        return 'black threes meld only when going out';
      }
    }
    if (action is AddToMeld) {
      final sideMelds = state.sideMelds(side);
      if (action.slot >= 0 && action.slot < sideMelds.length) {
        final target = sideMelds[action.slot];
        if (target.kind == MeldKind.set && target.rank == Rank.three) {
          if (cfg.isWildCard(action.ct)) return 'black-three sets take no wilds';
          if (state.handSize(player) - 1 > 1) {
            return 'black threes meld only when going out';
          }
        }
      }
    }
  }

  if (cfg.initialMeld.enabled && !state.initialMeldDone[side]) {
    final minimum = state.initialMeldMin[side];
    if (action is Discard || action is GoOut) {
      if (state.stagedPoints > 0 && state.stagedPoints < minimum) {
        return 'initial meld is below the threshold';
      }
      return null;
    }
    if (action is CreateSeq || action is CreateSet || action is AddToMeld) {
      final points = _actionPoints(state, action);
      // Base legality will reject it with a better message.
      if (points == null) return null;

      final hand = state.hands[player];
      final remaining = Map.of(hand);
      if (action is AddToMeld) {
        remaining[action.ct] = (remaining[action.ct] ?? 0) - 1;
      } else {
        final plan = action is CreateSeq
            ? planSequence(cfg, hand, action.suit, action.start, action.wild)
            : planSet(cfg, hand, (action as CreateSet).rank, action.wild);
        for (final ct in plan!.consumed) {
          remaining[ct] = (remaining[ct] ?? 0) - 1;
        }
      }

      // Post-action staged sets: their ranks stay addable and their free wild
      // slots extend placement capacity.
      final limit = cfg.wildcard.wildcardLimitPerMeld;
      final stagedSets =
          state.sideMelds(side).where((m) => m.kind == MeldKind.set).toList();
      final stagedRanks = {
        for (final m in stagedSets)
          if (m.rank != null) m.rank!,
      };
      var capacity = stagedSets.fold(
          0, (sum, m) => sum + (limit - m.wildCount).clamp(0, limit));
      if (action is CreateSet) {
        stagedRanks.add(action.rank);
        capacity += limit - (action.wild != setWildNone ? 1 : 0);
      } else if (action is AddToMeld && cfg.isWildCard(action.ct)) {
        capacity = capacity - 1 < 0 ? 0 : capacity - 1;
      }

      final bound = maxStageablePoints(
        cfg,
        remaining,
        stagedSetRanks: stagedRanks,
        stagedWildCapacity: capacity,
        reserve: 2,
      );
      if (state.stagedPoints + points + bound < minimum) {
        return 'cannot reach the initial-meld threshold';
      }
    }
  }
  return null;
}

/// All legal structured actions for the player to act, in stable id order.
List<GameAction> legalActions(RoundState state) {
  if (state.roundOver) return const [];
  final cfg = state.cfg;
  final player = state.currentPlayer;
  final side = cfg.table.side(player);
  final hand = state.hands[player];

  if (state.phase == Phase.draw) {
    return [
      if (state.stock.isNotEmpty) const DrawDeck(),
      if (pileDrawAllowed(state)) const DrawTrash(),
      if (state.stock.isEmpty) const EndRound(),
    ];
  }

  final handSize = state.handSize(player);
  // Reachable only via a permitted meld-out; the confirm is forced.
  if (handSize == 0) return const [GoOut()];

  final actions = <GameAction>[];
  final sideMelds = state.sideMelds(side);
  final canCreate = sideMelds.length < cfg.meld.maxMeldSlots;

  if (canCreate && meldResultAllowed(state, side, handSize - 3)) {
    if (cfg.meld.allowSequences) {
      for (final suit in Suit.values) {
        for (var start = 1; start <= numSeqShapes; start++) {
          for (var wild = 0; wild < numSeqWild; wild++) {
            if (planSequence(cfg, hand, suit, start, wild) != null) {
              actions.add(CreateSeq(suit: suit, start: start, wild: wild));
            }
          }
        }
      }
    }
    if (cfg.meld.allowSets) {
      final takenRanks = cfg.meld.uniqueSetRankPerSide
          ? {
              for (final m in sideMelds)
                if (m.kind == MeldKind.set) m.rank,
            }
          : const <int?>{};
      for (final rank in Rank.values) {
        if (takenRanks.contains(rank)) continue;
        for (var wild = 0; wild < numSetWild; wild++) {
          if (planSet(cfg, hand, rank, wild) != null) {
            actions.add(CreateSet(rank: rank, wild: wild));
          }
        }
      }
    }
  }

  final sortedHand = hand.keys.toList()..sort(); // enumeration never mutates
  for (var slot = 0; slot < sideMelds.length; slot++) {
    for (final ct in sortedHand) {
      if (planAdd(cfg, hand, sideMelds[slot], ct) != null &&
          addResultAllowed(state, side, sideMelds[slot], ct)) {
        actions.add(AddToMeld(slot: slot, ct: ct));
      }
    }
  }

  for (final ct in sortedHand) {
    if (discardAllowed(state, ct)) actions.add(Discard(ct: ct));
  }

  return [
    for (final a in actions)
      if (playActionExtraRejection(state, a) == null) a,
  ];
}

/// Legal action ids, sorted — the canonical wire form.
List<int> legalActionIds(RoundState state) {
  final slots = state.cfg.meld.maxMeldSlots;
  return [for (final a in legalActions(state)) encodeAction(a, slots)]..sort();
}
