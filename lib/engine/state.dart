/// Game state: hands, melds, stock, trash, mortos, scores and phase.
///
/// [RoundState] is the mutable per-round ground truth; [MatchState] wraps it
/// with cumulative scores and the replay log. Dealing is deterministic given
/// the caller-supplied [Prng].
library;

import 'cards.dart';
import 'config.dart';
import 'meld.dart';
import 'prng.dart';

enum Phase { draw, play, terminal }

enum EndReason { bater, stockExhausted }

class RoundState {
  final RulesConfig cfg;

  /// Per seat, card type -> count.
  final List<Map<CardId, int>> hands;

  /// Draw from the end.
  List<CardId> stock;

  /// The discard pile; the top is the last element.
  final List<CardId> trash;

  /// All sides' melds; filter by [Meld.owner].
  final List<Meld> melds;

  /// Per side; null once taken or converted.
  final List<List<CardId>?> morto;
  final List<bool> mortoTaken;

  // --- Canasta mechanics (inert in Buraco/Rummy/Biriba) ---

  /// Face-up red-three trays, per side.
  final List<List<CardId>> redThrees;

  /// Taken pile top that MUST be melded next.
  CardId? pendingPileCard;

  /// The pile was frozen: the forced meld must be a fresh natural set.
  bool pendingPilePairOnly;

  /// Meld points laid this turn by a not-yet-opened side.
  int stagedPoints;

  /// Per side, the turn number on which the side opened.
  final List<int?> openedOnTurn;

  /// Per side, this round's initial-meld threshold.
  final List<int> initialMeldMin;

  // --- turn machine ---

  int currentPlayer;
  Phase phase;
  int turnNumber;

  /// Top-card draw rules only.
  CardId? justDrawnFromPile;

  /// The lone card just bought as a whole pile, when the profile bans
  /// rediscarding it. Transient: recomputed on replay, never serialized.
  CardId? boughtSolePileCard;

  /// Canasta black-three; always false in Buraco.
  bool pileBlockedForNext;

  /// Canasta frozen pile; always false in Buraco.
  bool frozen;

  final List<bool> initialMeldDone;

  // --- terminal bookkeeping ---

  bool roundOver;
  int? wentOutSide;
  EndReason? endReason;

  RoundState({
    required this.cfg,
    required this.hands,
    required this.stock,
    List<CardId>? trash,
    List<Meld>? melds,
    List<List<CardId>?>? morto,
    List<bool>? mortoTaken,
    List<List<CardId>>? redThrees,
    this.pendingPileCard,
    this.pendingPilePairOnly = false,
    this.stagedPoints = 0,
    List<int?>? openedOnTurn,
    List<int>? initialMeldMin,
    this.currentPlayer = 0,
    this.phase = Phase.draw,
    this.turnNumber = 0,
    this.justDrawnFromPile,
    this.boughtSolePileCard,
    this.pileBlockedForNext = false,
    this.frozen = false,
    List<bool>? initialMeldDone,
    this.roundOver = false,
    this.wentOutSide,
    this.endReason,
  }) : trash = trash ?? [],
       melds = melds ?? [],
       morto = morto ?? [],
       mortoTaken = mortoTaken ?? [],
       redThrees = redThrees ?? [],
       openedOnTurn = openedOnTurn ?? [],
       initialMeldMin = initialMeldMin ?? [],
       initialMeldDone = initialMeldDone ?? [];

  List<Meld> sideMelds(int side) => [
    for (final m in melds)
      if (m.owner == side) m,
  ];

  int handSize(int player) => hands[player].values.fold(0, (a, b) => a + b);

  bool sideHasCanastra(int side, {bool cleanRequired = false}) {
    final minSize = cfg.meld.canastraMinSize;
    return sideMelds(
      side,
    ).any((m) => m.isCanastra(minSize) && (m.isClean || !cleanRequired));
  }

  int sideCanastraCount(int side) {
    final minSize = cfg.meld.canastraMinSize;
    return sideMelds(side).where((m) => m.isCanastra(minSize)).length;
  }
}

class MatchState {
  final RulesConfig cfg;
  final int seed;
  RoundState round;

  /// Cumulative, by side.
  final List<int> scores;
  int roundIndex;

  /// Encoded action ids — an episode is fully determined by
  /// `(cfg, seed, actionLog)`.
  final List<int> actionLog;

  bool matchOver;
  int? winnerSide;

  MatchState({
    required this.cfg,
    required this.seed,
    required this.round,
    List<int>? scores,
    this.roundIndex = 0,
    List<int>? actionLog,
    this.matchOver = false,
    this.winnerSide,
  }) : scores = scores ?? List.filled(cfg.table.numSides, 0),
       actionLog = actionLog ?? [];
}

const List<CardId> kRedThreeIds = [
  Rank.three + 13 * Suit.diamonds,
  Rank.three + 13 * Suit.hearts,
];

bool isRedThree(CardId ct) => kRedThreeIds.contains(ct);

