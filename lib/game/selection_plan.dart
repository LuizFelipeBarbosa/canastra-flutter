/// Turning "these cards, there" into moves the engine will accept.
///
/// The table asks one question — you have picked up some cards, can they go
/// here? — but the engine's action space answers a narrower one. It creates melds
/// at exactly the minimum size and extends them one card at a time, so laying a
/// five-card run down is a create plus two adds, in an order that matters: a 9
/// cannot join 5-6-7 until the 8 has.
///
/// So a selection becomes a *sequence* of action ids. The legality of that
/// sequence is decided by the engine's own planners, run here against a copy of
/// the hand and a copy of the meld — never by a second rulebook written in the
/// UI. Every step of a returned [SelectionPlan] was checked by the same code the
/// host will check it with.
library;

import '../engine/action.dart';
import '../engine/cards.dart';
import '../engine/config.dart';
import '../engine/meld.dart';
import '../multiplayer/table_view.dart';

/// Why a selection cannot be played. The table turns each of these into the
/// sentence the design puts on the "why not" line.
enum Refusal {
  /// Fewer cards than a meld needs, or too few natural ones.
  tooShort,

  /// More wilds than this profile allows in one meld.
  tooManyWilds,

  /// Not a set, and not a run in one suit.
  notAMeld,

  /// Does not fit the meld it was dropped on.
  doesNotFit,

  /// Structurally fine, but the rules forbid it right now — an initial-meld
  /// threshold not met, a black three, a hand that may not be emptied yet.
  notAllowedYet,

  /// You have no canastra, so you may not go out.
  needCanastra,

  /// Your morto has to come to your hand before you can go out.
  mortoFirst,

  /// The sole pile card you just bought cannot go straight back.
  justBought,
}

/// An ordered list of actions that plays a whole selection.
///
/// There is no record here of which card each step spends: the table keeps a
/// selection alive only while its cards are still in hand, so a sequence that
/// stops halfway leaves exactly the unplayed cards picked up.
class SelectionPlan {
  final List<int> steps;
  const SelectionPlan(this.steps);
}

/// The answer to "can these cards go here?".
sealed class PlanResult {
  const PlanResult();
}

class PlanReady extends PlanResult {
  final SelectionPlan plan;
  const PlanReady(this.plan);
}

class PlanRefused extends PlanResult {
  final Refusal reason;
  const PlanRefused(this.reason);
}

/// Rebuild the engine's own [Meld] from the public view of one.
///
/// The view carries everything the engine needs — the cards, which slots are
/// acting as wilds, and where a run starts — because a meld is fully public at a
/// real table. The id is arbitrary: it is never submitted, it only has to be
/// stable inside one simulation.
Meld meldFromView(MeldView view, {int meldId = 0}) => Meld(
  meldId: meldId,
  owner: view.owner,
  kind: view.isSequence ? MeldKind.sequence : MeldKind.set,
  suit: view.suit,
  rank: view.rank,
  startPos: view.startPos,
  slots: [
    for (var i = 0; i < view.cards.length; i++)
      Slot(
        view.cards[i],
        view.wildIndices.contains(i) ? SlotRole.wild : SlotRole.natural,
      ),
  ],
);

