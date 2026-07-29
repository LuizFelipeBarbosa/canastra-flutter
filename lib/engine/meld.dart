/// Meld model, validation, wildcard resolution and canastra detection.
///
/// A sequence meld stores its low sequence position (`startPos`, 1 = ace-low,
/// 14 = ace-high) and an ordered low→high slot list; slot `i` occupies position
/// `startPos + i`, which makes the rank a wild represents derivable rather than
/// stored.
///
/// The plan/apply split keeps legality checks pure: the `plan*` functions
/// inspect a hand and return a plan (or null when illegal) without mutating
/// anything; `createSequence`/`createSet`/`applyAdd` execute a plan, mutating
/// hand and meld. `legal.dart` enumerates actions by probing the planners.
library;

import 'cards.dart';
import 'config.dart';

// Wild-source parameter values.
const int seqWildNone = 0;
const int seqWildJoker = 1;
const int seqWildTwoOfSuit = 2;
const int seqWildOffSuitTwo = 3;

const int setWildNone = 0;
const int setWildJoker = 1;
const int setWildTwo = 2;

/// A meld operation violated the active rules.
class MeldError implements Exception {
  final String message;
  MeldError(this.message);
  @override
  String toString() => 'MeldError: $message';
}

enum MeldKind { sequence, set }

enum SlotRole { natural, wild }

class Slot {
  CardId card;
  SlotRole role;
  Slot(this.card, this.role);
}

class Meld {
  final int meldId;

  /// Side id (team in 4p, player in 2p).
  final int owner;
  final MeldKind kind;

  /// Sequences only.
  final int? suit;

  /// Sets only.
  final int? rank;

  /// Sequences only: position of `slots[0]`.
  int? startPos;

  final List<Slot> slots;

  Meld({
    required this.meldId,
    required this.owner,
    required this.kind,
    this.suit,
    this.rank,
    this.startPos,
    List<Slot>? slots,
  }) : slots = slots ?? [];

  // --- derived properties (never stored) ---

  int get size => slots.length;

  int get wildCount => slots.where((s) => s.role == SlotRole.wild).length;

  /// Limpa: contains no card acting as a wild.
  bool get isClean => wildCount == 0;

  /// Sequence position of the last slot (null for sets).
  int? get endPos => startPos == null ? null : startPos! + slots.length - 1;

  /// Slot index of the first wild, or null.
  int? get wildPosIndex {
    for (var i = 0; i < slots.length; i++) {
      if (slots[i].role == SlotRole.wild) return i;
    }
    return null;
  }

  bool isCanastra(int minSize) => slots.length >= minSize;

  /// Rank the slot stands for: its position rank in a sequence, the set's rank
  /// in a set.
  int representedRank(int slotIndex) =>
      kind == MeldKind.sequence ? rankAt(startPos! + slotIndex) : rank!;

  Map<CardId, int> cardMultiset() {
    final counts = <CardId, int>{};
    for (final s in slots) {
      counts[s.card] = (counts[s.card] ?? 0) + 1;
    }
    return counts;
  }

  Meld copy() => Meld(
    meldId: meldId,
    owner: owner,
    kind: kind,
    suit: suit,
    rank: rank,
    startPos: startPos,
    slots: [for (final s in slots) Slot(s.card, s.role)],
  );
}

// --- position and role predicates --------------------------------------------

/// Ace policy: whether a sequence may occupy position [pos].
bool posAllowed(RulesConfig cfg, int pos) {
  if (pos < kPosMin || pos > kPosMax) return false;
  final policy = cfg.meld.acePolicy;
  if (pos == kPosMax && policy == aceLowOnly) return false;
  if (pos == kPosMin && policy == aceHighOnly) return false;
  return true;
}

// --- precomputed hot-path tables ----------------------------------------------

/// `[start] -> (start, start+1, start+2)` for starts 1..12; index 0 unused.
final List<List<int>?> _seqPositions = List.generate(
  kPosMax - 1,
  (s) => s < kPosMin ? null : [s, s + 1, s + 2],
);

/// `[suit][start] -> the three natural card ids`; start index 0 unused.
final List<List<List<CardId>?>> _seqNats = List.generate(
  4,
  (suit) => List.generate(
    kPosMax - 1,
    (s) =>
        s < kPosMin ? null : [nat(s, suit), nat(s + 1, suit), nat(s + 2, suit)],
  ),
);

final List<CardId> _twoOfSuit = List.generate(4, (s) => cardId(Rank.two, s));

