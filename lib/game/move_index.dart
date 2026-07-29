/// Turns the engine's flat list of legal action ids into something tappable.
///
/// The engine offers moves as integers over a fixed action space — correct, but
/// not something you can point at. This walks that list once per view and works
/// out, for each move, which cards in your hand it spends and where those cards
/// land. The screen can then answer the only two questions a player asks: "what
/// can I do with this card?" and "what can go here?".
///
/// The consumed-card sets come from the engine's own planners, so a move is
/// never offered on a card the engine would not actually spend.
library;

import '../engine/action.dart';
import '../engine/cards.dart';
import '../engine/config.dart';
import '../engine/meld.dart';
import '../multiplayer/table_view.dart';

/// Where a move puts things.
enum MoveTarget {
  /// Take the top of the stock.
  stock,

  /// Take from the discard pile.
  pile,

  /// Throw a card on the discard pile, ending your turn.
  discard,

  /// Extend one of your side's existing melds.
  meld,

  /// Lay a brand-new meld.
  newMeld,

  /// Finish the round.
  goOut,

  /// Nobody can draw; end the round where it stands.
  endRound,
}

class MoveOption {
  final int actionId;
  final GameAction action;
  final MoveTarget target;

  /// Hand cards this move spends.
  final List<CardId> consumes;

  /// For [MoveTarget.meld], the index into your side's melds.
  final int? meldSlot;

  /// The wording of the move, without any card names in it.
  final String prefix;

  /// Cards to name after [prefix]. Kept as ids rather than formatted text
  /// because suit symbols have to be painted, not typed — see `card_label.dart`.
  final List<CardId> nameCards;

  const MoveOption({
    required this.actionId,
    required this.action,
    required this.target,
    required this.consumes,
    required this.prefix,
    this.nameCards = const [],
    this.meldSlot,
  });

  /// Plain-text form, for semantics and debugging.
  String get label =>
      nameCards.isEmpty ? prefix : '$prefix${nameCards.map(cardStr).join(' ')}';
}

class MoveIndex {
  final List<MoveOption> options;

  const MoveIndex(this.options);

  static const MoveIndex empty = MoveIndex([]);

  bool get isEmpty => options.isEmpty;

  /// Every move that spends [card].
  List<MoveOption> forCard(CardId card) => [
    for (final o in options)
      if (o.consumes.contains(card)) o,
  ];

  /// Cards in hand that have at least one move available.
  Set<CardId> get playableCards => {for (final o in options) ...o.consumes};

  List<MoveOption> withTarget(MoveTarget target) => [
    for (final o in options)
      if (o.target == target) o,
  ];

  MoveOption? firstWithTarget(MoveTarget target) {
    for (final o in options) {
      if (o.target == target) return o;
    }
    return null;
  }

  /// Build the index for the moves [view] currently offers.
  factory MoveIndex.build(RulesConfig cfg, TableView view) {
    if (view.legalActions.isEmpty) return MoveIndex.empty;

    final hand = <CardId, int>{};
    for (final ct in view.hand) {
      hand[ct] = (hand[ct] ?? 0) + 1;
    }
    final myMelds = view.myMelds;
    final slots = cfg.meld.maxMeldSlots;

    final options = <MoveOption>[];
    for (final id in view.legalActions) {
      final action = decodeAction(id, slots);
      switch (action) {
        case DrawDeck():
          options.add(
            MoveOption(
              actionId: id,
              action: action,
              target: MoveTarget.stock,
              consumes: const [],
              prefix: 'Draw from the stock',
            ),
          );

        case DrawTrash():
          options.add(
            MoveOption(
              actionId: id,
              action: action,
              target: MoveTarget.pile,
              consumes: const [],
              prefix: view.trash.length > 1
                  ? 'Take all ${view.trash.length} cards'
                  : 'Take the top card',
            ),
          );

        case Discard(:final ct):
          options.add(
            MoveOption(
              actionId: id,
              action: action,
              target: MoveTarget.discard,
              consumes: [ct],
              prefix: 'Discard ',
              nameCards: [ct],
            ),
          );

        case AddToMeld(:final slot, :final ct):
          options.add(
            MoveOption(
              actionId: id,
              action: action,
              target: MoveTarget.meld,
              meldSlot: slot,
              consumes: [ct],
              prefix: slot < myMelds.length
                  ? 'Add to ${meldLabel(myMelds[slot])}'
                  : 'Add to a meld',
            ),
          );

        case CreateSeq(:final suit, :final start, :final wild):
          final plan = planSequence(cfg, hand, suit, start, wild);
          if (plan == null) continue;
          options.add(
            MoveOption(
              actionId: id,
              action: action,
              target: MoveTarget.newMeld,
              consumes: plan.consumed,
              prefix: 'New run  ',
              nameCards: [for (final s in plan.slots) s.$1],
            ),
          );

        case CreateSet(:final rank, :final wild):
          final plan = planSet(cfg, hand, rank, wild);
          if (plan == null) continue;
          options.add(
            MoveOption(
              actionId: id,
              action: action,
              target: MoveTarget.newMeld,
              consumes: plan.consumed,
              prefix: 'New set  ',
              nameCards: [for (final s in plan.slots) s.$1],
            ),
          );

        case GoOut():
          options.add(
            MoveOption(
              actionId: id,
              action: action,
              target: MoveTarget.goOut,
              consumes: const [],
              prefix: 'Go out',
            ),
          );

        case EndRound():
          options.add(
            MoveOption(
              actionId: id,
              action: action,
              target: MoveTarget.endRound,
              consumes: const [],
              prefix: 'End the round',
            ),
          );
      }
    }
    return MoveIndex(options);
  }
}

/// Short name for a meld. Deliberately free of suit symbols: the pip beside it
/// is painted, and a heart in a string renders as a blank box.
String meldLabel(MeldView meld) {
  if (meld.isSequence) {
    final low = kRankNames[rankAt(meld.startPos!)];
    final high = kRankNames[rankAt(meld.startPos! + meld.size - 1)];
    return low == high ? low : '$low–$high';
  }
  return '${meld.size}x ${kRankNames[meld.rank!]}';
}
