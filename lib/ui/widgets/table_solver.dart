/// Fluid table geometry for an arbitrary viewport.
///
/// This is the formula-driven sibling of [layOutTable]. It knows nothing about
/// widgets: one pass chooses readable card sizes, packs both meld shelves, and
/// returns every rectangle and card position the eventual screen needs.
library;

import 'dart:ui' show Offset, Rect, Size;

import '../../engine/cards.dart';
import '../../game/game_controller.dart' show PickedCard;
import '../../multiplayer/table_view.dart';
import 'playing_card.dart' show kCardHeight, kCardWidth;
import 'table_layout.dart' show CardSpot, kOpponentScale;

const double _cardHeightFactor = 1.42895;
const double _meldPadding = 0.11;
const double _meldStep = 0.48;
const double _meldMinimumUnits = 2.35;
const double _meldGap = 0.17;

/// What changes from one solve to the next, beyond the public table view.
class TableSolverInput {
  final Size viewport;
  final TableView view;
  final List<PickedCard> selection;
  final Set<int> openSlots;

  /// How many opening-deal cards have landed, unless [dealDone] skips it.
  final int dealt;
  final bool dealDone;

  /// A visual preference may enlarge the hand only while the shelves survive.
  final double cardBoost;

  /// Your hand in display order. The authoritative cards remain [TableView.hand].
  final List<CardId>? handOverride;

  const TableSolverInput({
    required this.viewport,
    required this.view,
    required this.selection,
    required this.openSlots,
    required this.dealt,
    required this.dealDone,
    this.cardBoost = 1,
    this.handOverride,
  });
}

/// Every font and control size derived by the solver.
///
/// Keeping these here prevents a screen from repeating a clamp with subtly
/// different headroom from the geometry it is drawing into.
class TableFontSizes {
  final double brandNameFs;
  final double brandSubFs;
  final double turnFs;
  final double turnDotSize;
  final double scoreLabelFs;
  final double scoreValueFs;
  final double nameFs;
  final double seatMetaFs;
  final double coachFs;
  final double chipFs;
  final double pileLabelFs;
  final double pileValueFs;
  final double meldCaptionFs;
  final double newMeldFs;
  final double newMeldPlusFs;
  final double avatarSize;
  final double backButtonSize;
  final double backIconSize;
  final double headerHeight;

  const TableFontSizes({
    required this.brandNameFs,
    required this.brandSubFs,
    required this.turnFs,
    required this.turnDotSize,
    required this.scoreLabelFs,
    required this.scoreValueFs,
    required this.nameFs,
    required this.seatMetaFs,
    required this.coachFs,
    required this.chipFs,
    required this.pileLabelFs,
    required this.pileValueFs,
    required this.meldCaptionFs,
    required this.newMeldFs,
    required this.newMeldPlusFs,
    required this.avatarSize,
    required this.backButtonSize,
    required this.backIconSize,
    required this.headerHeight,
  });
}

/// Which strip owns an opponent-hand count and its transient deal anchor.
enum SeatAnchorBand { theirStrip, myStrip }

class SeatAnchor {
  final int seat;
  final Offset position;
  final SeatAnchorBand band;

  const SeatAnchor({
    required this.seat,
    required this.position,
    required this.band,
  });
}

/// How a pile's label and foot relate to its stack.
enum PileTextOrientation { horizontal, stacked }

class PileSolution {
  final String id;

  /// Set only for a morto packet. Several packets share the morto [box].
  final int? side;
  final Rect box;
  final Rect stack;
  final List<CardSpot> cards;
  final PileTextOrientation textOrientation;

  const PileSolution({
    required this.id,
    required this.side,
    required this.box,
    required this.stack,
    required this.cards,
    required this.textOrientation,
  });

  bool get horizontal => textOrientation == PileTextOrientation.horizontal;
  bool get stacked => textOrientation == PileTextOrientation.stacked;
}

/// One framed meld and the cards positioned inside it.
class MeldSolution {
  final MeldView meld;
  final Rect rect;
  final bool mine;

  /// Index into [TableView.myMelds] when [mine].
  final int slot;
  final int row;
  final bool hot;
  final bool sealed;
  final bool clean;
  final String label;
  final double captionFontSize;

  /// The full caption estimate, including frame padding and four pixels of air.
  final double captionMinimumWidth;
  final List<CardSpot> cards;

  const MeldSolution({
    required this.meld,
    required this.rect,
    required this.mine,
    required this.slot,
    required this.row,
    required this.hot,
    required this.sealed,
    required this.clean,
    required this.label,
    required this.captionFontSize,
    required this.captionMinimumWidth,
    required this.cards,
  });
}

/// A complete, widget-free answer for one viewport.
class TableSolution {
  final Size viewport;
  final bool landscape;
  final bool narrowAct;
  final bool tight;
  final bool veryTight;
  final int degradation;
  final double cw;
  final double mcw;

  /// The spread factor selected by the ladder, or `0.12` for stacked melds.
  final double meldStepFactor;
  final bool stackedMelds;
  final double pad;
  final double gap;
  final double midInner;
  final double handStep;
  final double handFanWidth;
  final double pileCardWidth;
  final double railWidth;
  final double bankHeight;
  final int theirRows;
  final int myRows;
  final TableFontSizes fonts;

  final Rect header;
  final Rect theirStrip;
  final Rect theirShelf;
  final Rect theirBlock;
  final Rect myStrip;
  final Rect myShelf;
  final Rect myBlock;
  final Rect pileBand;
  final Rect newMeldSlot;
  final Rect hand;

