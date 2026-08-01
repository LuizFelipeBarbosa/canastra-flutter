/// Where everything on the table is.
///
/// One pass computes a position for every card, zone and meld box in stage
/// coordinates, and the screen does nothing but draw the result. Keeping it apart
/// from the widgets is what makes the table cheap to animate: a card is the same
/// widget at a new position from one frame to the next, so it glides instead of
/// being rebuilt somewhere else — and the geometry can be reasoned about, or
/// tested, without pumping a single frame.
///
/// Every number here is a coordinate in one of the two stages, and which one it
/// is comes from a [TableMetrics] rather than from a constant.
library;

import 'dart:ui' show Size;

import '../../engine/cards.dart';
import '../../game/game_controller.dart' show PickedCard;
import '../../game/move_index.dart';
import '../../multiplayer/table_view.dart';
import 'playing_card.dart';
import 'stage.dart';

/// How much of life size a card is drawn at, per place it can be.
///
/// The stock, the pile, the morto and an opponent's hand are the same size on
/// either stage: what a narrow table has to give up is the *spread* of a meld,
/// not the size of a card in the middle of the felt.
const double kPileScale = 0.72;
const double kMortoScale = 0.52;
const double kOpponentScale = 0.42;

/// How tall the hand-order toggle's band is.
const double kHandOrderHeight = 24;

/// How a side's melds are packed onto the felt.
enum MeldStyle {
  /// One row per side, each meld spread out so every card in it is readable,
  /// with the play area sharing the row with yours.
  spread,

  /// Squared-up stacks over two rows, with the play area in a band of its own.
  ///
  /// Nine melds cannot be spread across a phone: the frames alone are wider than
  /// the felt before a single card is drawn. A stack shows the top card, the
  /// thickness, the count and the seal — the same trade the discard pile already
  /// makes — and every card in it is still a real widget at a real position, so
  /// melding one still glides.
  stacked,
}

/// Every number the table is laid out from, for one stage.
///
/// The landscape values are the design's. Most of them turn out to be
/// derivations of the stage rather than arbitrary constants — the play area's
/// right edge is a margin in from the edge, your meld row is the felt less the
/// play area, your hand fans across the felt less a card's worth of air — which
/// is what lets a second stage reuse this geometry instead of a second copy of
/// it.
class TableMetrics {
  final Size size;

  /// What every row, bar and label is inset by.
  final double margin;

  /// How much of life size a melded card is drawn at.
  final double meldScale;

  /// How much of a melded card the next one along leaves showing.
  final double meldOverlap;

  /// How your melds are packed onto their row, or rows.
  final MeldStyle meldStyle;

  /// Whether the chrome has to fold: the header's four toggles into one way in
  /// to all of them, the back link down to its arrow, the activity line onto a
  /// row of its own. Nothing to do with the melds — a stage can be too narrow
  /// for a row of pills and still have room to spread them.
  final bool narrow;

  /// The air a meld box keeps around its cards. A spread meld is a named frame
  /// and can wear the padding; a stack is barely wider than the one card it
  /// shows, and every point spent on its border is a point off the card.
  final double meldFrame;

  /// How many cards' worth of thickness a stack shows before the rest of the
  /// meld sits under its top card. Only read when the melds are
  /// [MeldStyle.stacked]; a spread meld shows every card it has.
  final int meldStackDepth;

  /// The smallest a melded card may be drawn when a row will not fit any other
  /// way. Either stage reaches for it: a wide table holds more melds before it
  /// has to, but nine of seven are already wider than the felt.
  ///
  /// It is set low on purpose. A row that fits at a comfortable size never
  /// touches the floor, so lowering it costs an ordinary table nothing at all —
  /// the only rows it speaks for are the crowded ones, and for those the choice
  /// is between a small card and a meld the stage clips away entirely. A player
  /// can read a small card. They cannot read one that was never drawn.
  final double minMeldScale;

  /// The row the play area sits on, and how tall it is. Only read when the
  /// melds are [MeldStyle.stacked]; a spread row shares its geometry.
  final double playY;
  final double playHeight;

  /// The rows the two sides' melds live on, and the labels above them.
  final double theirRowY;
  final double theirLabelY;
  final double myRowY;
  final double myLabelY;

  /// The middle of the table: where the cards in the three zones are drawn, and
  /// where each zone starts.
  final double centreY;
  final double stockX;
  final double pileX;
  final double mortoX;

