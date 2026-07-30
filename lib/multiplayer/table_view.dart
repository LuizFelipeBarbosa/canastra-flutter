/// The redacted, JSON-serialisable view of a table for one seat.
///
/// This is the ONLY shape that crosses the transport. It is built from the
/// authoritative [RoundState] by reading exclusively the zones the seat is
/// allowed to know — its own hand, all melds, the open discard pile, and public
/// sizes and flags. Other players' hand contents, the stock order and the morto
/// contents are unreachable by construction: [buildTableView] never reads those
/// fields beyond their length.
///
/// The UI and the bots both consume only this, so a bot can never peek and a
/// screen can never accidentally render a card the player should not see.
library;

import '../engine/cards.dart';
import '../engine/config.dart';
import '../engine/match.dart';
import '../engine/meld.dart';
import '../engine/scoring.dart';
import '../engine/state.dart';

/// Public summary of one meld. Melds are fully public at a real table, so this
/// carries the actual cards.
class MeldView {
  final int owner;
  final bool isSequence;
  final int? suit;
  final int? rank;
  final int? startPos;
  final List<CardId> cards;

  /// Slot indices holding a card that is acting as a wild.
  final List<int> wildIndices;
  final bool isCanastra;
  final bool isClean;
  final int points;

  const MeldView({
    required this.owner,
    required this.isSequence,
    required this.suit,
    required this.rank,
    required this.startPos,
    required this.cards,
    required this.wildIndices,
    required this.isCanastra,
    required this.isClean,
    required this.points,
  });

  int get size => cards.length;

  Map<String, dynamic> toJson() => {
    'owner': owner,
    'isSequence': isSequence,
    'suit': suit,
    'rank': rank,
    'startPos': startPos,
    'cards': cards,
    'wildIndices': wildIndices,
    'isCanastra': isCanastra,
    'isClean': isClean,
    'points': points,
  };

  factory MeldView.fromJson(Map<String, dynamic> j) => MeldView(
    owner: j['owner'] as int,
    isSequence: j['isSequence'] as bool,
    suit: j['suit'] as int?,
    rank: j['rank'] as int?,
    startPos: j['startPos'] as int?,
    cards: (j['cards'] as List).cast<int>(),
    wildIndices: (j['wildIndices'] as List).cast<int>(),
    isCanastra: j['isCanastra'] as bool,
    isClean: j['isClean'] as bool,
    points: j['points'] as int,
  );
}

/// One side's itemised round score, for the end-of-round sheet.
class ScoreSheetView {
  final int side;
  final List<(String, int)> lines;
  final int total;

  const ScoreSheetView({
    required this.side,
    required this.lines,
    required this.total,
  });

  Map<String, dynamic> toJson() => {
    'side': side,
    'lines': [
      for (final l in lines) {'label': l.$1, 'points': l.$2},
    ],
    'total': total,
  };

  factory ScoreSheetView.fromJson(Map<String, dynamic> j) => ScoreSheetView(
    side: j['side'] as int,
    lines: [
      for (final l in (j['lines'] as List).cast<Map<String, dynamic>>())
        (l['label'] as String, l['points'] as int),
    ],
    total: j['total'] as int,
  );
}

class RoundResultView {
  final int roundIndex;
  final String reason;
  final int? wentOutSide;
  final List<ScoreSheetView> sheets;
  final List<int> matchScores;

  const RoundResultView({
    required this.roundIndex,
    required this.reason,
    required this.wentOutSide,
    required this.sheets,
    required this.matchScores,
  });

  Map<String, dynamic> toJson() => {
    'roundIndex': roundIndex,
    'reason': reason,
    'wentOutSide': wentOutSide,
    'sheets': [for (final s in sheets) s.toJson()],
    'matchScores': matchScores,
  };

  factory RoundResultView.fromJson(Map<String, dynamic> j) => RoundResultView(
    roundIndex: j['roundIndex'] as int,
    reason: j['reason'] as String,
    wentOutSide: j['wentOutSide'] as int?,
    sheets: [
      for (final s in (j['sheets'] as List).cast<Map<String, dynamic>>())
        ScoreSheetView.fromJson(s),
    ],
    matchScores: (j['matchScores'] as List).cast<int>(),
  );
}

class TableView {
  // --- who am I ---
  final int seat;
  final int side;
  final int numPlayers;
  final int numSides;
  final int? partnerSeat;
  final List<String> playerNames;

  // --- the rules in force ---
  final String profile;
  final int matchTarget;
  final int canastraMinSize;

  // --- my private zone ---
  /// Sorted and expanded by count — the only hidden zone this seat may see.
  final List<CardId> hand;

  // --- public zones ---
  final List<int> handSizes;
  final List<MeldView> melds;
  final List<CardId> trash;
  final int stockCount;
  final List<bool> mortoTaken;
  final List<int> mortoSizes;
  final List<List<CardId>> redThrees;

  // --- turn state ---
  final int currentPlayer;
  final String phase;
  final int turnNumber;
  final bool frozen;
  final bool pileBlocked;
  final CardId? pendingPileCard;
  final List<bool> initialMeldDone;
  final List<int> initialMeldMin;
  final int stagedPoints;