  final List<MeldSolution> melds;
  final PileSolution stock;
  final PileSolution discard;
  final List<PileSolution> mortos;
  final List<SeatAnchor> seatAnchors;
  final List<CardSpot> cards;

  const TableSolution({
    required this.viewport,
    required this.landscape,
    required this.narrowAct,
    required this.tight,
    required this.veryTight,
    required this.degradation,
    required this.cw,
    required this.mcw,
    required this.meldStepFactor,
    required this.stackedMelds,
    required this.pad,
    required this.gap,
    required this.midInner,
    required this.handStep,
    required this.handFanWidth,
    required this.pileCardWidth,
    required this.railWidth,
    required this.bankHeight,
    required this.theirRows,
    required this.myRows,
    required this.fonts,
    required this.header,
    required this.theirStrip,
    required this.theirShelf,
    required this.theirBlock,
    required this.myStrip,
    required this.myShelf,
    required this.myBlock,
    required this.pileBand,
    required this.newMeldSlot,
    required this.hand,
    required this.melds,
    required this.stock,
    required this.discard,
    required this.mortos,
    required this.seatAnchors,
    required this.cards,
  });

  List<PileSolution> get piles => [stock, discard, ...mortos];
}

/// The compact, non-localised caption whose width this solver reserves.
///
/// A set needs only its rank because the visible cards carry its count. A run
/// reserves both endpoint ranks. Returning the string with the geometry makes
/// it impossible for the caller to measure one label and draw another.
String tableSolverMeldLabel(MeldView meld) {
  if (meld.isSequence) {
    final start = meld.startPos;
    final end = start == null ? null : start + meld.size - 1;
    if (start != null && start >= kPosMin && end != null && end <= kPosMax) {
      final low = kRankNames[rankAt(start)];
      final high = kRankNames[rankAt(end)];
      return low == high ? low : '$low–$high';
    }
  } else if (meld.rank case final rank? when rank >= 0 && rank < 13) {
    return kRankNames[rank];
  }

  final first = meld.cards.isEmpty ? null : idRank(meld.cards.first);
  return first == null ? '?' : kRankNames[first];
}

double tableSolverMeldCaptionFontSize(double cardWidth) =>
    _clamp(12.5, cardWidth * 0.20, 17);

/// The minimum framed width needed by a meld's caption and optional seal.
double tableSolverMeldCaptionMinimumWidth(MeldView meld, double cardWidth) {
  final fontSize = tableSolverMeldCaptionFontSize(cardWidth);
  final characterWidth = fontSize * 0.68;
  final captionGap = _max(4, cardWidth * 0.09);
  var caption =
      tableSolverMeldLabel(meld).length * characterWidth +
      captionGap +
      meld.points.toString().length * characterWidth;
  if (meld.isCanastra) {
    caption +=
        captionGap +
        (meld.isClean ? 5 : 4) * characterWidth * 0.92 +
        _max(8, cardWidth * 0.18);
  }
  return caption + 2 * cardWidth * _meldPadding + 4;
}