  /// Wide enough for both sides' mortos, side by side.
  final double mortoZoneWidth;

  /// The action strip and the line beneath it.
  final double stripY;
  final double stripHeight;
  final double whyNotY;

  /// Where your hand rests, and how far a card rises when you pick it up.
  final double handY;
  final double handLift;

  /// Where the hand-order toggle rests beneath it.
  final double handOrderY;

  /// The bar across the top, and the row of seat chips under it.
  final double headerHeight;
  final double seatChipsY;

  /// How much of the header the variant and round line may take before they
  /// ellipsise, and how wide an opponent's name may be on its chip. Both are
  /// unbounded on a wide table, where there is room for whatever they say.
  final double headerTitleWidth;
  final double seatNameWidth;

  /// The band the opponents' hands fan across. On a wide table it is the same
  /// row as the seat chips, off to the right of them.
  final double opponentsX;
  final double opponentsWidth;
  final double opponentsY;

  /// The narrowest the play area may become.
  final double minPlayWidth;

  const TableMetrics({
    required this.size,
    required this.margin,
    required this.meldScale,
    required this.meldOverlap,
    required this.meldStyle,
    required this.narrow,
    required this.meldFrame,
    required this.meldStackDepth,
    required this.minMeldScale,
    required this.playY,
    required this.playHeight,
    required this.theirRowY,
    required this.theirLabelY,
    required this.myRowY,
    required this.myLabelY,
    required this.centreY,
    required this.stockX,
    required this.pileX,
    required this.mortoX,
    required this.mortoZoneWidth,
    required this.stripY,
    required this.stripHeight,
    required this.whyNotY,
    required this.handY,
    required this.handLift,
    required this.handOrderY,
    required this.headerHeight,
    required this.seatChipsY,
    required this.headerTitleWidth,
    required this.seatNameWidth,
    required this.opponentsX,
    required this.opponentsWidth,
    required this.opponentsY,
    required this.minPlayWidth,
  });

  static const landscape = TableMetrics(
    size: kStageLandscape,
    margin: 20,
    meldScale: 0.575,
    meldOverlap: 0.42,
    meldStyle: MeldStyle.spread,
    narrow: false,
    meldFrame: 18,
    meldStackDepth: 3,
    minMeldScale: 0.239,
    playY: 358,
    playHeight: 88.445,
    theirRowY: 116,
    theirLabelY: 102,
    myRowY: 358,
    myLabelY: 340,
    centreY: 232,
    stockX: 452,
    pileX: 566,
    mortoX: 686,
    mortoZoneWidth: 106,
    stripY: 462,
    stripHeight: 46,
    whyNotY: 518,
    handY: 596,
    handLift: 22,
    handOrderY: 720,
    headerHeight: 58,
    seatChipsY: 62,
    headerTitleWidth: double.infinity,
    seatNameWidth: double.infinity,
    opponentsX: 962,
    opponentsWidth: 236,
    opponentsY: 62,
    minPlayWidth: 190,
  );

  /// A phone held upright.
  ///
  /// The bands run: header, seat chips, the activity line, the opponents' fan,
  /// their melds, the three zones, your melds over two rows, the play area, the
  /// strip, the refusal line, your hand along the bottom, and the hand-order
  /// toggle.
  static const portrait = TableMetrics(
    size: kStagePortrait,
    margin: 16,
    meldScale: 0.42,
    meldOverlap: 0.075,
    meldStyle: MeldStyle.stacked,
    narrow: true,
    meldFrame: 6,
    meldStackDepth: 3,
    minMeldScale: 0.129,
    playY: 550,
    playHeight: 56,
    theirRowY: 172,
    theirLabelY: 156,
    myRowY: 408,
    myLabelY: 392,
    centreY: 268,
    stockX: 20,
    pileX: 155,
    mortoX: 294,
    mortoZoneWidth: 106,
    stripY: 600,
    stripHeight: 44,
    whyNotY: 648,
    handY: 702,
    handLift: 22,
    handOrderY: 814,
    headerHeight: 48,
    seatChipsY: 52,
    headerTitleWidth: 150,
    seatNameWidth: 84,
    opponentsX: 16,
    opponentsWidth: 356,
    opponentsY: 104,
    minPlayWidth: 190,
  );

  double get meldCardWidth => kCardWidth * meldScale;
  double get meldCardHeight => kCardHeight * meldScale;