/// Shuffle and deal a fresh round. Deterministic given [rng].
///
/// Deal order is fixed for reproducibility: shuffle; deal hands one card at a
/// time round-robin from the top of the stock starting with [firstPlayer]; then
/// each morto as a block; then the optional upcard. The remainder is the stock.
/// [matchScores] picks each side's initial-meld threshold (Canasta).
RoundState dealRound(
  RulesConfig cfg,
  Prng rng, {
  int firstPlayer = 0,
  List<int>? matchScores,
}) {
  final stock = buildDeck(cfg.deck.deckCount, cfg.deck.printedJokers);
  rng.shuffle(stock);
  return dealRoundFromStock(
    cfg,
    stock,
    firstPlayer: firstPlayer,
    matchScores: matchScores,
  );
}

/// Deal from an already-shuffled [stock], which this function consumes.
///
/// Split out from [dealRound] so a deal can be reproduced from a recorded deck
/// order — used by the parity tests against the reference Python engine, and
/// the seam an authoritative server would deal through.
RoundState dealRoundFromStock(
  RulesConfig cfg,
  List<CardId> stock, {
  int firstPlayer = 0,
  List<int>? matchScores,
}) {
  final table = cfg.table;
  final hands = List.generate(table.numPlayers, (_) => <CardId, int>{});
  for (var i = 0; i < table.cardsPerPlayer; i++) {
    for (var offset = 0; offset < table.numPlayers; offset++) {
      final player = (firstPlayer + offset) % table.numPlayers;
      final ct = stock.removeLast();
      hands[player][ct] = (hands[player][ct] ?? 0) + 1;
    }
  }

  final numSides = table.numSides;
  if (cfg.morto.count != 0 && cfg.morto.count != numSides) {
    throw ArgumentError(
      'morto.count=${cfg.morto.count} must be 0 or match numSides=$numSides',
    );
  }
  final morto = <List<CardId>?>[
    for (var i = 0; i < cfg.morto.count; i++)
      [for (var j = 0; j < cfg.morto.size; j++) stock.removeLast()],
  ];

  final trash = <CardId>[];
  var frozen = false;
  if (cfg.discardPile.initialUpcard) {
    final upcard = stock.removeLast();
    trash.add(upcard);
    if (cfg.discardPile.freezeEnabled &&
        (cfg.isWildCard(upcard) || isRedThree(upcard))) {
      frozen = true;
    }
  }

  final scores = matchScores ?? List.filled(numSides, 0);
  final initialMeldMin = [
    for (var s = 0; s < numSides; s++)
      cfg.initialMeld.thresholds
          .where((t) => scores[s] >= t.$1)
          .fold(0, (best, t) => t.$2 > best ? t.$2 : best),
  ];

  final state = RoundState(
    cfg: cfg,
    hands: hands,
    stock: stock,
    trash: trash,
    morto: morto,
    mortoTaken: List.filled(morto.length, false),
    currentPlayer: firstPlayer,
    frozen: frozen,
    initialMeldDone: List.filled(numSides, !cfg.initialMeld.enabled),
    redThrees: List.generate(numSides, (_) => <CardId>[]),
    openedOnTurn: List.filled(numSides, null),
    initialMeldMin: initialMeldMin,
  );

  if (cfg.specialThrees.redThreeMode == red3BonusAutoreplace) {
    for (var player = 0; player < table.numPlayers; player++) {
      resolveRedThrees(state, player);
    }
  }
  return state;
}

/// Move red 3s from [player]'s hand to the side tray, drawing replacements from
/// the stock. No-op outside Canasta mode.
///
/// Returns true when a red 3 could not be replaced because the stock was empty
/// — a red 3 drawn as the last stock card ends the round immediately, and the
/// caller must finish it.
bool resolveRedThrees(RoundState state, int player, {bool replace = true}) {
  if (state.cfg.specialThrees.redThreeMode != red3BonusAutoreplace) {
    return false;
  }
  final side = state.cfg.table.side(player);
  final hand = state.hands[player];
  var unreplaced = false;
  while (true) {
    final red = kRedThreeIds.where((ct) => (hand[ct] ?? 0) > 0).firstOrNull;
    if (red == null) return unreplaced;
    if (hand[red] == 1) {
      hand.remove(red);
    } else {
      hand[red] = hand[red]! - 1;
    }
    state.redThrees[side].add(red);
    if (replace) {
      if (state.stock.isNotEmpty) {
        final ct = state.stock.removeLast();
        hand[ct] = (hand[ct] ?? 0) + 1;
      } else {
        unreplaced = true;
      }
    }
  }
}

/// Full card multiset across all zones — the conservation invariant. Constant
/// for the lifetime of a round.
Map<CardId, int> dealtMultiset(RoundState state) {
  final total = <CardId, int>{};
  void add(CardId ct, [int n = 1]) => total[ct] = (total[ct] ?? 0) + n;

  for (final hand in state.hands) {
    hand.forEach(add);
  }
  for (final meld in state.melds) {
    meld.cardMultiset().forEach(add);
  }
  for (final ct in state.stock) {
    add(ct);
  }
  for (final ct in state.trash) {
    add(ct);
  }
  for (final packet in state.morto) {
    if (packet == null) continue;
    for (final ct in packet) {
      add(ct);
    }
  }
  for (final tray in state.redThrees) {
    for (final ct in tray) {
      add(ct);
    }
  }
  return total;
}