/// Solve the table using the mockup formulas and their fixed degradation order.
TableSolution solveTable(TableSolverInput input) {
  final view = input.view;
  final size = input.viewport;
  final landscape = size.width > size.height * 1.10;
  final theirMelds = [
    for (final meld in view.melds)
      if (meld.owner != view.side) meld,
  ];
  final myMelds = view.myMelds;
  final handCards = input.handOverride ?? view.hand;
  final scales = _solveScales(
    size: size,
    landscape: landscape,
    handCount: handCards.length,
    theirMelds: theirMelds,
    myMelds: myMelds,
    cardBoost: input.cardBoost,
  );
  final q = scales.metrics;
  final meldGap = scales.mcw * _meldGap;
  final meldHeight = _meldBoxHeight(scales.mcw);
  final theirRows = _rowsOf(
    theirMelds,
    scales.mcw,
    q.shelfW,
    extra: false,
    geometry: scales.geometry,
    stepFactor: scales.stepFactor,
  );
  final myRows = _rowsOf(
    myMelds,
    scales.mcw,
    q.shelfW,
    extra: true,
    geometry: scales.geometry,
    stepFactor: scales.stepFactor,
  );

  final midTop = q.pad + q.hdrH + q.g;
  final theirShelfHeight =
      theirRows * meldHeight + (theirRows - 1) * meldGap;
  final theirStrip = Rect.fromLTWH(q.pad, midTop, q.shelfW, q.stripH);
  final theirShelf = Rect.fromLTWH(
    q.pad,
    theirStrip.bottom + 4,
    q.shelfW,
    theirShelfHeight,
  );
  final theirBlock = Rect.fromLTWH(
    q.pad,
    midTop,
    q.shelfW,
    q.stripH + 4 + theirShelfHeight,
  );

  final myShelfHeight = myRows * meldHeight + (myRows - 1) * meldGap;
  final myStrip = Rect.fromLTWH(
    q.pad,
    theirBlock.bottom,
    q.shelfW,
    q.myStripH,
  );
  final myShelf = Rect.fromLTWH(
    q.pad,
    myStrip.bottom + 4,
    q.shelfW,
    myShelfHeight,
  );
  final myBlock = Rect.fromLTWH(
    q.pad,
    myStrip.top,
    q.shelfW,
    q.myStripH + 4 + myShelfHeight,
  );

  final pileBand = landscape
      ? Rect.fromLTWH(
          size.width - q.pad - q.railW,
          midTop,
          q.railW,
          q.midInner,
        )
      : Rect.fromLTWH(
          q.pad,
          midTop + q.midInner + q.g,
          size.width - 2 * q.pad,
          q.bankH,
        );
  final hand = Rect.fromLTWH(
    q.pad,
    size.height - q.pad - q.handH,
    size.width - 2 * q.pad,
    q.handH,
  );
  final header = Rect.fromLTWH(
    q.pad,
    q.pad,
    size.width - 2 * q.pad,
    q.hdrH,
  );

  final theirLayout = _layOutMelds(
    melds: theirMelds,
    shelf: theirShelf,
    mine: false,
    openSlots: input.openSlots,
    cardWidth: scales.mcw,
    geometry: scales.geometry,
    stepFactor: scales.stepFactor,
  );
  final myLayout = _layOutMelds(
    melds: myMelds,
    shelf: myShelf,
    mine: true,
    openSlots: input.openSlots,
    cardWidth: scales.mcw,
    geometry: scales.geometry,
    stepFactor: scales.stepFactor,
    includeNewMeld: true,
  );
  final piles = _layOutPiles(view, pileBand, q, landscape);

  final availableHandWidth = size.width - 2 * q.pad;
  final rawHandStep = handCards.length > 1
      ? (availableHandWidth - scales.cw) / (handCards.length - 1)
      : scales.cw * 0.58;
  final handStep = rawHandStep > scales.cw * 0.58
      ? scales.cw * 0.58
      : rawHandStep < 8
      ? 8.0
      : rawHandStep;
  final handFanWidth = handCards.isEmpty
      ? 0.0
      : scales.cw + handStep * (handCards.length - 1);
  final hands = _layOutHands(
    input: input,
    cards: handCards,
    handRect: hand,
    handStep: handStep,
    fanWidth: handFanWidth,
    theirStrip: theirStrip,
    myStrip: myStrip,
    stockOrigin: piles.stock.stack.topLeft,
    pileScale: q.pileCW / kCardWidth,
    cardWidth: scales.cw,
  );

  final fonts = TableFontSizes(
    brandNameFs: _clamp(17, scales.cw * 0.25, 34),
    brandSubFs: _clamp(12, scales.cw * 0.145, 15),
    turnFs: _clamp(12.5, scales.cw * 0.155, 16),
    turnDotSize: _max(5, scales.cw * 0.075),
    scoreLabelFs: _clamp(11.5, scales.cw * 0.135, 14),
    scoreValueFs: _clamp(20, scales.cw * 0.32, 40),
    nameFs: q.nameFs,
    seatMetaFs: _clamp(12, scales.cw * 0.145, 15),
    coachFs: q.coachFs,
    chipFs: q.chipFs,
    pileLabelFs: q.pileLabelFs,
    pileValueFs: q.pileValueFs,
    meldCaptionFs: tableSolverMeldCaptionFontSize(scales.mcw),
    newMeldFs: _clamp(12, scales.mcw * 0.19, 16),
    newMeldPlusFs: _clamp(16, scales.mcw * 0.44, 30),
    avatarSize: _max(22, scales.cw * 0.26),
    backButtonSize: _max(32, scales.cw * 0.40),
    backIconSize: _max(16, scales.cw * 0.19),
    headerHeight: q.hdrH,
  );
  final allCards = <CardSpot>[
    ...theirLayout.cards,
    ...myLayout.cards,
    ...piles.cards,
    ...hands.cards,
  ];

  return TableSolution(
    viewport: size,
    landscape: landscape,
    narrowAct: q.narrowAct,
    tight: size.width < scales.cw * 6.6,
    veryTight: size.width < 460,
    degradation: scales.degradation,
    cw: scales.cw,
    mcw: scales.mcw,
    meldStepFactor: scales.geometry == _MeldGeometry.stacked
        ? 0.12
        : scales.stepFactor,
    stackedMelds: scales.geometry == _MeldGeometry.stacked,
    pad: q.pad,
    gap: q.g,
    midInner: q.midInner,
    handStep: handStep,
    handFanWidth: handFanWidth,
    pileCardWidth: q.pileCW,
    railWidth: q.railW,
    bankHeight: q.bankH,
    theirRows: theirRows,
    myRows: myRows,
    fonts: fonts,
    header: header,
    theirStrip: theirStrip,
    theirShelf: theirShelf,
    theirBlock: theirBlock,
    myStrip: myStrip,
    myShelf: myShelf,
    myBlock: myBlock,
    pileBand: pileBand,
    newMeldSlot: myLayout.newMeldSlot,
    hand: hand,
    melds: [...theirLayout.melds, ...myLayout.melds],
    stock: piles.stock,
    discard: piles.discard,
    mortos: piles.mortos,
    seatAnchors: hands.anchors,
    cards: allCards,
  );
}

enum _MeldGeometry { spread, stacked }

class _Metrics {
  final double pad;
  final double g;
  final double hdrH;
  final double handH;
  final double stripH;
  final double actLine;
  final bool narrowAct;
  final double myStripH;
  final double midH;
  final double pileLabelFs;
  final double pileValueFs;
  final double pileBoxPad;
  final double pileBoxPadX;
  final double railLabelW;
  final double pileCW;
  final double railW;
  final double bankH;
  final double shelfW;
  final double nameFs;
  final double coachFs;
  final double chipFs;
  final double midInner;

  const _Metrics({
    required this.pad,
    required this.g,
    required this.hdrH,
    required this.handH,
    required this.stripH,
    required this.actLine,
    required this.narrowAct,
    required this.myStripH,
    required this.midH,
    required this.pileLabelFs,
    required this.pileValueFs,
    required this.pileBoxPad,
    required this.pileBoxPadX,
    required this.railLabelW,
    required this.pileCW,
    required this.railW,
    required this.bankH,
    required this.shelfW,
    required this.nameFs,
    required this.coachFs,
    required this.chipFs,
    required this.midInner,
  });
}