  /// A meld box is its cards plus room for its name underneath. A stack has
  /// only a count and a score to fit under it, so it needs less.
  ///
  /// A row that had to shrink its cards to fit is shorter than the metric's
  /// own, which is why the height is asked for at a scale rather than read off
  /// [meldScale].
  double meldBoxHeightAt(double scale) =>
      kCardHeight * scale + (meldStyle == MeldStyle.spread ? 26 : 20);

  double get meldBoxHeight => meldBoxHeightAt(meldScale);

  /// How far apart your two rows of melds sit, when there are two.
  double get meldRowPitch => meldBoxHeight + 6;

  /// How many rows your melds are dealt onto.
  int get myMeldRows => meldStyle == MeldStyle.spread ? 1 : 2;

  double get zoneY => centreY - 22;
  double get zoneHeight => kCardHeight * kPileScale + 56;

  /// The far edge the play area stops at, leaving the same margin as everything
  /// else on the row.
  double get playRight => size.width - margin;

  /// The opponent may use the whole felt. So may you, once the play area has a
  /// band of its own; while it shares your row, your span stops short of it so
  /// that compressing a long row reserves its tap target instead of running a
  /// meld box underneath it.
  double get theirMeldSpan => size.width - 2 * margin;
  double get myMeldSpan =>
      theirMeldSpan - (meldStyle == MeldStyle.spread ? minPlayWidth : 0);

  /// The width your hand fans across: the felt, less a card's worth of air at
  /// each end so the fan never leaves the stage however large the hand grows.
  double get handSpan => size.width - 80;
}

/// Where a card sits, and how it should look there.
class CardSpot {
  /// Identity across rebuilds. A card type is held and melded many times over a
  /// two-deck game, so this is a place-and-copy identifier rather than the card
  /// itself — it is what makes the same widget follow the same card as it moves.
  final String key;

  final CardId card;
  final double x;
  final double y;
  final double scale;
  final int z;

  final bool faceUp;
  final bool asWild;
  final bool selected;

  /// In your hand, and therefore something you can pick up.
  final bool inHand;

  /// Which of the hand's identically-typed copies this is (0 = leftmost).
  /// Hand cards only; it is what a tap reports so the tapped twin is the one
  /// that rises.
  final int copy;

  const CardSpot({
    required this.key,
    required this.card,
    required this.x,
    required this.y,
    required this.scale,
    required this.z,
    required this.faceUp,
    this.asWild = false,
    this.selected = false,
    this.inHand = false,
    this.copy = 0,
  });

  CardSpot _withKey(String key) => CardSpot(
    key: key,
    card: card,
    x: x,
    y: y,
    scale: scale,
    z: z,
    faceUp: faceUp,
    asWild: asWild,
    selected: selected,
    inHand: inHand,
    copy: copy,
  );

  CardSpot onTheStock(TableMetrics m) => CardSpot(
    key: key,
    card: card,
    x: m.stockX + 15,
    y: m.centreY,
    scale: kPileScale,
    z: z,
    faceUp: false,
  );
}

/// Rewrites [CardSpot] keys to stable per-card-copy identities so the same
/// widget follows the same physical card as it moves between zones.
class CardIdentityTracker {
  final Map<CardId, List<_PreviousCardIdentity>> _previous = {};
  final Map<CardId, int> _nextOrdinal = {};

  void reset() {
    _previous.clear();
    _nextOrdinal.clear();
  }

