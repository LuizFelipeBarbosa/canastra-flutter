/// The four shipped rule profiles.
///
/// Each returns a fully-populated [RulesConfig]; everything the engine does is
/// driven by that tree, so a new variant is a new function here rather than a
/// new code path.
library;

import 'config.dart';

/// Buraco — the house rules.
///
/// Open trash taken whole, 2s wild (no printed jokers), sequences and sets,
/// a morto per side, any canastra (7+) unlocks going out, batida seca allowed,
/// standard Brazilian scoring to 3000.
RulesConfig buraco({int numPlayers = 2}) {
  final TableConfig table;
  if (numPlayers == 2) {
    table = TableConfig(numPlayers: 2, mode: modeIndividual, teamOf: 1);
  } else if (numPlayers == 4) {
    table = TableConfig(numPlayers: 4, mode: modeTeams, teamOf: 2);
  } else {
    throw ArgumentError('buraco supports 2 or 4 players, got $numPlayers');
  }
  return RulesConfig(
    name: 'buraco',
    table: table,
    goingOut: const GoingOutConfig(discardToGoOut: discardOutOptional),
  );
}

const Map<String, int> canastaCardPoints = {
  'A': 20, '2': 20, '3': 5, '4': 5, '5': 5, '6': 5, '7': 5,
  '8': 10, '9': 10, '10': 10, 'J': 10, 'Q': 10, 'K': 10, 'JOKER': 50,
};

const List<(int, int)> canastaThresholds = [
  (-1000000000, 15),
  (0, 50),
  (1500, 90),
  (3000, 120),
];

/// Classic (US) Canasta: sets only, a conditional/frozen discard pile with a
/// forced top-card meld, red-3 bonus trays, black-3 pile blocking, initial-meld
/// thresholds, canastas 500/300, match to 5000.
RulesConfig canasta({int numPlayers = 4}) {
  final TableConfig table;
  final int drawCount;
  final int minCanastras;
  if (numPlayers == 4) {
    table = TableConfig(
        numPlayers: 4, mode: modeTeams, teamOf: 2, cardsPerPlayer: 11);
    drawCount = 1;
    minCanastras = 1;
  } else if (numPlayers == 2) {
    table = TableConfig(
        numPlayers: 2, mode: modeIndividual, teamOf: 1, cardsPerPlayer: 15);
    drawCount = 2;
    minCanastras = 2;
  } else {
    throw ArgumentError('canasta supports 2 or 4 players, got $numPlayers');
  }
  return RulesConfig(
    name: 'canasta',
    table: table,
    deck: const DeckConfig(deckCount: 2, printedJokers: 4),
    wildcard: const WildcardConfig(
      naturalTwoInSuit: false, // sets only; a 2 is always wild
      wildcardLimitPerMeld: 3,
      minNaturalsPerMeld: 2,
    ),
    meld: const MeldConfig(
      allowSequences: false,
      canastraBonusClean: 500,
      canastraBonusDirty: 300,
    ),
    morto: const MortoConfig(count: 0),
    discardPile: const DiscardPileConfig(
      drawRule: drawConditionalMeldTop,
      initialUpcard: true,
      freezeEnabled: true,
      frozenNeedsTwoNaturals: true,
    ),
    goingOut: GoingOutConfig(
      requireCanastra: true,
      requireMortoTaken: false,
      discardToGoOut: discardOutOptional,
      goOutBonus: 100,
      concealedBonus: 100,
      goOutMinCanastras: minCanastras,
    ),
    initialMeld:
        const InitialMeldConfig(enabled: true, thresholds: canastaThresholds),
    specialThrees: const SpecialThreesConfig(
      redThreeMode: red3BonusAutoreplace,
      redThreeBonus: 100,
      redThreeAllBonus: 400,
      redThreeNegativeIfNoMeld: true,
      blackThreeBlocksPile: true,
      blackThreeMeldOnlyGoingOut: true,
    ),
    scoring:
        const ScoringConfig(cardPoints: canastaCardPoints, matchTarget: 5000),
    turn: TurnConfig(drawCount: drawCount),
  );
}

const Map<String, int> rummyCardPoints = {
  'A': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7,
  '8': 8, '9': 9, '10': 10, 'J': 10, 'Q': 10, 'K': 10, 'JOKER': 0,
};