_Metrics _metrics(double cw, Size size, bool landscape) {
  final width = size.width;
  final height = size.height;
  final pad = _clamp(10, width * 0.024, 24);
  final gap = _max(7, cw * 0.12);
  final headerHeight = _max(44, cw * 0.44);
  final handHeight = cw * _cardHeightFactor + cw * 0.14;
  final stripHeight = _max(24, cw * 0.30);
  final actionLine = _max(28, cw * 0.34);
  final middleHeight = _max(
    110,
    height - 2 * pad - headerHeight - handHeight - 2 * gap,
  );
  final pileLabelFs = _clamp(12, cw * 0.145, 15);
  final pileValueFs = _clamp(13.5, cw * 0.17, 17);
  final pileBoxPad = _max(4, cw * 0.07);
  final pileBoxPadX = _max(5, cw * 0.10);
  const railText = [
    ('STOCK', '62 LEFT'),
    ('DISCARD', 'TAKE PILE'),
    ('MORTO', '2 LEFT'),
  ];
  var railLabelWidth = 0.0;
  for (final text in railText) {
    railLabelWidth = _max(
      railLabelWidth,
      _max(
        text.$1.length * pileLabelFs * 0.70,
        text.$2.length * pileValueFs * 0.70,
      ),
    );
  }
  railLabelWidth += 6;
  final railChrome =
      2 * pileBoxPadX + gap + railLabelWidth + 4;
  final stackSlack = 9 + 2 * gap;
  final pileCandidate = landscape
      ? _min(
          cw * 0.66,
          _min(
            (middleHeight -
                    2 * gap -
                    6 * pileBoxPad -
                    15 -
                    stackSlack) /
                (3 * _cardHeightFactor),
            (width * 0.23 - railChrome) / 1.28,
          ),
        )
      : _min(cw * 0.60, (width - 2 * pad) / 6.6);
  final pileCardWidth = _clamp(28, pileCandidate, 96);
  final railWidth = landscape ? railChrome + pileCardWidth * 1.28 : 0.0;
  final bankHeight = landscape
      ? 0.0
      : pileCardWidth * _cardHeightFactor +
            14 +
            (pileLabelFs + pileValueFs) * 1.35 +
            2 * pileBoxPad;
  final shelfWidth = _max(
    80,
    width - 2 * pad - (landscape ? railWidth + gap : 0),
  );
  final nameFs = _clamp(14, cw * 0.19, 20);
  final coachFs = _clamp(14.5, cw * 0.175, 18);
  final chipFs = _clamp(12, cw * 0.15, 15);
  final groupPadding = _max(6, cw * 0.11);
  final identityWidth =
      _max(22, cw * 0.26) + 3 * nameFs * 0.62 + 2 * groupPadding;
  final coachWidth = 37 * coachFs * 0.55;
  final chipsWidth =
      10 * chipFs * 0.66 +
      2 * _max(8, cw * 0.13) +
      5 * chipFs * 0.7 +
      7 * chipFs * 0.66 +
      2 * _max(9, cw * 0.15) +
      2 * groupPadding;
  final narrowAct =
      identityWidth + coachWidth + chipsWidth + 2 * groupPadding > shelfWidth;
  final myStripHeight = narrowAct
      ? stripHeight + 8 + actionLine
      : actionLine;
  final middleInner =
      middleHeight - (landscape ? 0 : bankHeight + gap) - gap;

  return _Metrics(
    pad: pad,
    g: gap,
    hdrH: headerHeight,
    handH: handHeight,
    stripH: stripHeight,
    actLine: actionLine,
    narrowAct: narrowAct,
    myStripH: myStripHeight,
    midH: middleHeight,
    pileLabelFs: pileLabelFs,
    pileValueFs: pileValueFs,
    pileBoxPad: pileBoxPad,
    pileBoxPadX: pileBoxPadX,
    railLabelW: railLabelWidth,
    pileCW: pileCardWidth,
    railW: railWidth,
    bankH: bankHeight,
    shelfW: shelfWidth,
    nameFs: nameFs,
    coachFs: coachFs,
    chipFs: chipFs,
    midInner: middleInner,
  );
}

class _ScaleSolution {
  final double cw;
  final double mcw;
  final int degradation;
  final double stepFactor;
  final _MeldGeometry geometry;
  final _Metrics metrics;

  const _ScaleSolution({
    required this.cw,
    required this.mcw,
    required this.degradation,
    required this.stepFactor,
    required this.geometry,
    required this.metrics,
  });
}

