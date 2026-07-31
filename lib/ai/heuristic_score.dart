import '../engine/action.dart';
import '../engine/cards.dart';
import '../engine/config.dart';
import '../multiplayer/table_view.dart';

double baseActionScore(
  RulesConfig cfg,
  TableView view,
  Map<CardId, int> hand,
  GameAction action,
) {
  switch (action) {
    case GoOut():
      return 10000;
    case CreateSeq(:final wild):
      return wild == seqWildNoneValue ? 900 : 500;
    case CreateSet(:final wild):
      return wild == seqWildNoneValue ? 850 : 450;
    case AddToMeld(:final slot, :final ct):
      final myMelds = view.myMelds;
      final target = slot < myMelds.length ? myMelds[slot] : null;
      final completes =
          target != null && target.size == view.canastraMinSize - 1;
      if (cfg.isWildCard(ct)) return 300 + (completes ? 250 : 0);
      return 700 + (completes ? 150 : 0);
    case DrawTrash():
      if (!pileConnects(cfg, view, hand)) return 100;
      // A pile that connects is worth taking, but a huge one floods the hand
      // and pushes going out further away. Without this the policy will take
      // the pile every single turn, the stock never depletes, and two greedy
      // bots pass the same pile back and forth until the round is truncated.
      final flood = (view.trash.length - 10).clamp(0, 40);
      return 600 - 25.0 * flood;
    case DrawDeck():
      return 400;
    case Discard(:final ct):
      return 200 - 10 * usefulness(cfg, ct, hand) - cfg.cardValue(ct) / 20.0;
    case EndRound():
      return 50;
  }
}

/// Does any card in the pile pair with the hand or extend one of my melds?
bool pileConnects(RulesConfig cfg, TableView view, Map<CardId, int> hand) {
  final ranksInHand = {
    for (final c in hand.keys)
      if (c != kJoker) idRank(c),
  };
  for (final card in view.trash) {
    // A free wild is always worth taking.
    if (card == kJoker || cfg.isWildCard(card)) return true;
    if (ranksInHand.contains(idRank(card))) return true;
    for (final meld in view.myMelds) {
      if (meld.isSequence && meld.suit == idSuit(card)) {
        final start = meld.startPos!;
        final end = start + meld.size - 1;
        for (final p in positionsOf(idRank(card)!)) {
          if (p == start - 1 || p == end + 1) return true;
        }
      }
      if (!meld.isSequence && meld.rank == idRank(card)) return true;
    }
  }
  return false;
}

/// How connected a card is to the rest of the hand — higher means keep it.
double usefulness(RulesConfig cfg, CardId ct, Map<CardId, int> hand) {
  // Never throw a wild if there is any alternative.
  if (cfg.isWildCard(ct)) return 12;
  final rank = idRank(ct)!;
  final suit = idSuit(ct)!;

  var sameRank = 0;
  hand.forEach((c, n) {
    if (c != ct && c != kJoker && idRank(c) == rank) sameRank += n;
  });

  var neighbours = 0;
  hand.forEach((other, n) {
    if (other == ct || other == kJoker || idSuit(other) != suit) return;
    var gap = 99;
    for (final p in positionsOf(rank)) {
      for (final q in positionsOf(idRank(other)!)) {
        final d = (p - q).abs();
        if (d < gap) gap = d;
      }
    }
    if (gap >= 1 && gap <= 2) neighbours += n;
  });

  return 2.0 * sameRank + neighbours + ((hand[ct] ?? 0) - 1);
}

/// `seqWildNone` and `setWildNone` are both 0; naming it once keeps the score
/// table readable without importing the meld layer into the AI.
const int seqWildNoneValue = 0;