/// Other suits in ascending order — the canonical off-suit-two selection order.
final List<List<int>> _otherSuits = List.generate(
  4,
  (s) => [
    for (final o in Suit.values)
      if (o != s) o,
  ],
);

/// `[rank] -> the four natural card ids, lowest suit first`.
final List<List<CardId>> _setNats = List.generate(
  13,
  (r) => [for (final s in Suit.values) cardId(r, s)],
);

class _CfgTables {
  /// `isWildCard(ct)` for ct 0..53.
  final List<bool> wild;

  /// `[suit][pos]`: the position's natural card counts as NATURAL.
  final List<List<bool>> naturalOk;

  /// `posAllowed(pos)` for pos 0..15.
  final List<bool> posOk;

  /// All three positions allowed, for starts 0..12.
  final List<bool> seqStartOk;

  final bool seqEnabled;
  final bool setEnabled;
  final bool twoIsWild;

  _CfgTables({
    required this.wild,
    required this.naturalOk,
    required this.posOk,
    required this.seqStartOk,
    required this.seqEnabled,
    required this.setEnabled,
    required this.twoIsWild,
  });
}

final Expando<_CfgTables> _tablesCache = Expando('meldTables');

_CfgTables _cfgTables(RulesConfig cfg) {
  final cached = _tablesCache[cfg];
  if (cached != null) return cached;
  final tables = _CfgTables(
    wild: List.generate(kCardSpace, cfg.isWildCard),
    naturalOk: List.generate(
      4,
      (s) => List.generate(
        kPosMax + 1,
        (p) => p < kPosMin
            ? false
            : !cfg.isWildCard(nat(p, s)) || cfg.wildcard.naturalTwoInSuit,
      ),
    ),
    posOk: List.generate(kPosMax + 2, (p) => posAllowed(cfg, p)),
    seqStartOk: List.generate(
      kPosMax - 1,
      (s) => s < kPosMin
          ? false
          : posAllowed(cfg, s) &&
                posAllowed(cfg, s + 1) &&
                posAllowed(cfg, s + 2),
    ),
    seqEnabled: cfg.meld.allowSequences && cfg.meld.minMeldSize <= 3,
    setEnabled: cfg.meld.allowSets && cfg.meld.minMeldSize <= 3,
    twoIsWild: cfg.wildcard.wildRanks.contains(Rank.two),
  );
  _tablesCache[cfg] = tables;
  return tables;
}

/// Whether [ct] fills sequence position [pos] in [suit] as a NATURAL.
///
/// A wild-rank card is natural only in its own suit's own-rank position, and
/// only when the profile grants the natural-2 exception.
bool isNaturalAt(RulesConfig cfg, CardId ct, int pos, int suit) =>
    ct == nat(pos, suit) && _cfgTables(cfg).naturalOk[suit][pos];

// --- plans (pure legality + canonical resolution) -----------------------------

class CreatePlan {
  final List<CardId> consumed;
  final List<(CardId, SlotRole)> slots;
  const CreatePlan({required this.consumed, required this.slots});
}

/// Multiset check: the same card type may be needed more than once (a 2 held
/// once cannot serve as both the natural at position 2 and the wild).
bool _handCovers(Map<CardId, int> hand, List<CardId> consumed) {
  final needed = <CardId, int>{};
  for (final c in consumed) {
    needed[c] = (needed[c] ?? 0) + 1;
  }
  return needed.entries.every((e) => (hand[e.key] ?? 0) >= e.value);
}

enum AddKind { extend, swap, setAppend }

class AddPlan {
  final AddKind kind;

  /// Role of the added card's slot.
  final SlotRole role;

  /// extend: which end. swap: where the freed wild goes.
  final bool atLow;

  /// swap under the `TO_HAND` relocation policy.
  final bool wildToHand;

  const AddPlan({
    required this.kind,
    required this.role,
    this.atLow = false,
    this.wildToHand = false,
  });
}

