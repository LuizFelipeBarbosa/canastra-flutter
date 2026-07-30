/// Tests for the one piece of rules-adjacent code that lives outside the engine.
///
/// The table lets you pick up any number of cards and drop them somewhere; the
/// engine only creates melds at the minimum size and extends them one card at a
/// time. `selection_plan.dart` bridges that, and the thing worth testing is that
/// it produces a *sequence the engine will actually accept*, in an order that
/// works — so every plan here is replayed through the real host, and the assertion
/// is that the host took every step.
library;

import 'package:canastra/engine/action.dart';
import 'package:canastra/engine/cards.dart';
import 'package:canastra/engine/match.dart';
import 'package:canastra/engine/profiles.dart';
import 'package:canastra/engine/state.dart';
import 'package:canastra/game/selection_plan.dart';
import 'package:canastra/multiplayer/table_view.dart';
import 'package:flutter_test/flutter_test.dart';

// Suit-major card ids, spelled out so the tests read like a hand of cards.
const aceClubs = 0;
const twoClubs = 1;
const fiveClubs = 4;
const sixClubs = 5;
const sevenClubs = 6;
const eightClubs = 7;
const nineClubs = 8;
const kingClubs = 12;
const tenClubs = 9;
const jackClubs = 10;
const twoDiamonds = 14;
const kingDiamonds = 25;
const kingHearts = 38;
const aceSpades = 39;
const kingSpades = 51;

/// Two cards that make no meld together, held so a play never empties the hand.
///
/// Emptying it is a different rule with its own tests: the engine hands you your
/// morto the moment your last card goes down, which would quietly change the state
/// every other test is standing on.
const ballast = [aceSpades, kingSpades];

/// A match sitting in the play phase with exactly [hand] in seat 0.
///
/// The deal is thrown away rather than searched: the point of each test is one
/// specific handful, and hunting for it in a shuffle would make the test depend on
/// the shuffle.
Match _tableWith(List<CardId> hand, {String profile = 'buraco'}) {
  final match = Match(cfg: loadProfile(profile, numPlayers: 2), seed: 3);
  _setHand(match, hand);
  match.round.currentPlayer = 0;
  match.round.phase = Phase.play;
  return match;
}

void _setHand(Match match, List<CardId> hand) {
  final held = match.round.hands[0];
  held.clear();
  for (final ct in [...hand, ...ballast]) {
    held[ct] = (held[ct] ?? 0) + 1;
  }
}

TableView _viewOf(Match match) =>
    buildTableView(match, 0, playerNames: const ['You', 'Bruno']);

/// Submit every step to the host, in order. Throws if the host refuses one.
void _replay(Match match, SelectionPlan plan) {
  for (final step in plan.steps) {
    expect(
      match.legalActionIdsNow(),
      contains(step),
      reason: 'the host was not offering step ${plan.steps.indexOf(step)}',
    );
    match.applyId(step);
  }
}

SelectionPlan _expectReady(PlanResult result) {
  expect(result, isA<PlanReady>(), reason: 'expected a playable plan');
  return (result as PlanReady).plan;
}

void _expectRefused(PlanResult result, Refusal reason) {
  expect(result, isA<PlanRefused>());
  expect((result as PlanRefused).reason, equals(reason));
}

