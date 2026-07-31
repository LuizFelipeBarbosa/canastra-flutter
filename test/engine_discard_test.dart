/// Tests for the sole-pile buy-and-rediscard ban.
///
/// Buying a single-card discard pile and throwing that same card straight back
/// is a stalling no-op, so `soleBuyRediscardBan` makes it illegal for the rest
/// of the turn — with a valve that keeps the discard legal when the bought type
/// is the only type left in hand.
library;

import 'package:canastra/engine/action.dart';
import 'package:canastra/engine/cards.dart';
import 'package:canastra/engine/config.dart';
import 'package:canastra/engine/legal.dart';
import 'package:canastra/engine/profiles.dart';
import 'package:canastra/engine/state.dart';
import 'package:canastra/engine/turns.dart';
import 'package:flutter_test/flutter_test.dart';

const fiveClubs = 4;
const sixClubs = 5;
const kingHearts = 38;
const kingSpades = 51;

/// A dealt round rigged so seat 0 is about to draw with [hand] against [trash].
RoundState _pileState(
  RulesConfig cfg, {
  required List<CardId> hand,
  required List<CardId> trash,
}) {
  final state = dealRoundFromStock(
    cfg,
    buildDeck(cfg.deck.deckCount, cfg.deck.printedJokers),
  );
  state.hands[0].clear();
  for (final ct in hand) {
    state.hands[0][ct] = (state.hands[0][ct] ?? 0) + 1;
  }
  state.trash
    ..clear()
    ..addAll(trash);
  state
    ..currentPlayer = 0
    ..phase = Phase.draw;
  return state;
}

void main() {
  final cfg = loadProfile('buraco', numPlayers: 2);

  test('buying a sole pile card bans its discard and no other', () {
    final state = _pileState(
      cfg,
      hand: [fiveClubs, sixClubs],
      trash: [kingHearts],
    );
    applyAction(state, const DrawTrash());

    expect(state.boughtSolePileCard, equals(kingHearts));
    final discards = {
      for (final a in legalActions(state).whereType<Discard>()) a.ct,
    };
    expect(discards, isNot(contains(kingHearts)));
    expect(discards, containsAll([fiveClubs, sixClubs]));
  });

  test('the restriction lifts when the turn ends', () {
    final state = _pileState(
      cfg,
      hand: [fiveClubs, sixClubs],
      trash: [kingHearts],
    );
    applyAction(state, const DrawTrash());
    applyAction(state, const Discard(ct: fiveClubs));

    expect(state.boughtSolePileCard, isNull);
    state
      ..currentPlayer = 0
      ..phase = Phase.play;
    expect(discardAllowed(state, kingHearts), isTrue);
  });

  test('buying a pile of two or more sets no restriction', () {
    final state = _pileState(
      cfg,
      hand: [fiveClubs, sixClubs],
      trash: [kingSpades, kingHearts],
    );
    applyAction(state, const DrawTrash());

    expect(state.boughtSolePileCard, isNull);
    expect(discardAllowed(state, kingHearts), isTrue);
  });

  test('the twin copy of the bought card is banned too', () {
    final state = _pileState(
      cfg,
      hand: [kingHearts, fiveClubs],
      trash: [kingHearts],
    );
    applyAction(state, const DrawTrash());

    expect(state.hands[0][kingHearts], equals(2));
    expect(discardAllowed(state, kingHearts), isFalse);
  });

  test('the bought type stays discardable when it is the only type left', () {
    final state = _pileState(cfg, hand: [kingHearts], trash: [kingHearts]);
    applyAction(state, const DrawTrash());

    expect(state.hands[0].keys, equals([kingHearts]));
    expect(discardAllowed(state, kingHearts), isTrue);
  });

  test('with the flag off the rediscard stays legal', () {
    final off = cfg.withDiscardPile(
      cfg.discardPile.copyWith(soleBuyRediscardBan: false),
    );
    final state = _pileState(
      off,
      hand: [fiveClubs, sixClubs],
      trash: [kingHearts],
    );
    applyAction(state, const DrawTrash());

    expect(state.boughtSolePileCard, isNull);
    expect(discardAllowed(state, kingHearts), isTrue);
  });
}