/// Canonical physical wild for a sequence gap, or null if unavailable.
CardId? _seqWildCard(
  RulesConfig cfg,
  Map<CardId, int> hand,
  int suit,
  int gapPos,
  int wildChoice,
) {
  if (cfg.wildcard.wildcardLimitPerMeld < 1) return null;
  if (wildChoice == seqWildJoker) {
    if (cfg.wildcard.jokersWild && (hand[kJoker] ?? 0) > 0) return kJoker;
    return null;
  }
  if (wildChoice == seqWildTwoOfSuit) {
    final ct = _twoOfSuit[suit];
    if (_cfgTables(cfg).twoIsWild && (hand[ct] ?? 0) > 0) {
      // At its own natural position it would not act as a wild.
      if (isNaturalAt(cfg, ct, gapPos, suit)) return null;
      return ct;
    }
    return null;
  }
  if (wildChoice == seqWildOffSuitTwo) {
    if (!_cfgTables(cfg).twoIsWild) return null;
    for (final other in _otherSuits[suit]) {
      final ct = _twoOfSuit[other];
      if ((hand[ct] ?? 0) > 0) return ct;
    }
    return null;
  }
  return null;
}

/// Minimum-size (3) sequence creation.
CreatePlan? planSequence(
  RulesConfig cfg,
  Map<CardId, int> hand,
  int suit,
  int startPos,
  int wildChoice,
) {
  final tables = _cfgTables(cfg);
  if (!tables.seqEnabled) return null;
  if (startPos < kPosMin || startPos + 2 > kPosMax) return null;
  if (!tables.seqStartOk[startPos]) return null;

  final positions = _seqPositions[startPos]!;
  final nats = _seqNats[suit][startPos]!;
  final naturalOk = tables.naturalOk[suit];

  final held = <int>[];
  for (var i = 0; i < 3; i++) {
    if ((hand[nats[i]] ?? 0) > 0 && naturalOk[positions[i]]) {
      held.add(positions[i]);
    }
  }

  if (wildChoice == seqWildNone) {
    if (held.length != 3) return null;
    return CreatePlan(
      consumed: List.of(nats),
      slots: [for (final c in nats) (c, SlotRole.natural)],
    );
  }

  if (held.length != 2) return null;
  final gap = positions.firstWhere((p) => !held.contains(p));
  final wildCt = _seqWildCard(cfg, hand, suit, gap, wildChoice);
  if (wildCt == null) return null;

  final slots = <(CardId, SlotRole)>[
    for (var i = 0; i < 3; i++)
      if (positions[i] == gap)
        (wildCt, SlotRole.wild)
      else
        (nats[i], SlotRole.natural),
  ];
  final consumed = [for (final s in slots) s.$1];
  if (!_handCovers(hand, consumed)) return null;
  return CreatePlan(consumed: consumed, slots: slots);
}

/// Minimum-size (3) same-rank set creation.
///
/// [prefer] forces one specific card into the naturals — Canasta's forced
/// pile-card meld must consume the taken top card itself, and the canonical
/// lowest-suit-first selection could otherwise leave it in hand.
CreatePlan? planSet(
  RulesConfig cfg,
  Map<CardId, int> hand,
  int rank,
  int wildChoice, {
  CardId? prefer,
}) {
  final tables = _cfgTables(cfg);
  if (!tables.setEnabled) return null;
  // A set of wilds is not a set (masked while the rank is wild).
  if (cfg.wildcard.wildRanks.contains(rank)) return null;

  final needNaturals = wildChoice == setWildNone ? 3 : 2;
  if (wildChoice != setWildNone) {
    if (cfg.wildcard.wildcardLimitPerMeld < 1) return null;
    if (cfg.wildcard.minNaturalsPerMeld > 2) return null;
  }

  final naturals = <CardId>[];
  if (prefer != null) {
    if (idRank(prefer) != rank || (hand[prefer] ?? 0) < 1) return null;
    naturals.add(prefer);
  }
  for (final ct in _setNats[rank]) {
    // Canonical: lowest suit first, copies together.
    final avail = (hand[ct] ?? 0) - (ct == prefer ? 1 : 0);
    final take = avail < needNaturals - naturals.length
        ? avail
        : needNaturals - naturals.length;
    for (var i = 0; i < take; i++) {
      naturals.add(ct);
    }
    if (naturals.length == needNaturals) break;
  }
  if (naturals.length < needNaturals) return null;

  if (wildChoice == setWildNone) {
    return CreatePlan(
      consumed: naturals,
      slots: [for (final c in naturals) (c, SlotRole.natural)],
    );
  }

  final CardId wildCt;
  if (wildChoice == setWildJoker) {
    if (!(cfg.wildcard.jokersWild && (hand[kJoker] ?? 0) > 0)) return null;
    wildCt = kJoker;
  } else {
    if (!tables.twoIsWild) return null;
    final found = _twoOfSuit.where((ct) => (hand[ct] ?? 0) > 0);
    if (found.isEmpty) return null;
    wildCt = found.first;
  }

  final slots = <(CardId, SlotRole)>[
    for (final c in naturals) (c, SlotRole.natural),
    (wildCt, SlotRole.wild),
  ];
  final consumed = [...naturals, wildCt];
  if (!_handCovers(hand, consumed)) return null;
  return CreatePlan(consumed: consumed, slots: slots);
}

