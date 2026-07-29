/// The rules-config tree: the single source of rule truth.
///
/// Every class is immutable; a profile constructs one tree and the engine only
/// ever reads it. String-valued policy fields use plain constants rather than
/// enums so configs serialise to JSON verbatim.
library;

import 'cards.dart';

// --- policy constants -------------------------------------------------------

const String modeIndividual = 'INDIVIDUAL';
const String modeTeams = 'TEAMS';

const String aceHighOrLow = 'HIGH_OR_LOW';
const String aceLowOnly = 'LOW_ONLY';
const String aceHighOnly = 'HIGH_ONLY';

const String wildRelocateExtend = 'RELOCATE_EXTEND';
const String wildToHand = 'TO_HAND';

const String visibilityFullOpen = 'FULL_OPEN';
const String visibilityTopOnly = 'TOP_ONLY';

const String drawWholePile = 'WHOLE_PILE_UNCONDITIONAL';
const String drawTopCard = 'TOP_CARD';
const String drawConditionalMeldTop = 'CONDITIONAL_MELD_TOP';

const String discardOutRequired = 'REQUIRED';
const String discardOutOptional = 'OPTIONAL';
const String discardOutForbidden = 'FORBIDDEN';

const String mortoPickupOnEmpty = 'ON_EMPTY_FORCED';

const String handPenaltySelfNegative = 'SELF_NEGATIVE';
const String handPenaltyOpponentPositive = 'OPPONENT_POSITIVE';

const String episodeRound = 'ROUND';
const String episodeMatch = 'MATCH';

const String red3None = 'NONE';
const String red3BonusAutoreplace = 'BONUS_AUTOREPLACE';

const String exhaustionEndRound = 'END_ROUND';
const String exhaustionConvertMorto = 'CONVERT_MORTO';

const Map<String, int> buracoCardPoints = {
  'A': 15, '2': 10, '3': 5, '4': 5, '5': 5, '6': 5, '7': 5,
  '8': 10, '9': 10, '10': 10, 'J': 10, 'Q': 10, 'K': 10, 'JOKER': 20,
};

// --- config tree -------------------------------------------------------------

class TableConfig {
  final int numPlayers;
  final String mode;
  final int teamOf;
  final int cardsPerPlayer;

  TableConfig({
    this.numPlayers = 2,
    this.mode = modeIndividual,
    this.teamOf = 1,
    this.cardsPerPlayer = 11,
  }) {
    if (numPlayers < 2 || numPlayers > 4) {
      throw ArgumentError('unsupported numPlayers: $numPlayers');
    }
    if (numPlayers % teamOf != 0) {
      throw ArgumentError('numPlayers must be divisible by teamOf');
    }
  }

  int get numSides => numPlayers ~/ teamOf;

  /// Side (team in 4p, player in 2p) owning seat [player].
  int side(int player) => player % numSides;
}

class DeckConfig {
  final int deckCount;
  final int printedJokers;

  const DeckConfig({this.deckCount = 2, this.printedJokers = 0});

  int get totalCards => deckCount * 52 + printedJokers;
}

class WildcardConfig {
  final Set<int> wildRanks;
  final bool jokersWild;
  final bool naturalTwoInSuit;
  final int wildcardLimitPerMeld;
  final int minNaturalsPerMeld;
  final String wildRelocation;

  const WildcardConfig({
    this.wildRanks = const {Rank.two},
    this.jokersWild = true,
    this.naturalTwoInSuit = true,
    this.wildcardLimitPerMeld = 1,
    this.minNaturalsPerMeld = 2,
    this.wildRelocation = wildRelocateExtend,
  });
}

class MeldConfig {
  final bool allowSequences;
  final bool allowSets;
  final int minMeldSize;
  final String acePolicy;
  final bool allowWrap;
  final bool uniqueSetRankPerSide;
  final int canastraMinSize;
  final int canastraBonusClean;
  final int canastraBonusDirty;
  final int maxMeldSlots;

  const MeldConfig({
    this.allowSequences = true,
    this.allowSets = true,
    this.minMeldSize = 3,
    this.acePolicy = aceHighOrLow,
    this.allowWrap = false,
    this.uniqueSetRankPerSide = true,
    this.canastraMinSize = 7,
    this.canastraBonusClean = 200,
    this.canastraBonusDirty = 100,
    this.maxMeldSlots = 24,
  });
}

class MortoConfig {
  final int count;
  final int size;
  final String pickup;
  final int untakenPenalty;

