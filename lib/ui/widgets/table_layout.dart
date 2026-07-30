/// Where everything on the table is.
///
/// One pass computes a position for every card, zone and meld box in stage
/// coordinates, and the screen does nothing but draw the result. Keeping it apart
/// from the widgets is what makes the table cheap to animate: a card is the same
/// widget at a new position from one frame to the next, so it glides instead of
/// being rebuilt somewhere else — and the geometry can be reasoned about, or
/// tested, without pumping a single frame.
///
/// Every number here is a stage coordinate, and the stage is always 1240 × 790.
library;

import '../../engine/cards.dart';
import '../../game/move_index.dart';
import '../../multiplayer/table_view.dart';
import 'playing_card.dart';

/// How much of life size a card is drawn at, per place it can be.
const double kMeldScale = 0.575;
const double kPileScale = 0.72;
const double kMortoScale = 0.52;
const double kOpponentScale = 0.42;

const double _meldWidth = kCardWidth * kMeldScale;
const double _meldStep = _meldWidth * 0.42;
const double _meldHeight = kCardHeight * kMeldScale;

/// A meld box is its cards plus room for its name underneath.
const double kMeldBoxHeight = _meldHeight + 26;

/// The rows the two sides' melds live on, and the labels above them.
const double kTheirRowY = 116;
const double kMyRowY = 358;
const double kTheirLabelY = 102;
const double kMyLabelY = 340;

/// The middle of the table.
const double kCentreY = 232;
const double kStockX = 452;
const double kPileX = 566;
const double kMortoX = 686;
const double kZoneY = kCentreY - 22;
const double kZoneHeight = kCardHeight * kPileScale + 56;