  /// Call once per layout pass with the frame's spots in layout order.
  ///
  /// Positional keys remain useful as observations: an exact position is the
  /// strongest evidence that a copy stayed put, while the key's prefix tells us
  /// whether it merely shifted within a hand, pile, or individual meld. Only
  /// after preserving those matches can a cross-zone move claim a remaining
  /// identity, which is what lets a discarded card glide from hand to pile.
  List<CardSpot> assign(List<CardSpot> spots) {
    final currentByType = <CardId, List<_CurrentCardIdentity>>{};
    for (var i = 0; i < spots.length; i++) {
      final spot = spots[i];
      if (_isBackPlaceholder(spot.key)) continue;

      currentByType
          .putIfAbsent(spot.card, () => [])
          .add(
            _CurrentCardIdentity(
              spotIndex: i,
              location: _CardLocation.fromKey(spot.key),
            ),
          );
    }

    final ordinals = List<int?>.filled(spots.length, null);
    final next = <CardId, List<_PreviousCardIdentity>>{};
    for (final entry in currentByType.entries) {
      final previous = _previous[entry.key] ?? const [];
      final claimed = List<bool>.filled(previous.length, false);

      void matchPrevious(
        bool Function(_CardLocation current, _CardLocation previous) matches,
      ) {
        for (final current in entry.value) {
          if (ordinals[current.spotIndex] != null) continue;
          for (var i = 0; i < previous.length; i++) {
            if (claimed[i] ||
                !matches(current.location, previous[i].location)) {
              continue;
            }
            ordinals[current.spotIndex] = previous[i].ordinal;
            claimed[i] = true;
            break;
          }
        }
      }

      matchPrevious(
        (current, previous) =>
            current.zone == previous.zone && current.slot == previous.slot,
      );
      matchPrevious((current, previous) => current.zone == previous.zone);
      matchPrevious((current, previous) => true);

      var nextOrdinal = _nextOrdinal[entry.key] ?? 0;
      for (final current in entry.value) {
        if (ordinals[current.spotIndex] != null) continue;
        ordinals[current.spotIndex] = nextOrdinal;
        nextOrdinal++;
      }
      _nextOrdinal[entry.key] = nextOrdinal;

      next[entry.key] = [
        for (final current in entry.value)
          _PreviousCardIdentity(
            ordinal: ordinals[current.spotIndex]!,
            location: current.location,
          ),
      ];
    }

    _previous
      ..clear()
      ..addAll(next);

    return [
      for (var i = 0; i < spots.length; i++)
        if (ordinals[i] case final ordinal?)
          spots[i]._withKey('card:${spots[i].card}:$ordinal')
        else
          spots[i],
    ];
  }
}

class _CurrentCardIdentity {
  final int spotIndex;
  final _CardLocation location;

  const _CurrentCardIdentity({required this.spotIndex, required this.location});
}

class _PreviousCardIdentity {
  final int ordinal;
  final _CardLocation location;

  const _PreviousCardIdentity({required this.ordinal, required this.location});
}

class _CardLocation {
  final String zone;
  final String slot;

  const _CardLocation({required this.zone, required this.slot});

  factory _CardLocation.fromKey(String key) {
    final parts = key.split(':');
    final zone = parts.first == 'meld' && parts.length >= 3
        ? parts.take(3).join(':')
        : parts.first;
    return _CardLocation(zone: zone, slot: key);
  }
}

/// Stock, morto, and opponent-hand backs carry no card type in the player's
/// view. Letting their sentinel value consume a real ordinal would collide with
/// the valid card id zero, while their existing positional keys are already the
/// only identity the renderer can meaningfully preserve.
bool _isBackPlaceholder(String key) =>
    key.startsWith('stock:') ||
    key.startsWith('morto:') ||
    (key.startsWith('seat') && key.contains(':'));

/// One of the named places in the middle of the table, or the play area.
class ZoneSpot {
  final String id;
  final double x;
  final double y;
  final double width;
  final double height;

  final String label;
  final String foot;

  /// A legal destination for what is going on right now.
  final bool hot;

  /// The play area is dashed; the rest are solid.
  final bool dashed;

  /// Going out is the one hot state that is gold rather than mint.
  final bool terminal;

  const ZoneSpot({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.label,
    required this.foot,
    this.hot = false,
    this.dashed = false,
    this.terminal = false,
  });
}

/// A meld on the table.
class MeldSpot {
  /// Index into your side's melds — the slot the engine adds to. Only meaningful
  /// when [mine].
  final int slot;
  final bool mine;
  final MeldView meld;

  final double x;
  final double y;
  final double width;
  final double height;

  /// Drawn as a stack: too narrow for the meld's name, so it carries a count
  /// and its score instead.
  final bool compact;

  /// The selection would fit here.
  final bool open;

  const MeldSpot({
    required this.slot,
    required this.mine,
    required this.meld,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.compact,
    required this.open,
  });
}

class TableLayout {
  final List<CardSpot> cards;
  final List<ZoneSpot> zones;
  final List<MeldSpot> melds;

  const TableLayout({
    required this.cards,
    required this.zones,
    required this.melds,
  });

  static const empty = TableLayout(cards: [], zones: [], melds: []);
}

/// The strings the zones show, already in the reader's language. The layout is
/// deliberately free of copy so it can be read as geometry.
class ZoneWords {
  final String stock;
  final String pile;
  final String morto;
  final String playArea;
  final String playIdle;
  final String playReady;
  final String pileDiscard;
  final String pileBatida;
  final String empty;
  final String waiting;
  final String taken;

  /// "24 left".
  final String Function(int) left;