_ScaleSolution _solveScales({
  required Size size,
  required bool landscape,
  required int handCount,
  required List<MeldView> theirMelds,
  required List<MeldView> myMelds,
  required double cardBoost,
}) {
  final pad = _clamp(10, size.width * 0.024, 24);
  final cwByWidth =
      (size.width - 2 * pad) / (1 + 0.44 * (handCount - 1));

  if (_fitsCw(26, size, landscape, theirMelds, myMelds)) {
    var low = 26.0;
    var high = _max(26, _min(cwByWidth, 132));
    var cw = 26.0;
    for (var i = 0; i < 26; i++) {
      final middle = (low + high) / 2;
      if (_fitsCw(middle, size, landscape, theirMelds, myMelds)) {
        cw = middle;
        low = middle;
      } else {
        high = middle;
      }
    }
    cw = _clamp(
      26,
      cw * cardBoost,
      _min(cwByWidth * 1.15, 190),
    );
    final q = _metrics(cw, size, landscape);
    final mAny = _biggestMeld(
      cw: cw,
      floor: 24,
      rowCap: 2,
      q: q,
      theirMelds: theirMelds,
      myMelds: myMelds,
      geometry: _MeldGeometry.spread,
      stepFactor: _meldStep,
    );
    final mOne = _biggestMeld(
      cw: cw,
      floor: 24,
      rowCap: 1,
      q: q,
      theirMelds: theirMelds,
      myMelds: myMelds,
      geometry: _MeldGeometry.spread,
      stepFactor: _meldStep,
    );
    if (mAny > 0) {
      return _ScaleSolution(
        cw: cw,
        mcw: _preferredMeldWidth(mAny, mOne),
        degradation: 0,
        stepFactor: _meldStep,
        geometry: _MeldGeometry.spread,
        metrics: q,
      );
    }
  }

  const cw = 26.0;
  final q = _metrics(cw, size, landscape);
  final levelOneAny = _biggestMeld(
    cw: cw,
    floor: 18,
    rowCap: 3,
    q: q,
    theirMelds: theirMelds,
    myMelds: myMelds,
    geometry: _MeldGeometry.spread,
    stepFactor: _meldStep,
  );
  final levelOneOne = _biggestMeld(
    cw: cw,
    floor: 18,
    rowCap: 1,
    q: q,
    theirMelds: theirMelds,
    myMelds: myMelds,
    geometry: _MeldGeometry.spread,
    stepFactor: _meldStep,
  );
  if (levelOneAny > 0) {
    return _ScaleSolution(
      cw: cw,
      mcw: _preferredMeldWidth(levelOneAny, levelOneOne),
      degradation: 1,
      stepFactor: _meldStep,
      geometry: _MeldGeometry.spread,
      metrics: q,
    );
  }

  for (final stepFactor in const [0.40, 0.34, 0.28]) {
    final mAny = _biggestMeld(
      cw: cw,
      floor: 18,
      rowCap: 3,
      q: q,
      theirMelds: theirMelds,
      myMelds: myMelds,
      geometry: _MeldGeometry.spread,
      stepFactor: stepFactor,
    );
    if (mAny > 0) {
      return _ScaleSolution(
        cw: cw,
        mcw: mAny,
        degradation: 2,
        stepFactor: stepFactor,
        geometry: _MeldGeometry.spread,
        metrics: q,
      );
    }
  }

  final stacked = _biggestMeld(
    cw: cw,
    floor: 18,
    rowCap: 3,
    q: q,
    theirMelds: theirMelds,
    myMelds: myMelds,
    geometry: _MeldGeometry.stacked,
    stepFactor: 0.12,
  );
  if (stacked > 0) {
    return _ScaleSolution(
      cw: cw,
      mcw: stacked,
      degradation: 3,
      stepFactor: 0.12,
      geometry: _MeldGeometry.stacked,
      metrics: q,
    );
  }

  return _ScaleSolution(
    cw: cw,
    mcw: 18,
    degradation: 4,
    stepFactor: 0.12,
    geometry: _MeldGeometry.stacked,
    metrics: q,
  );
}

bool _fitsCw(
  double cw,
  Size size,
  bool landscape,
  List<MeldView> theirMelds,
  List<MeldView> myMelds,
) {
  final q = _metrics(cw, size, landscape);
  final meldWidth = _max(24, cw * 0.55);
  final theirRows = _rowsOf(
    theirMelds,
    meldWidth,
    q.shelfW,
    extra: false,
    geometry: _MeldGeometry.spread,
    stepFactor: _meldStep,
  );
  final myRows = _rowsOf(
    myMelds,
    meldWidth,
    q.shelfW,
    extra: true,
    geometry: _MeldGeometry.spread,
    stepFactor: _meldStep,
  );
  if (theirRows > 2 || myRows > 2) return false;
  final height =
      _blockHeight(theirRows, meldWidth, q.stripH) +
      _blockHeight(myRows, meldWidth, q.myStripH);
  return height <= q.midInner;
}

double _biggestMeld({
  required double cw,
  required double floor,
  required int rowCap,
  required _Metrics q,
  required List<MeldView> theirMelds,
  required List<MeldView> myMelds,
  required _MeldGeometry geometry,
  required double stepFactor,
}) {
  final ceiling = _min(cw * 0.92, 104);
  if (ceiling < floor ||
      !_meldFits(
        floor,
        rowCap,
        q,
        theirMelds,
        myMelds,
        geometry,
        stepFactor,
      )) {
    return 0;
  }

  var low = floor;
  var high = ceiling;
  var best = floor;
  for (var i = 0; i < 24; i++) {
    final middle = (low + high) / 2;
    if (_meldFits(
      middle,
      rowCap,
      q,
      theirMelds,
      myMelds,
      geometry,
      stepFactor,
    )) {
      best = middle;
      low = middle;
    } else {
      high = middle;
    }
  }
  return best;
}

bool _meldFits(
  double cardWidth,
  int rowCap,
  _Metrics q,
  List<MeldView> theirMelds,
  List<MeldView> myMelds,
  _MeldGeometry geometry,
  double stepFactor,
) {
  final theirRows = _rowsOf(
    theirMelds,
    cardWidth,
    q.shelfW,
    extra: false,
    geometry: geometry,
    stepFactor: stepFactor,
  );
  final myRows = _rowsOf(
    myMelds,
    cardWidth,
    q.shelfW,
    extra: true,
    geometry: geometry,
    stepFactor: stepFactor,
  );
  return theirRows <= rowCap &&
      myRows <= rowCap &&
      _blockHeight(theirRows, cardWidth, q.stripH) +
              _blockHeight(myRows, cardWidth, q.myStripH) <=
          q.midInner;
}