/// Extension of an existing meld by one card.
AddPlan? planAdd(RulesConfig cfg, Map<CardId, int> hand, Meld meld, CardId ct) {
  if ((hand[ct] ?? 0) <= 0) return null;
  final tables = _cfgTables(cfg);

  if (meld.kind == MeldKind.set) {
    if (idRank(ct) == meld.rank && !tables.wild[ct]) {
      return const AddPlan(kind: AddKind.setAppend, role: SlotRole.natural);
    }
    if (tables.wild[ct] && meld.wildCount < cfg.wildcard.wildcardLimitPerMeld) {
      return const AddPlan(kind: AddKind.setAppend, role: SlotRole.wild);
    }
    return null;
  }

  final suit = meld.suit!;
  final st = meld.startPos!;
  final en = meld.endPos!;
  final lowOpen = tables.posOk[st - 1];
  final highOpen = tables.posOk[en + 1];

  // 1. Natural end extension (includes the natural-2 landing on position 2).
  if (lowOpen && isNaturalAt(cfg, ct, st - 1, suit)) {
    return const AddPlan(
      kind: AddKind.extend,
      role: SlotRole.natural,
      atLow: true,
    );
  }
  if (highOpen && isNaturalAt(cfg, ct, en + 1, suit)) {
    return const AddPlan(
      kind: AddKind.extend,
      role: SlotRole.natural,
      atLow: false,
    );
  }

  // 2. Wild swap-and-relocate: ct is the natural at the wild's position.
  final wi = meld.wildPosIndex;
  if (wi != null && isNaturalAt(cfg, ct, st + wi, suit)) {
    if (cfg.wildcard.wildRelocation == wildToHand) {
      return const AddPlan(
        kind: AddKind.swap,
        role: SlotRole.natural,
        wildToHand: true,
      );
    }
    // Deterministic: low end first.
    if (lowOpen) {
      return const AddPlan(
        kind: AddKind.swap,
        role: SlotRole.natural,
        atLow: true,
      );
    }
    if (highOpen) {
      return const AddPlan(
        kind: AddKind.swap,
        role: SlotRole.natural,
        atLow: false,
      );
    }
    return null; // meld spans the full run; no home for the freed wild
  }

  // 3. Wild placement on an open end (low end first).
  if (tables.wild[ct] && meld.wildCount < cfg.wildcard.wildcardLimitPerMeld) {
    if (lowOpen) {
      return const AddPlan(
        kind: AddKind.extend,
        role: SlotRole.wild,
        atLow: true,
      );
    }
    if (highOpen) {
      return const AddPlan(
        kind: AddKind.extend,
        role: SlotRole.wild,
        atLow: false,
      );
    }
  }
  return null;
}

// --- application (mutating) ---------------------------------------------------

void _consume(Map<CardId, int> hand, CardId ct) {
  final n = hand[ct] ?? 0;
  if (n <= 0) throw MeldError('hand does not contain card type $ct');
  if (n == 1) {
    hand.remove(ct);
  } else {
    hand[ct] = n - 1;
  }
}

Meld createSequence(
  RulesConfig cfg,
  Map<CardId, int> hand,
  int owner,
  int meldId,
  int suit,
  int startPos,
  int wildChoice,
) {
  final plan = planSequence(cfg, hand, suit, startPos, wildChoice);
  if (plan == null) {
    throw MeldError(
      'illegal sequence: suit=$suit start=$startPos wild=$wildChoice',
    );
  }
  for (final ct in plan.consumed) {
    _consume(hand, ct);
  }
  final meld = Meld(
    meldId: meldId,
    owner: owner,
    kind: MeldKind.sequence,
    suit: suit,
    startPos: startPos,
    slots: [for (final s in plan.slots) Slot(s.$1, s.$2)],
  );
  validateMeld(cfg, meld);
  return meld;
}

Meld createSet(
  RulesConfig cfg,
  Map<CardId, int> hand,
  int owner,
  int meldId,
  int rank,
  int wildChoice, {
  CardId? prefer,
}) {
  final plan = planSet(cfg, hand, rank, wildChoice, prefer: prefer);
  if (plan == null) throw MeldError('illegal set: rank=$rank wild=$wildChoice');
  for (final ct in plan.consumed) {
    _consume(hand, ct);
  }
  final meld = Meld(
    meldId: meldId,
    owner: owner,
    kind: MeldKind.set,
    rank: rank,
    slots: [for (final s in plan.slots) Slot(s.$1, s.$2)],
  );
  validateMeld(cfg, meld);
  return meld;
}