  /// "3 cards".
  final String Function(int) cards;

  const ZoneWords({
    required this.stock,
    required this.pile,
    required this.morto,
    required this.playArea,
    required this.playIdle,
    required this.playReady,
    required this.pileDiscard,
    required this.pileBatida,
    required this.empty,
    required this.waiting,
    required this.taken,
    required this.left,
    required this.cards,
  });
}

/// Rank-major hand order: low ranks first, ties broken by suit, jokers last.
///
/// The view's own hand order is suit-major, so this is the one alternative a
/// re-sorted [LayoutInput.handOverride] needs.
int rankMajorOrder(CardId a, CardId b) {
  if (isJoker(a) || isJoker(b)) {
    return (isJoker(a) ? 1 : 0) - (isJoker(b) ? 1 : 0);
  }
  final byRank = idRank(a)! - idRank(b)!;
  return byRank != 0 ? byRank : idSuit(a)! - idSuit(b)!;
}

/// What the screen tells the layout that the view does not already say.
class LayoutInput {
  final TableView view;
  final MoveIndex moves;

  /// Which stage this table is being laid out in.
  final TableMetrics metrics;

  /// Your hand in the order to draw it, when a preference re-sorts it.
  /// Display only — everything else still speaks [TableView.hand]'s cards.
  final List<CardId>? handOverride;

  /// What is picked up, each entry naming the copy it lifted so the exact
  /// tapped twin rises when the hand holds a type twice.
  final List<PickedCard> selection;

  final Set<int> openSlots;
  final bool canMeld;

  /// The selected card can legally be thrown right now.
  final bool canDiscard;
  final bool discardGoesOut;

  /// How many cards of the opening deal have landed. Anything past this is still
  /// sitting on the stock. Pass [dealDone] to skip the animation entirely.
  final int dealt;
  final bool dealDone;

  final ZoneWords words;

  const LayoutInput({
    required this.view,
    required this.moves,
    required this.metrics,
    this.handOverride,
    required this.selection,
    required this.openSlots,
    required this.canMeld,
    required this.canDiscard,
    required this.discardGoesOut,
    required this.dealt,
    required this.dealDone,
    required this.words,
  });
}