double _preferredMeldWidth(double anyRows, double oneRow) =>
    oneRow > 0 && oneRow >= anyRows * 0.82 ? oneRow : anyRows;

double _blockHeight(int rows, double cardWidth, double stripHeight) =>
    stripHeight +
    4 +
    rows * _meldBoxHeight(cardWidth) +
    (rows - 1) * cardWidth * _meldGap;

double _meldBoxHeight(double cardWidth) =>
    cardWidth * (0.09 + _cardHeightFactor) +
    _max(cardWidth * 0.46, 21);

double _meldUnits(
  int count,
  _MeldGeometry geometry,
  double stepFactor,
) {
  if (geometry == _MeldGeometry.stacked) {
    final visible = count < 3 ? count : 3;
    return _max(
      _meldMinimumUnits,
      _meldPadding * 2 + 1 + 0.12 * (visible - 1),
    );
  }
  return _max(
    _meldMinimumUnits,
    _meldPadding * 2 + 1 + stepFactor * (count - 1),
  );
}

double _meldWidth(
  MeldView meld,
  double cardWidth,
  _MeldGeometry geometry,
  double stepFactor,
) =>
    _max(
      _meldUnits(meld.cards.length, geometry, stepFactor) * cardWidth,
      tableSolverMeldCaptionMinimumWidth(meld, cardWidth),
    );

double _newMeldWidth(double cardWidth) {
  final fontSize = _clamp(12, cardWidth * 0.19, 16);
  return _max(cardWidth * 2.25, fontSize * 9 * 0.66 + 16);
}

int _rowsOf(
  List<MeldView> melds,
  double cardWidth,
  double shelfWidth, {
  required bool extra,
  required _MeldGeometry geometry,
  required double stepFactor,
}) {
  final widths = [
    for (final meld in melds)
      _meldWidth(meld, cardWidth, geometry, stepFactor),
    if (extra) _newMeldWidth(cardWidth),
  ];
  return _packRows(widths, cardWidth * _meldGap, shelfWidth - 4);
}

int _packRows(List<double> widths, double gap, double available) {
  var rows = 1;
  var x = 0.0;
  for (final width in widths) {
    final addition = x == 0 ? width : gap + width;
    if (x + addition > available && x > 0) {
      rows++;
      x = width;
    } else {
      x += addition;
    }
  }
  return rows;
}

class _PackedPosition {
  final double x;
  final int row;

  const _PackedPosition(this.x, this.row);
}

List<_PackedPosition> _packPositions(
  List<double> widths,
  double gap,
  double available,
) {
  final positions = <_PackedPosition>[];
  var row = 0;
  var x = 0.0;
  for (final width in widths) {
    final addition = x == 0 ? width : gap + width;
    if (x + addition > available && x > 0) {
      row++;
      x = 0;
    } else if (x > 0) {
      x += gap;
    }
    positions.add(_PackedPosition(x, row));
    x += width;
  }
  return positions;
}

class _MeldLayout {
  final List<MeldSolution> melds;
  final List<CardSpot> cards;
  final Rect newMeldSlot;

  const _MeldLayout({
    required this.melds,
    required this.cards,
    required this.newMeldSlot,
  });
}

_MeldLayout _layOutMelds({
  required List<MeldView> melds,
  required Rect shelf,
  required bool mine,
  required Set<int> openSlots,
  required double cardWidth,
  required _MeldGeometry geometry,
  required double stepFactor,
  bool includeNewMeld = false,
}) {
  final widths = [
    for (final meld in melds)
      _meldWidth(meld, cardWidth, geometry, stepFactor),
    if (includeNewMeld) _newMeldWidth(cardWidth),
  ];
  final gap = cardWidth * _meldGap;
  final positions = _packPositions(widths, gap, shelf.width - 4);
  final boxHeight = _meldBoxHeight(cardWidth);
  final solutions = <MeldSolution>[];
  final allCards = <CardSpot>[];
  final side = mine ? 'me' : 'them';

  for (var slot = 0; slot < melds.length; slot++) {
    final meld = melds[slot];
    final position = positions[slot];
    final rect = Rect.fromLTWH(
      shelf.left + position.x,
      shelf.top + position.row * (boxHeight + gap),
      widths[slot],
      boxHeight,
    );
    final cards = <CardSpot>[];
    final cardStep = cardWidth * (geometry == _MeldGeometry.stacked
        ? 0.12
        : stepFactor);
    for (var i = 0; i < meld.cards.length; i++) {
      final thickness = geometry == _MeldGeometry.stacked && i > 2 ? 2 : i;
      cards.add(
        CardSpot(
          key: 'meld:$side:$slot:$i',
          card: meld.cards[i],
          x: rect.left + cardWidth * _meldPadding + thickness * cardStep,
          y: rect.top + cardWidth * _meldPadding * 0.75,
          scale: cardWidth / kCardWidth,
          z: 20 + i,
          faceUp: true,
          asWild: meld.wildIndices.contains(i),
        ),
      );
    }
    allCards.addAll(cards);
    solutions.add(
      MeldSolution(
        meld: meld,
        rect: rect,
        mine: mine,
        slot: slot,
        row: position.row,
        hot: mine && openSlots.contains(slot),
        sealed: meld.isCanastra,
        clean: meld.isClean,
        label: tableSolverMeldLabel(meld),
        captionFontSize: tableSolverMeldCaptionFontSize(cardWidth),
        captionMinimumWidth: tableSolverMeldCaptionMinimumWidth(
          meld,
          cardWidth,
        ),
        cards: cards,
      ),
    );
  }

  final newMeldSlot = includeNewMeld
      ? Rect.fromLTWH(
          shelf.left + positions.last.x,
          shelf.top + positions.last.row * (boxHeight + gap),
          widths.last,
          boxHeight,
        )
      : Rect.zero;
  return _MeldLayout(
    melds: solutions,
    cards: allCards,
    newMeldSlot: newMeldSlot,
  );
}