/// The action strip and the line beneath it.
const double kStripY = 462;
const double kStripHeight = 46;
const double kWhyNotY = 518;

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
  );

  CardSpot onTheStock() => CardSpot(
    key: key,
    card: card,
    x: kStockX + 15,
    y: kCentreY,
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

  /// The selection would fit here.
  final bool open;

  const MeldSpot({
    required this.slot,
    required this.mine,
    required this.meld,
    required this.x,
    required this.y,
    required this.width,
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

/// What the screen tells the layout that the view does not already say.
class LayoutInput {
  final TableView view;
  final MoveIndex moves;

  final List<CardId> selection;
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
  final cards = <CardSpot>[];
  final zones = <ZoneSpot>[];
  final melds = <MeldSpot>[];

  // --- melds, and the cards in them ---
  var myMeldsEndX = 20.0;
  for (final mine in [false, true]) {
    final rowY = mine ? kMyRowY : kTheirRowY;
    final owned = mine
        ? view.myMelds
        : [
            for (final m in view.melds)
              if (m.owner != view.side) m,
          ];
    final step = _fittedStep(owned, available: mine ? 1010 : 1200);
    var x = 20.0;
    for (var slot = 0; slot < owned.length; slot++) {
      final meld = owned[slot];
      final width = 18 + _meldWidth + step * (meld.size - 1);
      final side = mine ? 'me' : 'them';
      melds.add(
        MeldSpot(
          slot: slot,
          mine: mine,
          meld: meld,
          x: x,
          y: rowY,
          width: width,
          open: mine && input.openSlots.contains(slot),
        ),
      );
      for (var i = 0; i < meld.cards.length; i++) {
        cards.add(
          CardSpot(
            key: 'meld:$side:$slot:$i',
            card: meld.cards[i],
            x: x + 9 + i * step,
            y: rowY + 8,
            scale: kMeldScale,
            z: 20 + i,
            faceUp: true,
            asWild: meld.wildIndices.contains(i),
          ),
        );
      }
      x += width + 8;
    }
    if (mine) myMeldsEndX = x;
  }

  // --- the three zones in the middle ---
  final pileWidth = kCardWidth * kPileScale;
  final canDraw = input.moves.firstWithTarget(MoveTarget.stock) != null;
  final canTakePile = input.moves.firstWithTarget(MoveTarget.pile) != null;
  final canDiscard = input.canDiscard;

  zones.add(
    ZoneSpot(
      id: 'stock',
      x: kStockX,
      y: kZoneY,
      width: pileWidth + 30,
      height: kZoneHeight,
      label: words.stock,
      foot: words.left(view.stockCount),
      hot: canDraw,
    ),
  );

  zones.add(
    ZoneSpot(
      id: 'pile',
      x: kPileX,
      y: kZoneY,
      width: pileWidth + 34,
      height: kZoneHeight,
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
        x: kMortoX,
        y: kZoneY,
        width: 106,
        height: kZoneHeight,
        label: words.morto,
        foot: taken ? words.taken : words.waiting,
      ),
    );
  }

  // --- the play area: whatever is left of your meld row ---
  const minPlayWidth = 190.0;
  const maxPlayX = 1240.0 - minPlayWidth;
  final playX = myMeldsEndX < maxPlayX ? myMeldsEndX : maxPlayX;
  zones.add(
    ZoneSpot(
      id: 'play',
      x: playX,
      y: kMyRowY,
      width: (1220 - playX) < minPlayWidth ? minPlayWidth : 1220 - playX,
      height: kMeldBoxHeight,
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
        x: kStockX + 15 + offset,
        y: kCentreY + offset,
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
        x: kPileX + 17 + offset,
        y: kCentreY + offset,
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
      final baseX = kMortoX + (side == view.side ? 12 : 58);
      final shown = size < 3 ? size : 3;
      for (var i = 0; i < shown; i++) {
        cards.add(
          CardSpot(
            key: 'morto:$side:$i',
            card: 0,
            x: baseX + i * 1.4,
            y: kCentreY + i * 1.4,
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

/// How far apart the cards in a meld sit, so a whole row of them fits the table.
///
/// A side melding well can put nine melds down, and a row laid out at the full
/// spacing would run off the felt and take the melds at the end with it. Rather
/// than scroll — which would hide them just as effectively — the cards in every
/// meld on the row slide closer together until the row fits. They stop at the
/// point where a rank in the corner would start to be covered; past that, a table
/// this crowded is allowed to overflow rather than become unreadable.
///
/// The opponent can use the full felt, but the player's row passes a narrower
/// [available] span so compression reserves the play area's tap target instead
/// of letting an otherwise valid meld box extend underneath it.
double _fittedStep(List<MeldView> melds, {double available = 1200}) {
  if (melds.length < 2) return _meldStep;

  const gap = 8.0;
  final frames = melds.length * (18 + _meldWidth) + gap * (melds.length - 1);
  final overlapping = melds.fold(0, (sum, m) => sum + m.size - 1);
  if (overlapping == 0) return _meldStep;
  if (frames + _meldStep * overlapping <= available) return _meldStep;

  const floor = _meldWidth * 0.26;
  final fitted = (available - frames) / overlapping;
  if (fitted < floor) return floor;
  return fitted > _meldStep ? _meldStep : fitted;
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
  final spots = <CardSpot>[];

  final seats = [
    view.seat,
    for (var p = 0; p < view.numPlayers; p++)
      if (p != view.seat) p,
  ];

  bool landed(int order, int index) =>
      input.dealDone || input.dealt >= index * seats.length + order + 1;

  // Yours.
  final hand = view.hand;
  final step = hand.isEmpty ? 60.0 : _min(60, 1160 / hand.length);
  final startX = 620 - (step * (hand.length - 1) + kCardWidth) / 2;
  final unpicked = [...input.selection];
  for (var i = 0; i < hand.length; i++) {
    // Selection is by card type and a type can be held twice, so the first
    // copies encountered are the picked-up ones.
    final picked = unpicked.remove(hand[i]);
    final spot = CardSpot(
      key: 'hand:$i',
      card: hand[i],
      x: startX + i * step,
      y: picked ? 574 : 596,
      scale: 1,
      z: 60 + i,
      faceUp: true,
      selected: picked,
      inHand: true,
    );
    spots.add(landed(0, i) ? spot : spot.onTheStock());
  }

  // Theirs. One opponent gets the design's single fan on the right; a
  // four-handed table shares that band out, which keeps every hand size visible
  // without moving anything else on the table.
  const bandStart = 962.0;
  const bandWidth = 236.0;
  final others = seats.skip(1).toList();
  final share = others.isEmpty ? bandWidth : bandWidth / others.length;

  for (var s = 0; s < others.length; s++) {
    final count = view.handSizes[others[s]];
    if (count == 0) continue;
    final theirStep = _min(22, share / count);
    final x = others.length == 1 ? bandStart : bandStart + s * share;
    for (var i = 0; i < count; i++) {
      final spot = CardSpot(
        key: 'seat${others[s]}:$i',
        card: 0,
        x: x + i * theirStep,
        y: 62,
        scale: kOpponentScale,
        z: 30 + i,
        faceUp: false,
      );
      spots.add(landed(s + 1, i) ? spot : spot.onTheStock());
    }
  }

  return spots;
}

double _min(double a, double b) => a < b ? a : b;