/// Lay [selection] down as a brand-new meld.
///
/// The engine offers one create action per shape it would accept. Each is asked
/// to plan itself out of the selection *alone*, so a create can never reach past
/// the cards you picked up. Whatever a create leaves over is then added on, which
/// is how a selection longer than the minimum meld becomes legal.
PlanResult planNewMeld(
  RulesConfig cfg,
  TableView view,
  List<CardId> selection,
) {
  final slot = view.myMelds.length;
  final slots = cfg.meld.maxMeldSlots;
  final guard = _StrandGuard(cfg: cfg, view: view, replacing: -1);

  SelectionPlan? best;
  var bestWilds = 1 << 30;
  var stranded = false;

  for (final id in view.legalActions) {
    final action = decodeAction(id, slots);
    if (action is! CreateSeq && action is! CreateSet) continue;

    // A fresh copy per candidate: creating consumes the pool it is given.
    final pool = _multiset(selection);
    final Meld created;
    try {
      created = switch (action) {
        CreateSeq(:final suit, :final start, :final wild) => createSequence(
          cfg,
          pool,
          view.side,
          slot,
          suit,
          start,
          wild,
        ),
        CreateSet(:final rank, :final wild) => createSet(
          cfg,
          pool,
          view.side,
          slot,
          rank,
          wild,
          prefer: view.pendingPileCard,
        ),
        // Unreachable: the guard above admits only the two create families.
        _ => throw MeldError('not a create action'),
      };
    } on MeldError {
      continue;
    }

    final drain = _drainOnto(
      cfg,
      pool,
      created,
      guard: guard,
      handSize: view.hand.length - created.size,
      pendingPileCard: view.pendingPileCard,
    );
    // A candidate only counts if it plays every card that was picked up.
    if (!drain.complete) {
      stranded = stranded || drain.stranded;
      continue;
    }

    // Prefer the shape that spends the fewest wilds: five cards that make a run
    // of naturals should not be laid down as a run with a two standing in.
    if (created.wildCount < bestWilds) {
      bestWilds = created.wildCount;
      best = SelectionPlan([
        id,
        for (final ct in drain.added)
          encodeAction(AddToMeld(slot: slot, ct: ct), slots),
      ]);
    }
  }

  if (best != null) return PlanReady(best);
  // A shape the engine would take, blocked only by what it would leave you
  // holding, deserves the reason it was actually blocked for.
  if (stranded) return PlanRefused(guard.strandReason);
  return PlanRefused(_shapeRefusal(cfg, selection) ?? Refusal.notAMeld);
}

/// Add [selection] to the meld already in [slot].
PlanResult planExtendMeld(
  RulesConfig cfg,
  TableView view,
  int slot,
  List<CardId> selection,
) {
  if (selection.isEmpty || slot < 0 || slot >= view.myMelds.length) {
    return const PlanRefused(Refusal.doesNotFit);
  }

  final pool = _multiset(selection);
  final guard = _StrandGuard(cfg: cfg, view: view, replacing: slot);
  final drain = _drainOnto(
    cfg,
    pool,
    meldFromView(view.myMelds[slot]),
    guard: guard,
    handSize: view.hand.length,
    pendingPileCard: view.pendingPileCard,
  );
  if (!drain.complete) {
    return PlanRefused(
      drain.stranded ? guard.strandReason : Refusal.doesNotFit,
    );
  }

  final steps = [
    for (final ct in drain.added)
      encodeAction(AddToMeld(slot: slot, ct: ct), cfg.meld.maxMeldSlots),
  ];
  // The host has only ruled on the first step. If that one is not on the table's
  // own list, the shape is fine but the rules say not right now.
  if (!view.legalActions.contains(steps.first)) {
    return const PlanRefused(Refusal.notAllowedYet);
  }
  return PlanReady(SelectionPlan(steps));
}

class _Drain {
  /// Cards added, in the order they must be submitted.
  final List<CardId> added;

  /// Every card the pool started with was played.
  final bool complete;

  /// A card fitted, but playing it would have stranded the hand. Worth knowing
  /// apart from "does not fit", because it is a different sentence to the player.
  final bool stranded;

  const _Drain(this.added, this.complete, {this.stranded = false});
}

/// The engine's anti-stranding rule, as the client can see it.
///
/// A play may not leave you holding fewer than two cards unless your morto is
/// still coming — it will refill the hand — or you are already able to go out. The
/// engine applies this to every action separately, so a four-card extension can be
/// legal for its first two cards and refused for the third. Modelling it here is
/// what stops the table offering a play the host would only half-take.
class _StrandGuard {
  final RulesConfig cfg;
  final TableView view;

  /// Index in `view.myMelds` of the meld being changed, or -1 when it is new.
  final int replacing;

  _StrandGuard({
    required this.cfg,
    required this.view,
    required this.replacing,
  });

  bool get _mortoComing =>
      view.side < view.mortoSizes.length &&
      view.mortoSizes[view.side] > 0 &&
      view.side < view.mortoTaken.length &&
      !view.mortoTaken[view.side];

  bool allows(int resultingHand, Meld target) {
    if (resultingHand >= 2) return true;
    if (_mortoComing) return true;
    if (!_canGoOutWith(target)) return false;
    final policy = cfg.goingOut.discardToGoOut;
    // Emptying the hand ends the round through GO_OUT; leaving one card ends it
    // through a final discard. A profile can forbid either route.
    if (resultingHand == 0) return policy != discardOutRequired;
    return policy != discardOutForbidden;
  }