class _PileLayout {
  final PileSolution stock;
  final PileSolution discard;
  final List<PileSolution> mortos;
  final List<CardSpot> cards;

  const _PileLayout({
    required this.stock,
    required this.discard,
    required this.mortos,
    required this.cards,
  });
}

_PileLayout _layOutPiles(
  TableView view,
  Rect band,
  _Metrics q,
  bool landscape,
) {
  final nonEmptyMortoSides = <int>[];
  if (view.mortoSizes.isNotEmpty) {
    if (view.side >= 0 &&
        view.side < view.mortoSizes.length &&
        view.mortoSizes[view.side] > 0) {
      nonEmptyMortoSides.add(view.side);
    }
    for (var side = 0; side < view.mortoSizes.length; side++) {
      if (side != view.side && view.mortoSizes[side] > 0) {
        nonEmptyMortoSides.add(side);
      }
    }
  }
  final hasMortoZone = view.mortoSizes.isNotEmpty;
  final zoneCount = hasMortoZone ? 3 : 2;
  final miniWidth = q.pileCW * 0.78;
  final miniPacketWidth = miniWidth + 2 * 1.4;
  final mortoGroupWidth = nonEmptyMortoSides.isEmpty
      ? q.pileCW * 1.28
      : miniPacketWidth +
            (nonEmptyMortoSides.length - 1) * q.pileCW * 0.50;
  final basePortraitWidth = _max(q.pileCW * 1.28, q.railLabelW);
  final portraitWidths = [
    basePortraitWidth,
    basePortraitWidth,
    if (hasMortoZone) _max(basePortraitWidth, mortoGroupWidth),
  ];
  final portraitGap = q.pileCW * 0.20;
  final portraitTotal =
      portraitWidths.fold(0.0, (sum, width) => sum + width) +
      portraitGap * (portraitWidths.length - 1);
  final portraitStart = band.left + (band.width - portraitTotal) / 2;

  Rect boxAt(int index) {
    if (landscape) {
      final height = band.height / zoneCount;
      return Rect.fromLTWH(
        band.left,
        band.top + index * height,
        band.width,
        height,
      );
    }
    var x = portraitStart;
    for (var i = 0; i < index; i++) {
      x += portraitWidths[i] + portraitGap;
    }
    return Rect.fromLTWH(x, band.top, portraitWidths[index], band.height);
  }

  Offset stackOrigin(Rect box, double width, double height) => landscape
      ? Offset(
          box.left + q.pileBoxPadX,
          box.top + (box.height - height) / 2,
        )
      : Offset(box.left + (box.width - width) / 2, box.top + q.pileBoxPad);

  final orientation = landscape
      ? PileTextOrientation.horizontal
      : PileTextOrientation.stacked;
  final pileHeight = q.pileCW * _cardHeightFactor;

  final stockBox = boxAt(0);
  final stockStack = Rect.fromLTWH(
    stackOrigin(stockBox, q.pileCW + 5, pileHeight + 5).dx,
    stackOrigin(stockBox, q.pileCW + 5, pileHeight + 5).dy,
    q.pileCW + 5,
    pileHeight + 5,
  );
  final stockCards = <CardSpot>[];
  final stockShown = view.stockCount < 3 ? view.stockCount : 3;
  for (var i = 0; i < stockShown; i++) {
    stockCards.add(
      CardSpot(
        key: 'stock:$i',
        card: 0,
        x: stockStack.left + i * 2.5,
        y: stockStack.top + i * 2.5,
        scale: q.pileCW / kCardWidth,
        z: 10 + i,
        faceUp: false,
      ),
    );
  }
  final stock = PileSolution(
    id: 'stock',
    side: null,
    box: stockBox,
    stack: stockStack,
    cards: stockCards,
    textOrientation: orientation,
  );

  final discardBox = boxAt(1);
  final discardStackWidth = q.pileCW * 1.12;
  final discardStackHeight = pileHeight + 4;
  final discardOrigin = stackOrigin(
    discardBox,
    discardStackWidth,
    discardStackHeight,
  );
  final discardStack = Rect.fromLTWH(
    discardOrigin.dx,
    discardOrigin.dy,
    discardStackWidth,
    discardStackHeight,
  );
  final discardCards = <CardSpot>[];
  if (view.trash.length > 1) {
    final under = view.trash.length - 2;
    discardCards.add(
      CardSpot(
        key: 'pile:$under',
        card: view.trash[under],
        x: discardStack.left + q.pileCW * 0.12,
        y: discardStack.top + 4,
        scale: q.pileCW / kCardWidth,
        z: 12,
        faceUp: false,
      ),
    );
  }
  if (view.trash.isNotEmpty) {
    final top = view.trash.length - 1;
    discardCards.add(
      CardSpot(
        key: 'pile:$top',
        card: view.trash[top],
        x: discardStack.left,
        y: discardStack.top,
        scale: q.pileCW / kCardWidth,
        z: 13,
        faceUp: true,
      ),
    );
  }
  final discard = PileSolution(
    id: 'discard',
    side: null,
    box: discardBox,
    stack: discardStack,
    cards: discardCards,
    textOrientation: orientation,
  );

  final mortos = <PileSolution>[];
  final mortoCards = <CardSpot>[];
  if (hasMortoZone && nonEmptyMortoSides.isNotEmpty) {
    final mortoBox = boxAt(2);
    final miniHeight = miniWidth * _cardHeightFactor;
    final groupHeight = miniHeight + 2 * 1.4;
    final groupOrigin = stackOrigin(mortoBox, mortoGroupWidth, groupHeight);
    for (var packet = 0; packet < nonEmptyMortoSides.length; packet++) {
      final side = nonEmptyMortoSides[packet];
      final stack = Rect.fromLTWH(
        groupOrigin.dx + packet * q.pileCW * 0.50,
        groupOrigin.dy,
        miniPacketWidth,
        groupHeight,
      );
      final cards = <CardSpot>[];
      final size = view.mortoSizes[side];
      final shown = size < 3 ? size : 3;
      for (var i = 0; i < shown; i++) {
        cards.add(
          CardSpot(
            key: 'morto:$side:$i',
            card: 0,
            x: stack.left + i * 1.4,
            y: stack.top + i * 1.4,
            scale: miniWidth / kCardWidth,
            z: 10 + i,
            faceUp: false,
          ),
        );
      }
      mortoCards.addAll(cards);
      mortos.add(
        PileSolution(
          id: 'morto',
          side: side,
          box: mortoBox,
          stack: stack,
          cards: cards,
          textOrientation: orientation,
        ),
      );
    }
  }

  return _PileLayout(
    stock: stock,
    discard: discard,
    mortos: mortos,
    cards: [...stockCards, ...discardCards, ...mortoCards],
  );
}