  const MortoConfig({
    this.count = 2,
    this.size = 11,
    this.pickup = mortoPickupOnEmpty,
    this.untakenPenalty = 100,
  });
}

class DiscardPileConfig {
  final String visibility;
  final String drawRule;
  final bool initialUpcard;
  final bool freezeEnabled;
  final bool frozenNeedsTwoNaturals;
  final bool noImmediateRedrawDiscard;

  const DiscardPileConfig({
    this.visibility = visibilityFullOpen,
    this.drawRule = drawWholePile,
    this.initialUpcard = false,
    this.freezeEnabled = false,
    this.frozenNeedsTwoNaturals = false,
    this.noImmediateRedrawDiscard = false,
  });
}

class GoingOutConfig {
  final bool requireCanastra;
  final bool requireCleanCanastra;
  final bool requireMortoTaken;
  final String discardToGoOut;
  final int goOutBonus;
  final int concealedBonus;
  final int goOutMinCanastras;

  const GoingOutConfig({
    this.requireCanastra = true,
    this.requireCleanCanastra = false,
    this.requireMortoTaken = true,
    this.discardToGoOut = discardOutRequired,
    this.goOutBonus = 100,
    this.concealedBonus = 0,
    this.goOutMinCanastras = 1,
  });
}

class InitialMeldConfig {
  final bool enabled;

  /// `(scoreFloor, requiredPoints)` pairs; the highest matching floor wins.
  final List<(int, int)> thresholds;

  const InitialMeldConfig({this.enabled = false, this.thresholds = const []});
}

class SpecialThreesConfig {
  final String redThreeMode;
  final int redThreeBonus;
  final int redThreeAllBonus;
  final bool redThreeNegativeIfNoMeld;
  final bool blackThreeBlocksPile;
  final bool blackThreeMeldOnlyGoingOut;

  const SpecialThreesConfig({
    this.redThreeMode = red3None,
    this.redThreeBonus = 0,
    this.redThreeAllBonus = 0,
    this.redThreeNegativeIfNoMeld = false,
    this.blackThreeBlocksPile = false,
    this.blackThreeMeldOnlyGoingOut = false,
  });
}

class ScoringConfig {
  final Map<String, int> cardPoints;
  final String handPenaltyMode;
  final int matchTarget;
  final String episode;

  const ScoringConfig({
    this.cardPoints = buracoCardPoints,
    this.handPenaltyMode = handPenaltySelfNegative,
    this.matchTarget = 3000,
    this.episode = episodeRound,
  });
}

class TurnConfig {
  final int drawCount;
  final String deckExhaustionPolicy;

  const TurnConfig({
    this.drawCount = 1,
    this.deckExhaustionPolicy = exhaustionEndRound,
  });
}

class RulesConfig {
  final String name;
  final TableConfig table;
  final DeckConfig deck;
  final WildcardConfig wildcard;
  final MeldConfig meld;
  final MortoConfig morto;
  final DiscardPileConfig discardPile;
  final GoingOutConfig goingOut;
  final InitialMeldConfig initialMeld;
  final SpecialThreesConfig specialThrees;
  final ScoringConfig scoring;
  final TurnConfig turn;

  RulesConfig({
    this.name = 'buraco',
    TableConfig? table,
    this.deck = const DeckConfig(),
    this.wildcard = const WildcardConfig(),
    this.meld = const MeldConfig(),
    this.morto = const MortoConfig(),
    this.discardPile = const DiscardPileConfig(),
    this.goingOut = const GoingOutConfig(),
    this.initialMeld = const InitialMeldConfig(),
    this.specialThrees = const SpecialThreesConfig(),
    this.scoring = const ScoringConfig(),
    this.turn = const TurnConfig(),
  }) : table = table ?? TableConfig();

  /// Point value of a card type under this profile's scoring table.
  /// Memoised: the tree is immutable, so the table cannot drift.
  late final List<int> _cardValues = List.generate(
    kCardSpace,
    (ct) => scoring.cardPoints[rankName(ct)]!,
  );

  int cardValue(CardId ct) => _cardValues[ct];

  /// Whether `ct` is a wildcard type. Context-free — the natural-2 positional
  /// exception is applied by meld validation, not here.
  late final List<bool> _wildTable = List.generate(
    kCardSpace,
    (ct) => ct == kJoker ? wildcard.jokersWild : wildcard.wildRanks.contains(idRank(ct)),
  );

  bool isWildCard(CardId ct) => _wildTable[ct];
}