  bool _canGoOutWith(Meld target) {
    final out = cfg.goingOut;
    if (out.requireMortoTaken &&
        !(view.side < view.mortoTaken.length && view.mortoTaken[view.side])) {
      return false;
    }
    if (!out.requireCanastra) return true;
    var qualifying = 0;
    for (var slot = 0; slot < view.myMelds.length; slot++) {
      if (slot == replacing) continue;
      final m = view.myMelds[slot];
      if (m.isCanastra && (m.isClean || !out.requireCleanCanastra)) {
        qualifying += 1;
      }
    }
    if (target.isCanastra(cfg.meld.canastraMinSize) &&
        (target.isClean || !out.requireCleanCanastra)) {
      qualifying += 1;
    }
    return qualifying >= out.goOutMinCanastras;
  }

  /// Which of the design's two sentences fits this table.
  Refusal get strandReason =>
      cfg.goingOut.requireMortoTaken &&
          view.side < view.mortoTaken.length &&
          !view.mortoTaken[view.side]
      ? Refusal.mortoFirst
      : Refusal.needCanastra;
}

/// Greedily add every card in [pool] onto [meld], mutating both.
///
/// Repeated passes rather than one, because order decides legality: on a first
/// pass over 8-9 onto 5-6-7 only the 8 fits, and the 9 becomes legal because of
/// it. The loop stops when a whole pass adds nothing, which is when the leftovers
/// genuinely do not belong.
///
/// The budget is what the pool held on entry, not the pool itself: extending over
/// a wild can hand that wild back, and a card the player never picked up must not
/// then be played on.
_Drain _drainOnto(
  RulesConfig cfg,
  Map<CardId, int> pool,
  Meld meld, {
  required _StrandGuard guard,
  required int handSize,
  CardId? pendingPileCard,
}) {
  final budget = Map.of(pool);
  final spent = <CardId, int>{};
  final added = <CardId>[];
  var hand = handSize;
  var stranded = false;

  var progress = true;
  while (progress) {
    progress = false;
    final candidates = budget.keys.toList()..sort();
    if (pendingPileCard != null && budget.containsKey(pendingPileCard)) {
      candidates
        ..remove(pendingPileCard)
        ..insert(0, pendingPileCard);
    }
    // Low card first, so a run grows from one end in a single pass.
    for (final ct in candidates) {
      if ((spent[ct] ?? 0) >= budget[ct]!) continue;
      final plan = planAdd(cfg, pool, meld, ct);
      if (plan == null) continue;

      // The engine judges each add on the state it would leave behind, so the
      // simulation has to as well — including a swap that hands a wild back and
      // leaves the hand the size it was.
      final resulting = hand - 1 + (plan.wildToHand ? 1 : 0);
      final after = meld.copy();
      final probe = Map.of(pool);
      try {
        applyAdd(cfg, probe, after, ct);
      } on MeldError {
        continue;
      }
      if (!guard.allows(resulting, after)) {
        stranded = true;
        continue;
      }

      applyAdd(cfg, pool, meld, ct);
      hand = resulting;
      spent[ct] = (spent[ct] ?? 0) + 1;
      added.add(ct);
      progress = true;
    }
  }

  final complete = budget.entries.every((e) => (spent[e.key] ?? 0) == e.value);
  return _Drain(added, complete, stranded: !complete && stranded);
}

/// A fallback refusal phrase for a selection no engine candidate could consume.
///
/// These context-free counts are deliberately consulted only after replaying
/// every legal create. A two may be natural in its own run position, so this
/// heuristic can describe a failure but must never decide legality.
Refusal? _shapeRefusal(RulesConfig cfg, List<CardId> selection) {
  if (selection.length < cfg.meld.minMeldSize) return Refusal.tooShort;
  final wilds = _wildsIn(cfg, selection);
  if (wilds > cfg.wildcard.wildcardLimitPerMeld) return Refusal.tooManyWilds;
  if (selection.length - wilds < cfg.wildcard.minNaturalsPerMeld) {
    return Refusal.tooShort;
  }
  return null;
}

int _wildsIn(RulesConfig cfg, Iterable<CardId> cards) =>
    cards.where(cfg.isWildCard).length;

Map<CardId, int> _multiset(Iterable<CardId> cards) {
  final counts = <CardId, int>{};
  for (final c in cards) {
    counts[c] = (counts[c] ?? 0) + 1;
  }
  return counts;
}