void main() {
  group('laying a new meld down', () {
    test('three naturals in a suit are one action', () {
      final match = _tableWith([fiveClubs, sixClubs, sevenClubs]);
      final plan = _expectReady(
        planNewMeld(match.cfg, _viewOf(match), [
          fiveClubs,
          sixClubs,
          sevenClubs,
        ]),
      );

      expect(plan.steps, hasLength(1));
      expect(
        decodeAction(plan.steps.single, match.cfg.meld.maxMeldSlots),
        isA<CreateSeq>(),
      );
      _replay(match, plan);
      expect(match.round.melds.single.size, equals(3));
    });

    test('a five-card run is a create and two adds, low card first', () {
      final hand = [fiveClubs, sixClubs, sevenClubs, eightClubs, nineClubs];
      final match = _tableWith(hand);
      final plan = _expectReady(planNewMeld(match.cfg, _viewOf(match), hand));

      expect(plan.steps, hasLength(3));
      final adds = [
        for (final step in plan.steps.skip(1))
          decodeAction(step, match.cfg.meld.maxMeldSlots) as AddToMeld,
      ];
      // The 9 cannot join 5-6-7 until the 8 has, so the order is not incidental.
      expect(adds.map((a) => a.ct), equals([eightClubs, nineClubs]));
      expect(adds.every((a) => a.slot == 0), isTrue);

      _replay(match, plan);
      final meld = match.round.melds.single;
      expect(meld.size, equals(5));
      expect(meld.isClean, isTrue);
    });

    test('three of a rank is a set', () {
      final hand = [kingClubs, kingDiamonds, kingHearts];
      final match = _tableWith(hand);
      final plan = _expectReady(planNewMeld(match.cfg, _viewOf(match), hand));

      expect(
        decodeAction(plan.steps.first, match.cfg.meld.maxMeldSlots),
        isA<CreateSet>(),
      );
      _replay(match, plan);
      expect(match.round.melds.single.rank, equals(Rank.king));
    });

    test('a run is preferred without a wild when it can be', () {
      // A-2-3 of clubs plus a spare two: the 2♣ is natural in its own position,
      // so the run should be laid down clean rather than spending a wild.
      final hand = [aceClubs, twoClubs, 2 /* 3♣ */];
      final match = _tableWith(hand);
      final plan = _expectReady(planNewMeld(match.cfg, _viewOf(match), hand));
      _replay(match, plan);
      expect(match.round.melds.single.isClean, isTrue);
    });

    test('a wild fills a gap when there is no clean run', () {
      // 5♣ 7♣ with a two standing in for the 6.
      final hand = [fiveClubs, sevenClubs, twoDiamonds];
      final match = _tableWith(hand);
      final plan = _expectReady(planNewMeld(match.cfg, _viewOf(match), hand));
      _replay(match, plan);
      final meld = match.round.melds.single;
      expect(meld.size, equals(3));
      expect(meld.isClean, isFalse);
    });

    test('a natural two and an off-suit wild are not over-counted', () {
      // The context-free wildcard table calls both twos wild. The meld planner
      // knows that 2♣ is natural in the A-2-3♣ run and only 2♦ stands in.
      final hand = [aceClubs, twoClubs, twoDiamonds];
      final match = _tableWith(hand);
      final plan = _expectReady(planNewMeld(match.cfg, _viewOf(match), hand));

      expect(match.legalActionIdsNow(), contains(plan.steps.first));
      _replay(match, plan);
      final meld = match.round.melds.single;
      expect(meld.size, equals(3));
      expect(meld.isClean, isFalse);
    });

    test('a natural rummy run plans and replays without wilds', () {
      final hand = [fiveClubs, sixClubs, sevenClubs];
      final match = _tableWith(hand, profile: 'rummy');
      final plan = _expectReady(planNewMeld(match.cfg, _viewOf(match), hand));

      _replay(match, plan);
      expect(match.round.melds.single.size, equals(3));
      expect(match.round.melds.single.isClean, isTrue);
    });

    test('a biriba run with a wild plans and replays', () {
      final hand = [fiveClubs, sevenClubs, twoDiamonds];
      final match = _tableWith(hand, profile: 'biriba');
      final plan = _expectReady(planNewMeld(match.cfg, _viewOf(match), hand));

      _replay(match, plan);
      expect(match.round.melds.single.size, equals(3));
      expect(match.round.melds.single.isClean, isFalse);
    });
  });

  group('refusals name the actual problem', () {
    test('two cards is too short', () {
      final match = _tableWith([fiveClubs, sixClubs]);
      _expectRefused(
        planNewMeld(match.cfg, _viewOf(match), [fiveClubs, sixClubs]),
        Refusal.tooShort,
      );
    });

    test('one natural and two wilds is too few real cards', () {
      final hand = [sevenClubs, twoClubs, twoDiamonds];
      final match = _tableWith(hand);
      // Buraco allows one wild per meld, so this trips the wild limit first.
      _expectRefused(
        planNewMeld(match.cfg, _viewOf(match), hand),
        Refusal.tooManyWilds,
      );
    });

    test('cards from different suits and ranks are not a meld', () {
      final hand = [fiveClubs, sixClubs, kingDiamonds];
      final match = _tableWith(hand);
      _expectRefused(
        planNewMeld(match.cfg, _viewOf(match), hand),
        Refusal.notAMeld,
      );
    });
  });

  group('extending a meld already on the table', () {
    /// Lay 5-6-7♣ down, then hand seat 0 whatever the test needs next.
    Match withRunDown(List<CardId> thenHold) {
      final match = _tableWith([fiveClubs, sixClubs, sevenClubs]);
      final plan = _expectReady(
        planNewMeld(match.cfg, _viewOf(match), [
          fiveClubs,
          sixClubs,
          sevenClubs,
        ]),
      );
      _replay(match, plan);
      _setHand(match, thenHold);
      return match;
    }

    test('two cards extend the open end in the order that works', () {
      final match = withRunDown([eightClubs, nineClubs]);
      final plan = _expectReady(
        planExtendMeld(match.cfg, _viewOf(match), 0, [nineClubs, eightClubs]),
      );

      final adds = [
        for (final step in plan.steps)
          (decodeAction(step, match.cfg.meld.maxMeldSlots) as AddToMeld).ct,
      ];
      // Picked up 9 first, but the 8 still has to go down first.
      expect(adds, equals([eightClubs, nineClubs]));
      _replay(match, plan);
      expect(match.round.melds.single.size, equals(5));
    });

    test('a card that does not reach the meld is refused', () {
      final match = withRunDown([kingHearts]);
      _expectRefused(
        planExtendMeld(match.cfg, _viewOf(match), 0, [kingHearts]),
        Refusal.doesNotFit,
      );
    });

    test('a partly-fitting handful is refused whole', () {
      // The 8 fits; the king does not. Neither is played — the table should not
      // half-do what was asked.
      final match = withRunDown([eightClubs, kingHearts]);
      _expectRefused(
        planExtendMeld(match.cfg, _viewOf(match), 0, [eightClubs, kingHearts]),
        Refusal.doesNotFit,
      );
      expect(match.round.melds.single.size, equals(3));
    });

    test('a run grows to a canastra in one gesture', () {
      final run = [eightClubs, nineClubs, tenClubs, jackClubs];
      final match = withRunDown(run);
      final plan = _expectReady(
        planExtendMeld(match.cfg, _viewOf(match), 0, run),
      );
      expect(plan.steps, hasLength(4));
      _replay(match, plan);
      final meld = match.round.melds.single;
      expect(meld.size, equals(7));
      expect(meld.isCanastra(match.cfg.meld.canastraMinSize), isTrue);
    });

    test('a play that would strand the hand is refused, and says why', () {
      // Morto already taken, no canastra down, and the whole hand would go: the
      // engine forbids this, so the table must not offer it.
      final match = withRunDown([eightClubs, nineClubs]);
      final state = match.round;
      state.hands[0].clear();
      for (final ct in [eightClubs, nineClubs]) {
        state.hands[0][ct] = 1;
      }
      state.mortoTaken[0] = true;
      state.morto[0] = null;

      final view = _viewOf(match);
      _expectRefused(
        planExtendMeld(match.cfg, view, 0, [eightClubs, nineClubs]),
        Refusal.needCanastra,
      );
      // Nor one of the two on its own: going down to a single card would force a
      // last discard, and that is going out, which this side may not do yet.
      _expectRefused(
        planExtendMeld(match.cfg, view, 0, [eightClubs]),
        Refusal.needCanastra,
      );
      // The engine agrees — it is offering no add at all.
      expect(
        match.legalActionsNow().whereType<AddToMeld>(),
        isEmpty,
        reason: 'the plan and the host must refuse the same things',
      );
      expect(match.round.melds.single.size, equals(3));
    });

    test('the morto still coming lets the hand empty', () {
      // Same shape, but the morto is untaken: it will refill the hand, so the
      // engine allows the play and so must the plan.
      final match = withRunDown([eightClubs, nineClubs]);
      final state = match.round;
      state.hands[0].clear();
      for (final ct in [eightClubs, nineClubs]) {
        state.hands[0][ct] = 1;
      }
      state.mortoTaken[0] = false;

      final plan = _expectReady(
        planExtendMeld(match.cfg, _viewOf(match), 0, [eightClubs, nineClubs]),
      );
      _replay(match, plan);
      expect(match.round.mortoTaken[0], isTrue, reason: 'the morto arrives');
    });

    test('an exhausted untaken morto still names the morto obligation', () {
      final match = withRunDown([eightClubs, nineClubs]);
      final state = match.round;
      state.hands[0]
        ..clear()
        ..[eightClubs] = 1
        ..[nineClubs] = 1;
      state.mortoTaken[0] = false;
      state.morto[0] = null;

      _expectRefused(
        planExtendMeld(match.cfg, _viewOf(match), 0, [eightClubs, nineClubs]),
        Refusal.mortoFirst,
      );
    });
  });

  group('Canasta pending pile card', () {
    Match withKingsDown(List<CardId> thenHold) {
      final match = _tableWith([
        kingClubs,
        kingDiamonds,
        kingHearts,
      ], profile: 'canasta');
      match.round.initialMeldDone[0] = true;
      final core = [kingClubs, kingDiamonds, kingHearts];
      _replay(
        match,
        _expectReady(planNewMeld(match.cfg, _viewOf(match), core)),
      );
      _setHand(match, thenHold);
      return match;
    }

    test('the pending card is the first add onto an open set', () {
      final match = withKingsDown([kingHearts, kingSpades]);
      // Ballast also uses K♠; keep exactly the selected copy so this tests the
      // physical pending-card obligation rather than an interchangeable spare.
      match.round.hands[0][kingSpades] = 1;
      match.round.hands[0][aceClubs] = 1;
      match.round.pendingPileCard = kingSpades;

      final plan = _expectReady(
        planExtendMeld(match.cfg, _viewOf(match), 0, [kingHearts, kingSpades]),
      );
      final first = decodeAction(plan.steps.first, match.cfg.meld.maxMeldSlots);
      expect(first, isA<AddToMeld>());
      expect((first as AddToMeld).ct, equals(kingSpades));

      _replay(match, plan);
      expect(match.round.pendingPileCard, isNull);
      expect(match.round.melds.single.size, equals(5));
    });

    test('a fresh set consumes the pending physical copy', () {
      final hand = [kingClubs, kingDiamonds, kingHearts, kingSpades];
      final match = _tableWith(hand, profile: 'canasta');
      match.round.initialMeldDone[0] = true;
      // Remove the second K♠ supplied by ballast. If the client simulates the
      // create without `prefer`, its queued K♠ add cannot replay after the host
      // correctly consumes the one pending copy.
      match.round.hands[0][kingSpades] = 1;
      match.round.hands[0][aceClubs] = 1;
      match.round.pendingPileCard = kingSpades;

      final plan = _expectReady(planNewMeld(match.cfg, _viewOf(match), hand));
      expect(plan.steps, hasLength(2));
      _replay(match, plan);
      expect(match.round.pendingPileCard, isNull);
      expect(match.round.melds.single.size, equals(4));
    });
  });

  group('a meld rebuilt from its public view is the same meld', () {
    test('cards, shape and which slots are wild all survive', () {
      final match = _tableWith([fiveClubs, sevenClubs, twoDiamonds]);
      _replay(
        match,
        _expectReady(
          planNewMeld(match.cfg, _viewOf(match), [
            fiveClubs,
            sevenClubs,
            twoDiamonds,
          ]),
        ),
      );

      final original = match.round.melds.single;
      final rebuilt = meldFromView(_viewOf(match).myMelds.single);

      expect(rebuilt.kind, equals(original.kind));
      expect(rebuilt.suit, equals(original.suit));
      expect(rebuilt.startPos, equals(original.startPos));
      expect(rebuilt.wildCount, equals(original.wildCount));
      expect([
        for (final s in rebuilt.slots) s.card,
      ], equals([for (final s in original.slots) s.card]));
    });
  });
}