/// Lay the table out.
TableLayout layOutTable(LayoutInput input) {
  final view = input.view;
  final words = input.words;
  final m = input.metrics;
  final cards = <CardSpot>[];
  final zones = <ZoneSpot>[];
  final melds = <MeldSpot>[];

  // --- melds, and the cards in them ---
  final myMeldsEndX = _melds(input, melds, cards);

  // --- the three zones in the middle ---
  final pileWidth = kCardWidth * kPileScale;
  final canDraw = input.moves.firstWithTarget(MoveTarget.stock) != null;
  final canTakePile = input.moves.firstWithTarget(MoveTarget.pile) != null;
  final canDiscard = input.canDiscard;

  zones.add(
    ZoneSpot(
      id: 'stock',
      x: m.stockX,
      y: m.zoneY,
      width: pileWidth + 30,
      height: m.zoneHeight,
      label: words.stock,
      foot: words.left(view.stockCount),
      hot: canDraw,
    ),
  );

  zones.add(
    ZoneSpot(
      id: 'pile',
      x: m.pileX,
      y: m.zoneY,
      width: pileWidth + 34,
      height: m.zoneHeight,
      label: words.pile,
      foot: canDiscard
          ? (input.discardGoesOut ? words.pileBatida : words.pileDiscard)
          : view.trash.isEmpty
          ? words.empty
          : words.cards(view.trash.length),
      hot: canTakePile || canDiscard,
      terminal: canDiscard && input.discardGoesOut,
    ),
  );

  // Canasta and Rummy have no morto, so the slot simply is not there.
  final hasMorto = view.mortoSizes.isNotEmpty;
  if (hasMorto) {
    final taken =
        view.side < view.mortoTaken.length && view.mortoTaken[view.side];
    zones.add(
      ZoneSpot(
        id: 'morto',
        x: m.mortoX,
        y: m.zoneY,
        width: m.mortoZoneWidth,
        height: m.zoneHeight,
        label: words.morto,
        foot: taken ? words.taken : words.waiting,
      ),
    );
  }

  // --- the play area: whatever is left of your meld row, or a band of its own
  // when your melds have taken the whole width ---
  final maxPlayX = m.playRight - m.minPlayWidth;
  final spread = m.meldStyle == MeldStyle.spread;
  final playX = spread
      ? (myMeldsEndX < maxPlayX ? myMeldsEndX : maxPlayX)
      : m.margin;
  final playRoom = m.playRight - playX;
  zones.add(
    ZoneSpot(
      id: 'play',
      x: playX,
      y: m.playY,
      width: !spread || playRoom >= m.minPlayWidth ? playRoom : m.minPlayWidth,
      height: m.playHeight,
      label: words.playArea,
      foot: input.canMeld ? words.playReady : words.playIdle,
      hot: input.canMeld,
      dashed: true,
    ),
  );

  // --- the stock: four backs read as a deck, a hundred is a hundred widgets ---
  final stockShown = view.stockCount < 4 ? view.stockCount : 4;
  for (var fromTop = 0; fromTop < stockShown; fromTop++) {
    final offset = (fromTop < 3 ? fromTop : 3) * 1.6;
    cards.add(
      CardSpot(
        // A seat cannot know the stock's contents, and the view does not carry
        // them. Every one of these is a back.
        key: 'stock:$fromTop',
        card: 0,
        x: m.stockX + 15 + offset,
        y: m.centreY + offset,
        scale: kPileScale,
        z: 10 + (4 - fromTop),
        faceUp: false,
      ),
    );
  }

  // --- the discard pile, face up, its top five suggested ---
  final trashFrom = view.trash.length < 5 ? 0 : view.trash.length - 5;
  for (var i = trashFrom; i < view.trash.length; i++) {
    final fromTop = view.trash.length - 1 - i;
    final offset = fromTop * 2.2;
    cards.add(
      CardSpot(
        key: 'pile:$i',
        card: view.trash[i],
        x: m.pileX + 17 + offset,
        y: m.centreY + offset,
        scale: kPileScale,
        z: 12 + (5 - fromTop),
        faceUp: true,
      ),
    );
  }

  // --- the mortos, yours on the left ---
  if (hasMorto) {
    for (var side = 0; side < view.mortoSizes.length; side++) {
      final size = view.mortoSizes[side];
      if (size == 0) continue;
      final baseX = m.mortoX + (side == view.side ? 12 : 58);
      final shown = size < 3 ? size : 3;
      for (var i = 0; i < shown; i++) {
        cards.add(
          CardSpot(
            key: 'morto:$side:$i',
            card: 0,
            x: baseX + i * 1.4,
            y: m.centreY + i * 1.4,
            scale: kMortoScale,
            z: 10 + i,
            faceUp: false,
          ),
        );
      }
    }
  }

  // --- your hand, and the opponents' ---
  cards.addAll(_hands(input));

  return TableLayout(cards: cards, zones: zones, melds: melds);
}

/// Both sides' melds, and every card in them. Returns where your row ended,
/// which is where a spread table puts the play area.
///
/// A row of melds is laid out the same way whatever the stage: melds in slot
/// order, left to right, sliding closer together until the row fits. What a
/// narrow stage changes is only how many rows *yours* get — your melds are drop
/// targets and have to stay tappable, so they wrap onto a second row rather than
/// compressing past legibility, while the opponent's stay on one row because
/// they are information rather than a target.
double _melds(LayoutInput input, List<MeldSpot> melds, List<CardSpot> cards) {
  final view = input.view;
  final m = input.metrics;
  var myEndX = m.margin;

  for (final mine in [false, true]) {
    final owned = mine
        ? view.myMelds
        : [
            for (final meld in view.melds)
              if (meld.owner != view.side) meld,
          ];
    final available = mine ? m.myMeldSpan : m.theirMeldSpan;
    final rows = mine ? m.myMeldRows : 1;
    // Filled evenly rather than to the brim, so nine melds read as five and four
    // rather than as a full row and a stub.
    final perRow = (owned.length + rows - 1) ~/ rows;
    final side = mine ? 'me' : 'them';

    for (var from = 0; from < owned.length; from += perRow) {
      final row = from ~/ perRow;
      final end = from + perRow;
      final inRow = owned.sublist(
        from,
        end < owned.length ? end : owned.length,
      );
      final fit = _fitRow(inRow, m, available: available);
      final cardWidth = kCardWidth * fit.scale;
      final inset = m.meldFrame / 2;
      var x = m.margin;

      for (var i = 0; i < inRow.length; i++) {
        final slot = from + i;
        final meld = inRow[i];
        final width =
            m.meldFrame + cardWidth + fit.step * _thickness(meld.size - 1, m);
        final y = (mine ? m.myRowY : m.theirRowY) + row * m.meldRowPitch;
        melds.add(
          MeldSpot(
            slot: slot,
            mine: mine,
            meld: meld,
            x: x,
            y: y,
            width: width,
            height: m.meldBoxHeightAt(fit.scale),
            compact: m.meldStyle == MeldStyle.stacked,
            open: mine && input.openSlots.contains(slot),
          ),
        );
        for (var card = 0; card < meld.cards.length; card++) {
          cards.add(
            CardSpot(
              key: 'meld:$side:$slot:$card',
              card: meld.cards[card],
              x: x + inset + _thickness(card, m) * fit.step,
              y: y + 8,
              scale: fit.scale,
              z: 20 + card,
              faceUp: true,
              asWild: meld.wildIndices.contains(card),
            ),
          );
        }
        x += width + _meldGap;
      }
      if (mine) myEndX = x;
    }
  }

  return myEndX;
}