  // --- scores ---
  /// Live per-side score from public zones only — never leaks hand values.
  final List<int> publicScores;
  final List<int> matchScores;

  // --- lifecycle ---
  /// Host-owned rematch identity; presentation bookkeeping, not a game rule.
  final int matchNumber;
  final bool roundOver;
  final bool matchOver;
  final int? wentOutSide;
  final int? winnerSide;
  final int roundIndex;
  final RoundResultView? roundResult;

  // --- what I may do ---
  final List<int> legalActions;
  final List<GameEvent> history;

  const TableView({
    required this.seat,
    required this.side,
    required this.numPlayers,
    required this.numSides,
    required this.partnerSeat,
    required this.playerNames,
    required this.profile,
    required this.matchTarget,
    required this.canastraMinSize,
    required this.hand,
    required this.handSizes,
    required this.melds,
    required this.trash,
    required this.stockCount,
    required this.mortoTaken,
    required this.mortoSizes,
    required this.redThrees,
    required this.currentPlayer,
    required this.phase,
    required this.turnNumber,
    required this.frozen,
    required this.pileBlocked,
    required this.pendingPileCard,
    required this.initialMeldDone,
    required this.initialMeldMin,
    required this.stagedPoints,
    required this.publicScores,
    required this.matchScores,
    required this.matchNumber,
    required this.roundOver,
    required this.matchOver,
    required this.wentOutSide,
    required this.winnerSide,
    required this.roundIndex,
    required this.roundResult,
    required this.legalActions,
    required this.history,
  });

  bool get myTurn => currentPlayer == seat && !roundOver && !matchOver;

  List<MeldView> meldsOf(int owner) => [
    for (final m in melds)
      if (m.owner == owner) m,
  ];

  /// My side's melds, in the slot order `AddToMeld.slot` indexes into.
  List<MeldView> get myMelds => meldsOf(side);

  Map<String, dynamic> toJson() => {
    'seat': seat,
    'side': side,
    'numPlayers': numPlayers,
    'numSides': numSides,
    'partnerSeat': partnerSeat,
    'playerNames': playerNames,
    'profile': profile,
    'matchTarget': matchTarget,
    'canastraMinSize': canastraMinSize,
    'hand': hand,
    'handSizes': handSizes,
    'melds': [for (final m in melds) m.toJson()],
    'trash': trash,
    'stockCount': stockCount,
    'mortoTaken': mortoTaken,
    'mortoSizes': mortoSizes,
    'redThrees': redThrees,
    'currentPlayer': currentPlayer,
    'phase': phase,
    'turnNumber': turnNumber,
    'frozen': frozen,
    'pileBlocked': pileBlocked,
    'pendingPileCard': pendingPileCard,
    'initialMeldDone': initialMeldDone,
    'initialMeldMin': initialMeldMin,
    'stagedPoints': stagedPoints,
    'publicScores': publicScores,
    'matchScores': matchScores,
    'matchNumber': matchNumber,
    'roundOver': roundOver,
    'matchOver': matchOver,
    'wentOutSide': wentOutSide,
    'winnerSide': winnerSide,
    'roundIndex': roundIndex,
    'roundResult': roundResult?.toJson(),
    'legalActions': legalActions,
    'history': [for (final h in history) h.toJson()],
  };

  factory TableView.fromJson(Map<String, dynamic> j) => TableView(
    seat: j['seat'] as int,
    side: j['side'] as int,
    numPlayers: j['numPlayers'] as int,
    numSides: j['numSides'] as int,
    partnerSeat: j['partnerSeat'] as int?,
    playerNames: (j['playerNames'] as List).cast<String>(),
    profile: j['profile'] as String,
    matchTarget: j['matchTarget'] as int,
    canastraMinSize: j['canastraMinSize'] as int,
    hand: (j['hand'] as List).cast<int>(),
    handSizes: (j['handSizes'] as List).cast<int>(),
    melds: [
      for (final m in (j['melds'] as List).cast<Map<String, dynamic>>())
        MeldView.fromJson(m),
    ],
    trash: (j['trash'] as List).cast<int>(),
    stockCount: j['stockCount'] as int,
    mortoTaken: (j['mortoTaken'] as List).cast<bool>(),
    mortoSizes: (j['mortoSizes'] as List).cast<int>(),
    redThrees: [
      for (final t in (j['redThrees'] as List)) (t as List).cast<int>(),
    ],
    currentPlayer: j['currentPlayer'] as int,
    phase: j['phase'] as String,
    turnNumber: j['turnNumber'] as int,
    frozen: j['frozen'] as bool,
    pileBlocked: j['pileBlocked'] as bool,
    pendingPileCard: j['pendingPileCard'] as int?,
    initialMeldDone: (j['initialMeldDone'] as List).cast<bool>(),
    initialMeldMin: (j['initialMeldMin'] as List).cast<int>(),
    stagedPoints: j['stagedPoints'] as int,
    publicScores: (j['publicScores'] as List).cast<int>(),
    matchScores: (j['matchScores'] as List).cast<int>(),
    matchNumber: j['matchNumber'] as int? ?? 0,
    roundOver: j['roundOver'] as bool,
    matchOver: j['matchOver'] as bool,
    wentOutSide: j['wentOutSide'] as int?,
    winnerSide: j['winnerSide'] as int?,
    roundIndex: j['roundIndex'] as int,
    roundResult: j['roundResult'] == null
        ? null
        : RoundResultView.fromJson(j['roundResult'] as Map<String, dynamic>),
    legalActions: (j['legalActions'] as List).cast<int>(),
    history: [
      for (final h in (j['history'] as List).cast<Map<String, dynamic>>())
        GameEvent.fromJson(h),
    ],
  );
}

