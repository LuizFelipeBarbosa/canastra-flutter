/// Action types and integer-id encode/decode.
///
/// Fixed layout, parametrised only by `S = maxMeldSlots`. With the default
/// `S = 24` the space is `A = 1585` ids:
///
/// | family          | base        | size        |
/// |-----------------|-------------|-------------|
/// | DRAW_DECK       | 0           | 1           |
/// | DRAW_TRASH      | 1           | 1           |
/// | CREATE_SEQUENCE | 2           | 4·12·4 =192 |
/// | CREATE_SET      | 194         | 13·3 = 39   |
/// | ADD_TO_MELD     | 233         | S·54        |
/// | DISCARD         | 233 + S·54  | 54          |
/// | GO_OUT          | +54         | 1           |
/// | END_ROUND       | +55         | 1           |
///
/// The stable ids are what travels over the wire in multiplayer and what the
/// replay log stores, so the layout must not change between client versions.
library;

import 'cards.dart';

// Wild-source dimensions; the values themselves live in `meld.dart`.
const int numSeqWild = 4; // none / joker / two-of-suit / off-suit-two
const int numSetWild = 3; // none / joker / two
const int numSeqShapes = 12; // start positions 1..12 for length-3 creation

const int baseSeq = 2;
const int baseSet = baseSeq + 4 * numSeqShapes * numSeqWild; // 194
const int baseAdd = baseSet + 13 * numSetWild; // 233

sealed class GameAction {
  const GameAction();
}

class DrawDeck extends GameAction {
  const DrawDeck();
  @override
  bool operator ==(Object other) => other is DrawDeck;
  @override
  int get hashCode => 0;
  @override
  String toString() => 'DrawDeck()';
}

class DrawTrash extends GameAction {
  const DrawTrash();
  @override
  bool operator ==(Object other) => other is DrawTrash;
  @override
  int get hashCode => 1;
  @override
  String toString() => 'DrawTrash()';
}

class CreateSeq extends GameAction {
  final int suit;

  /// Sequence position of the low card, 1..12.
  final int start;

  /// A `seqWild*` constant.
  final int wild;

  const CreateSeq({
    required this.suit,
    required this.start,
    required this.wild,
  });

  @override
  bool operator ==(Object other) =>
      other is CreateSeq &&
      other.suit == suit &&
      other.start == start &&
      other.wild == wild;
  @override
  int get hashCode => Object.hash('seq', suit, start, wild);
  @override
  String toString() => 'CreateSeq(suit: $suit, start: $start, wild: $wild)';
}

class CreateSet extends GameAction {
  final int rank;

  /// A `setWild*` constant.
  final int wild;

  const CreateSet({required this.rank, required this.wild});

  @override
  bool operator ==(Object other) =>
      other is CreateSet && other.rank == rank && other.wild == wild;
  @override
  int get hashCode => Object.hash('set', rank, wild);
  @override
  String toString() => 'CreateSet(rank: $rank, wild: $wild)';
}

class AddToMeld extends GameAction {
  /// Index into the acting side's melds, in creation order.
  final int slot;
  final CardId ct;

  const AddToMeld({required this.slot, required this.ct});

  @override
  bool operator ==(Object other) =>
      other is AddToMeld && other.slot == slot && other.ct == ct;
  @override
  int get hashCode => Object.hash('add', slot, ct);
  @override
  String toString() => 'AddToMeld(slot: $slot, ct: $ct)';
}

class Discard extends GameAction {
  final CardId ct;
  const Discard({required this.ct});

  @override
  bool operator ==(Object other) => other is Discard && other.ct == ct;
  @override
  int get hashCode => Object.hash('discard', ct);
  @override
  String toString() => 'Discard(ct: $ct)';
}

class GoOut extends GameAction {
  const GoOut();
  @override
  bool operator ==(Object other) => other is GoOut;
  @override
  int get hashCode => 2;
  @override
  String toString() => 'GoOut()';
}

class EndRound extends GameAction {
  const EndRound();
  @override
  bool operator ==(Object other) => other is EndRound;
  @override
  int get hashCode => 3;
  @override
  String toString() => 'EndRound()';
}

int baseDiscard(int maxMeldSlots) => baseAdd + maxMeldSlots * kCardSpace;

int actionSpaceSize(int maxMeldSlots) =>
    baseDiscard(maxMeldSlots) + kCardSpace + 2;

/// Structured action → stable integer id.
int encodeAction(GameAction action, int maxMeldSlots) {
  switch (action) {
    case DrawDeck():
      return 0;
    case DrawTrash():
      return 1;
    case CreateSeq(:final suit, :final start, :final wild):
      assert(
        start >= 1 && start <= numSeqShapes && wild >= 0 && wild < numSeqWild,
      );
      return baseSeq + (suit * numSeqShapes + (start - 1)) * numSeqWild + wild;
    case CreateSet(:final rank, :final wild):
      assert(wild >= 0 && wild < numSetWild);
      return baseSet + rank * numSetWild + wild;
    case AddToMeld(:final slot, :final ct):
      assert(slot >= 0 && slot < maxMeldSlots && ct >= 0 && ct < kCardSpace);
      return baseAdd + slot * kCardSpace + ct;
    case Discard(:final ct):
      assert(ct >= 0 && ct < kCardSpace);
      return baseDiscard(maxMeldSlots) + ct;
    case GoOut():
      return baseDiscard(maxMeldSlots) + kCardSpace;
    case EndRound():
      return baseDiscard(maxMeldSlots) + kCardSpace + 1;
  }
}

/// Integer id → structured action (total inverse of [encodeAction]).
GameAction decodeAction(int a, int maxMeldSlots) {
  if (a < 0 || a >= actionSpaceSize(maxMeldSlots)) {
    throw ArgumentError('action id out of range: $a');
  }
  if (a == 0) return const DrawDeck();
  if (a == 1) return const DrawTrash();
  if (a < baseSet) {
    var x = a - baseSeq;
    final w = x % numSeqWild;
    x ~/= numSeqWild;
    return CreateSeq(
      suit: x ~/ numSeqShapes,
      start: x % numSeqShapes + 1,
      wild: w,
    );
  }
  if (a < baseAdd) {
    final x = a - baseSet;
    return CreateSet(rank: x ~/ numSetWild, wild: x % numSetWild);
  }
  final disc = baseDiscard(maxMeldSlots);
  if (a < disc) {
    final x = a - baseAdd;
    return AddToMeld(slot: x ~/ kCardSpace, ct: x % kCardSpace);
  }
  if (a < disc + kCardSpace) return Discard(ct: a - disc);
  if (a == disc + kCardSpace) return const GoOut();
  return const EndRound();
}