/// The air between one meld box on a row and the next.
const double _meldGap = 8;

/// How many cards' worth of offset sit to the left of the card at [index].
///
/// A spread meld shows every card it has, so the answer is the index itself. A
/// stack shows a few cards' worth of thickness and lets the rest of the meld
/// hide under its top card: the count is printed on the box, and tapping it
/// opens the meld, so nothing is lost that the reader cannot get back.
int _thickness(int index, TableMetrics m) =>
    m.meldStyle == MeldStyle.spread || index < m.meldStackDepth
    ? index
    : m.meldStackDepth;

/// How a row of melds is drawn once it has been made to fit.
class _RowFit {
  /// How far apart the cards in a meld sit.
  final double step;

  /// How much of life size those cards are drawn at.
  final double scale;

  const _RowFit({required this.step, required this.scale});
}

/// What a row of melds has to give up to fit the table.
///
/// A side melding well can put nine melds down, and a row laid out at the full
/// spacing would run off the felt and take the melds at the end with it — the
/// stage clips, so a meld past the edge is not untidy but gone. Rather than
/// scroll, which would hide it just as effectively, the row gives ground in a
/// fixed order: the cards in every meld slide closer together, then the cards
/// themselves shrink to the size that fills the row exactly, then they slide
/// closer again at that size, because a smaller card has a smaller step to give.
/// Either stage makes all three concessions — a wide table simply holds more
/// melds before it has to reach for the second.
///
/// What no row gives up is how many cards a meld shows. That is [_thickness]'s
/// business, and it is the whole difference between the two styles: a stack
/// hides its middle and a spread meld never does, however small its cards get.
///
/// The opponent can use the full felt, but the player's row passes a narrower
/// [available] span so compression reserves the play area's tap target instead
/// of letting an otherwise valid meld box extend underneath it.
_RowFit _fitRow(
  List<MeldView> melds,
  TableMetrics m, {
  required double available,
}) {
  final tightest = _fittedStep(melds, m, m.meldScale, available);
  if (_rowWidth(melds, m, m.meldScale, tightest) <= available) {
    return _RowFit(step: tightest, scale: m.meldScale);
  }

  // Ten stacks are wider than a phone, and nine spread melds of seven wider than
  // the felt, before a single card is offset — so a row that has run out of
  // thickness to give has to give card. The scale that fills the row exactly is
  // the one where the frames, the gaps and every meld's card and thickness add
  // up to the span, reckoned at the step the row is about to be squeezed to
  // rather than the natural one: solving against a spread the row will not keep
  // leaves a slack it hands straight back, and charges the difference to the
  // cards. Anything smaller than the floor is a row that would rather overflow
  // than vanish.
  final fixed = _meldGap * (melds.length - 1) + melds.length * m.meldFrame;
  final closest = _closestStep(melds, m);
  var perScale = 0.0;
  for (final meld in melds) {
    perScale += kCardWidth * (1 + closest * _thickness(meld.size - 1, m));
  }
  final scale = ((available - fixed) / perScale).clamp(
    m.minMeldScale,
    m.meldScale,
  );
  return _RowFit(step: _fittedStep(melds, m, scale, available), scale: scale);
}

/// How wide the row comes out at a given scale and step.
double _rowWidth(
  List<MeldView> melds,
  TableMetrics m,
  double scale,
  double step,
) {
  var width = _meldGap * (melds.length - 1);
  for (final meld in melds) {
    width +=
        m.meldFrame + kCardWidth * scale + step * _thickness(meld.size - 1, m);
  }
  return width;
}