class _HandsLayout {
  final List<CardSpot> cards;
  final List<SeatAnchor> anchors;

  const _HandsLayout({required this.cards, required this.anchors});
}

_HandsLayout _layOutHands({
  required TableSolverInput input,
  required List<CardId> cards,
  required Rect handRect,
  required double handStep,
  required double fanWidth,
  required Rect theirStrip,
  required Rect myStrip,
  required Offset stockOrigin,
  required double pileScale,
  required double cardWidth,
}) {
  final view = input.view;
  final dealSeats = [
    view.seat,
    for (var seat = 0; seat < view.numPlayers; seat++)
      if (seat != view.seat) seat,
  ];

  bool landed(int order, int index) =>
      input.dealDone ||
      input.dealt >= index * dealSeats.length + order + 1;

  final spots = <CardSpot>[];
  final unpicked = [...input.selection];
  final copies = <CardId, int>{};
  final handStart = handRect.left + (handRect.width - fanWidth) / 2;
  for (var i = 0; i < cards.length; i++) {
    final copy = copies[cards[i]] ?? 0;
    copies[cards[i]] = copy + 1;
    final selected = unpicked.remove((ct: cards[i], copy: copy));
    final destination = CardSpot(
      key: 'hand:$i',
      card: cards[i],
      x: handStart + i * handStep,
      y: selected ? handRect.top : handRect.top + cardWidth * 0.14,
      scale: cardWidth / kCardWidth,
      z: 60 + i,
      faceUp: true,
      selected: selected,
      inHand: true,
      copy: copy,
    );
    spots.add(
      landed(0, i)
          ? destination
          : CardSpot(
              key: destination.key,
              card: destination.card,
              x: stockOrigin.dx,
              y: stockOrigin.dy,
              scale: pileScale,
              z: destination.z,
              faceUp: false,
            ),
    );
  }

  final partner = view.numPlayers == 4
      ? view.partnerSeat ??
            (view.seat >= 0 ? (view.seat + 2) % view.numPlayers : null)
      : null;
  final theirSeats = <int>[];
  final mySeats = <int>[];
  for (var seat = 0; seat < view.numPlayers; seat++) {
    if (seat == view.seat) continue;
    if (seat == partner) {
      mySeats.add(seat);
    } else {
      theirSeats.add(seat);
    }
  }

  List<SeatAnchor> anchorsIn(
    List<int> seats,
    Rect strip,
    SeatAnchorBand band,
  ) => [
    for (var i = 0; i < seats.length; i++)
      SeatAnchor(
        seat: seats[i],
        position: Offset(
          strip.left + strip.width * (i + 0.5) / seats.length,
          strip.center.dy,
        ),
        band: band,
      ),
  ];

  final anchors = [
    ...anchorsIn(theirSeats, theirStrip, SeatAnchorBand.theirStrip),
    ...anchorsIn(mySeats, myStrip, SeatAnchorBand.myStrip),
  ];
  final destinationWidth = kCardWidth * kOpponentScale;
  final destinationHeight = kCardHeight * kOpponentScale;
  for (final anchor in anchors) {
    final count = anchor.seat < view.handSizes.length
        ? view.handSizes[anchor.seat]
        : 0;
    if (count == 0) continue;
    final order = dealSeats.indexOf(anchor.seat);
    if (input.dealDone || landed(order, count - 1)) continue;

    for (var i = 0; i < count; i++) {
      final isLanded = landed(order, i);
      spots.add(
        CardSpot(
          key: 'seat${anchor.seat}:$i',
          card: 0,
          x: isLanded
              ? anchor.position.dx - destinationWidth / 2
              : stockOrigin.dx,
          y: isLanded
              ? anchor.position.dy - destinationHeight / 2
              : stockOrigin.dy,
          scale: isLanded ? kOpponentScale : pileScale,
          z: 30 + i,
          faceUp: false,
        ),
      );
    }
  }
  return _HandsLayout(cards: spots, anchors: anchors);
}

double _clamp(double low, double value, double high) =>
    _max(low, _min(high, value));

double _min(double a, double b) => a < b ? a : b;

double _max(double a, double b) => a > b ? a : b;