/// Basic Rummy: a single 52-card deck, no wildcards, top-card draw, no morto,
/// no canastra requirement, and the winner collects the opponent's pips.
RulesConfig rummy({int numPlayers = 2}) {
  if (numPlayers != 2) {
    throw ArgumentError('rummy is 2-player only, got $numPlayers');
  }
  return RulesConfig(
    name: 'rummy',
    table: TableConfig(
        numPlayers: 2, mode: modeIndividual, teamOf: 1, cardsPerPlayer: 10),
    deck: const DeckConfig(deckCount: 1, printedJokers: 0),
    wildcard: const WildcardConfig(
      wildRanks: {},
      jokersWild: false,
      naturalTwoInSuit: false,
      wildcardLimitPerMeld: 0,
      minNaturalsPerMeld: 3,
    ),
    meld: const MeldConfig(
      acePolicy: aceLowOnly,
      canastraBonusClean: 0,
      canastraBonusDirty: 0,
    ),
    morto: const MortoConfig(count: 0),
    discardPile: const DiscardPileConfig(
      drawRule: drawTopCard,
      initialUpcard: true,
      noImmediateRedrawDiscard: true,
    ),
    goingOut: const GoingOutConfig(
      requireCanastra: false,
      requireMortoTaken: false,
      discardToGoOut: discardOutOptional,
      goOutBonus: 0,
    ),
    scoring: const ScoringConfig(
      cardPoints: rummyCardPoints,
      handPenaltyMode: handPenaltyOpponentPositive,
      matchTarget: 100,
    ),
  );
}

/// Greek Biriba: two decks plus four jokers, biribakia (dead hands) that
/// convert into fresh stock on exhaustion, biriba = a 7+ meld.
RulesConfig biriba({int numPlayers = 4}) {
  final TableConfig table;
  if (numPlayers == 2) {
    table = TableConfig(numPlayers: 2, mode: modeIndividual, teamOf: 1);
  } else if (numPlayers == 4) {
    table = TableConfig(numPlayers: 4, mode: modeTeams, teamOf: 2);
  } else {
    throw ArgumentError('biriba supports 2 or 4 players, got $numPlayers');
  }
  return RulesConfig(
    name: 'biriba',
    table: table,
    deck: const DeckConfig(deckCount: 2, printedJokers: 4),
    discardPile: const DiscardPileConfig(
      initialUpcard: true,
      noImmediateRedrawDiscard: true,
    ),
    scoring:
        const ScoringConfig(cardPoints: buracoCardPoints, matchTarget: 5000),
    turn: const TurnConfig(deckExhaustionPolicy: exhaustionConvertMorto),
  );
}

/// A profile the player can pick on the setup screen.
class GameProfile {
  final String id;
  final String label;
  final String tagline;
  final String blurb;
  final List<int> playerCounts;
  final RulesConfig Function({int numPlayers}) build;

  const GameProfile({
    required this.id,
    required this.label,
    required this.tagline,
    required this.blurb,
    required this.playerCounts,
    required this.build,
  });
}

const List<GameProfile> kProfiles = [
  GameProfile(
    id: 'buraco',
    label: 'Buraco',
    tagline: 'Brazilian house rules',
    blurb: 'Sequences and sets, twos are wild, take the whole discard pile, '
        'and pick up your morto before you can go out.',
    playerCounts: [2, 4],
    build: buraco,
  ),
  GameProfile(
    id: 'canasta',
    label: 'Canasta',
    tagline: 'Classic American',
    blurb: 'Sets only, jokers and twos wild, a pile that freezes, red threes '
        'for bonus, and a minimum meld that grows with your score.',
    playerCounts: [2, 4],
    build: canasta,
  ),
  GameProfile(
    id: 'biriba',
    label: 'Biriba',
    tagline: 'Greek cousin',
    blurb: 'Buraco scoring with jokers in the deck, and a dead hand that turns '
        'into a fresh stock when the deck runs out.',
    playerCounts: [2, 4],
    build: biriba,
  ),
  GameProfile(
    id: 'rummy',
    label: 'Rummy',
    tagline: 'Quick and simple',
    blurb: 'One deck, no wilds, draw a single card, and go out fast — the '
        'winner scores whatever is left in the loser\'s hand.',
    playerCounts: [2],
    build: rummy,
  ),
];

GameProfile profileById(String id) =>
    kProfiles.firstWhere((p) => p.id == id, orElse: () => kProfiles.first);

/// Load a rules config by profile id.
RulesConfig loadProfile(String id, {int? numPlayers}) {
  final profile = profileById(id);
  return profile.build(numPlayers: numPlayers ?? profile.playerCounts.first);
}