/// How close the cards in a meld are ever made to sit, as a fraction of a card.
///
/// A spread row stops at the point where a rank in the corner would start to be
/// covered. A stack has no rank to protect below its top card, so it may close
/// up to a hairline — which is the headroom that lets a phone absorb a crowded
/// row before it has to shrink anything. A row of one meld is squeezed by
/// nothing, having nothing beside it to make room for, so it keeps the natural
/// spread and is the one row whose scale is solved against that.
double _closestStep(List<MeldView> melds, TableMetrics m) => melds.length < 2
    ? m.meldOverlap
    : m.meldStyle == MeldStyle.spread
    ? _min(0.26, m.meldOverlap)
    : 0.03;

/// How far apart the cards in a meld sit, once the row has been squeezed as far
/// as it will go at [scale].
double _fittedStep(
  List<MeldView> melds,
  TableMetrics m,
  double scale,
  double available,
) {
  final cardWidth = kCardWidth * scale;
  final step = cardWidth * m.meldOverlap;
  if (melds.length < 2) return step;

  final frames =
      melds.length * (m.meldFrame + cardWidth) + _meldGap * (melds.length - 1);
  final overlapping = melds.fold(
    0,
    (sum, meld) => sum + _thickness(meld.size - 1, m),
  );
  if (overlapping == 0) return step;
  if (frames + step * overlapping <= available) return step;

  final floor = cardWidth * _closestStep(melds, m);
  final fitted = (available - frames) / overlapping;
  if (fitted < floor) return floor;
  return fitted > step ? step : fitted;
}

/// Every hand on the table, mid-deal or not.
///
/// A deal goes one card per seat per round, starting with you, so a card at index
/// `i` of seat `s`'s hand lands on tick `i * seats + order(s) + 1`. Comparing that
/// to how far the deal has got is all the animation is: an undealt card is drawn
/// on the stock, and gliding to where it belongs is what the card widget does for
/// free when its position changes.
List<CardSpot> _hands(LayoutInput input) {
  final view = input.view;
  final m = input.metrics;
  final spots = <CardSpot>[];

  final seats = [
    view.seat,
    for (var p = 0; p < view.numPlayers; p++)
      if (p != view.seat) p,
  ];

  bool landed(int order, int index) =>
      input.dealDone || input.dealt >= index * seats.length + order + 1;

  // Yours.
  final hand = input.handOverride ?? view.hand;
  final step = hand.isEmpty ? 60.0 : _min(60, m.handSpan / hand.length);
  final startX = m.size.width / 2 - (step * (hand.length - 1) + kCardWidth) / 2;
  final unpicked = [...input.selection];
  final copies = <CardId, int>{};
  for (var i = 0; i < hand.length; i++) {
    // Each selection entry names its copy, so of two identical cards exactly
    // the tapped one rises.
    final copy = copies[hand[i]] ?? 0;
    copies[hand[i]] = copy + 1;
    final picked = unpicked.remove((ct: hand[i], copy: copy));
    final spot = CardSpot(
      key: 'hand:$i',
      card: hand[i],
      x: startX + i * step,
      y: picked ? m.handY - m.handLift : m.handY,
      scale: 1,
      z: 60 + i,
      faceUp: true,
      selected: picked,
      inHand: true,
      copy: copy,
    );
    spots.add(landed(0, i) ? spot : spot.onTheStock(m));
  }

  // Theirs. One opponent gets the design's single fan on the right; a
  // four-handed table shares that band out, which keeps every hand size visible
  // without moving anything else on the table.
  final others = seats.skip(1).toList();
  final share = others.isEmpty
      ? m.opponentsWidth
      : m.opponentsWidth / others.length;

  for (var s = 0; s < others.length; s++) {
    final count = view.handSizes[others[s]];
    if (count == 0) continue;
    final theirStep = _min(22, share / count);
    final x = others.length == 1 ? m.opponentsX : m.opponentsX + s * share;
    for (var i = 0; i < count; i++) {
      final spot = CardSpot(
        key: 'seat${others[s]}:$i',
        card: 0,
        x: x + i * theirStep,
        y: m.opponentsY,
        scale: kOpponentScale,
        z: 30 + i,
        faceUp: false,
      );
      spots.add(landed(s + 1, i) ? spot : spot.onTheStock(m));
    }
  }

  return spots;
}

double _min(double a, double b) => a < b ? a : b;