/// Add one card from [hand] to [meld] per the canonical plan.
void applyAdd(RulesConfig cfg, Map<CardId, int> hand, Meld meld, CardId ct) {
  final plan = planAdd(cfg, hand, meld, ct);
  if (plan == null) {
    throw MeldError('illegal add: card $ct onto meld ${meld.meldId}');
  }
  _consume(hand, ct);

  switch (plan.kind) {
    case AddKind.setAppend:
      meld.slots.add(Slot(ct, plan.role));
    case AddKind.extend:
      if (plan.atLow) {
        meld.slots.insert(0, Slot(ct, plan.role));
        meld.startPos = meld.startPos! - 1;
      } else {
        meld.slots.add(Slot(ct, plan.role));
      }
    case AddKind.swap:
      final wi = meld.wildPosIndex!;
      final freed = meld.slots[wi].card;
      meld.slots[wi] = Slot(ct, SlotRole.natural);
      if (plan.wildToHand) {
        hand[freed] = (hand[freed] ?? 0) + 1;
      } else if (plan.atLow) {
        final newPos = meld.startPos! - 1;
        final role = isNaturalAt(cfg, freed, newPos, meld.suit!)
            ? SlotRole.natural
            : SlotRole.wild;
        meld.slots.insert(0, Slot(freed, role));
        meld.startPos = newPos;
      } else {
        final end = meld.endPos!;
        final role = isNaturalAt(cfg, freed, end + 1, meld.suit!)
            ? SlotRole.natural
            : SlotRole.wild;
        meld.slots.add(Slot(freed, role));
      }
  }
  validateMeld(cfg, meld);
}

// --- structural validation -----------------------------------------------------

/// Full structural check; throws [MeldError] on any violation.
void validateMeld(RulesConfig cfg, Meld meld) {
  if (meld.size < cfg.meld.minMeldSize) {
    throw MeldError('meld ${meld.meldId} below minimum size');
  }
  if (meld.wildCount > cfg.wildcard.wildcardLimitPerMeld) {
    throw MeldError('meld ${meld.meldId} exceeds wildcard limit');
  }

  if (meld.kind == MeldKind.sequence) {
    if (!cfg.meld.allowSequences) {
      throw MeldError('sequences not allowed by profile');
    }
    if (meld.suit == null || meld.startPos == null || meld.rank != null) {
      throw MeldError('malformed sequence meld');
    }
    final end = meld.endPos!;
    if (meld.startPos! < kPosMin || end > kPosMax) {
      throw MeldError('sequence out of position range');
    }
    if (!(posAllowed(cfg, meld.startPos!) && posAllowed(cfg, end))) {
      throw MeldError('sequence violates ace policy');
    }
    for (var i = 0; i < meld.slots.length; i++) {
      final slot = meld.slots[i];
      final pos = meld.startPos! + i;
      final naturalHere = isNaturalAt(cfg, slot.card, pos, meld.suit!);
      if (slot.role == SlotRole.natural && !naturalHere) {
        throw MeldError(
          'slot $i claims NATURAL but is not ${nat(pos, meld.suit!)}',
        );
      }
      if (slot.role == SlotRole.wild &&
          (naturalHere || !cfg.isWildCard(slot.card))) {
        throw MeldError('slot $i claims WILD illegitimately');
      }
    }
  } else {
    if (!cfg.meld.allowSets) throw MeldError('sets not allowed by profile');
    if (meld.rank == null || meld.suit != null || meld.startPos != null) {
      throw MeldError('malformed set meld');
    }
    var naturals = 0;
    for (var i = 0; i < meld.slots.length; i++) {
      final slot = meld.slots[i];
      if (slot.role == SlotRole.natural) {
        if (cfg.isWildCard(slot.card) || idRank(slot.card) != meld.rank) {
          throw MeldError('set slot $i claims NATURAL illegitimately');
        }
        naturals++;
      } else if (!cfg.isWildCard(slot.card)) {
        throw MeldError('set slot $i claims WILD but card is not wild');
      }
    }
    if (naturals < cfg.wildcard.minNaturalsPerMeld) {
      throw MeldError('set below minimum natural count');
    }
  }
}