MeldView _meldView(RulesConfig cfg, Meld meld) => MeldView(
  owner: meld.owner,
  isSequence: meld.kind == MeldKind.sequence,
  suit: meld.suit,
  rank: meld.rank,
  startPos: meld.startPos,
  cards: [for (final s in meld.slots) s.card],
  wildIndices: [
    for (var i = 0; i < meld.slots.length; i++)
      if (meld.slots[i].role == SlotRole.wild) i,
  ],
  isCanastra: meld.isCanastra(cfg.meld.canastraMinSize),
  isClean: meld.isClean,
  points: meldPoints(cfg, meld) + canastraBonus(cfg, meld),
);

/// Live per-side score from public zones only.
///
/// The terminal hand penalties depend on hidden hand values, so they are
/// deliberately excluded — showing them mid-round would leak every hand.
List<int> _publicSideScores(RoundState state) {
  final cfg = state.cfg;
  final scores = List.filled(cfg.table.numSides, 0);
  for (final meld in state.melds) {
    scores[meld.owner] += meldPoints(cfg, meld) + canastraBonus(cfg, meld);
  }
  if (cfg.morto.count != 0) {
    for (var side = 0; side < cfg.table.numSides; side++) {
      if (side < state.mortoTaken.length && !state.mortoTaken[side]) {
        scores[side] -= cfg.morto.untakenPenalty;
      }
    }
  }
  if (state.wentOutSide != null) {
    scores[state.wentOutSide!] += cfg.goingOut.goOutBonus;
  }
  return scores;
}

RoundResultView _resultView(RoundResult r) => RoundResultView(
  roundIndex: r.roundIndex,
  reason: r.reason.name,
  wentOutSide: r.wentOutSide,
  sheets: [
    for (final s in r.sheet)
      ScoreSheetView(
        side: s.side,
        lines: [for (final l in s.lines) (l.label, l.points)],
        total: s.total,
      ),
  ],
  matchScores: r.matchScoresAfter,
);

/// Build the view seat [seat] is entitled to.
///
/// [legalActions] is passed in rather than recomputed so it can only ever be
/// non-empty for the seat actually to act — a seat never learns what another
/// seat could play.
TableView buildTableView(
  Match match,
  int seat, {
  required List<String> playerNames,
  int matchNumber = 0,
}) {
  final cfg = match.cfg;
  final state = match.round;
  final table = cfg.table;

  final hand = <CardId>[];
  state.hands[seat].forEach((ct, n) {
    for (var i = 0; i < n; i++) {
      hand.add(ct);
    }
  });
  hand.sort();

  return TableView(
    seat: seat,
    side: table.side(seat),
    numPlayers: table.numPlayers,
    numSides: table.numSides,
    partnerSeat: table.numPlayers == 4 ? (seat + 2) % 4 : null,
    playerNames: playerNames,
    profile: cfg.name,
    matchTarget: cfg.scoring.matchTarget,
    canastraMinSize: cfg.meld.canastraMinSize,
    hand: hand,
    handSizes: [for (var p = 0; p < table.numPlayers; p++) state.handSize(p)],
    melds: [for (final m in state.melds) _meldView(cfg, m)],
    trash: List.of(state.trash),
    stockCount: state.stock.length,
    mortoTaken: List.of(state.mortoTaken),
    mortoSizes: [for (final packet in state.morto) packet?.length ?? 0],
    redThrees: [for (final tray in state.redThrees) List.of(tray)],
    currentPlayer: state.currentPlayer,
    phase: state.phase.name,
    turnNumber: state.turnNumber,
    frozen: state.frozen,
    pileBlocked: state.pileBlockedForNext,
    pendingPileCard: state.pendingPileCard,
    initialMeldDone: List.of(state.initialMeldDone),
    initialMeldMin: List.of(state.initialMeldMin),
    stagedPoints: state.stagedPoints,
    publicScores: _publicSideScores(state),
    matchScores: match.matchScores,
    matchNumber: matchNumber,
    roundOver: state.roundOver,
    matchOver: match.matchOver,
    wentOutSide: state.wentOutSide,
    winnerSide: match.winnerSide,
    roundIndex: match.roundIndex,
    roundResult: state.roundOver && match.lastRoundResult != null
        ? _resultView(match.lastRoundResult!)
        : null,
    // Only the seat to act learns its move list.
    legalActions: state.currentPlayer == seat
        ? match.legalActionIdsNow()
        : const [],
    history: match.history,
  );
}
