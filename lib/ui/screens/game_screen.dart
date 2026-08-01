/// The table.
///
/// The interaction model is one thing: pick cards up, and everywhere they can
/// legally go lights up. During the draw phase there is nothing in hand to pick up
/// yet, so the stock and the pile light up instead. Everything offered comes from
/// the host's legal-move list — the screen can never suggest a move the engine
/// would reject, and when a play needs more than one action the controller submits
/// them in order.
///
/// The table is laid out absolutely, in one fixed coordinate space, by
/// `table_layout.dart`. This file draws that result and nothing else, so the two
/// hard problems — where things are, and what they look like — stay apart.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../engine/cards.dart';
import '../../game/game_controller.dart';
import '../../game/move_index.dart';
import '../../game/selection_plan.dart';
import '../../multiplayer/table_view.dart';
import '../app_scope.dart';
import '../copy.dart';
import '../cues.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/lobby_view.dart';
import '../widgets/meld_box.dart';
import '../widgets/playing_card.dart';
import '../widgets/round_sheet.dart';
import '../widgets/sheet.dart';
import '../widgets/stage.dart';
import '../widgets/table_layout.dart';
import '../widgets/table_zone.dart';

/// How fast the opening deal lands, per card.
const Duration kDealTick = Duration(milliseconds: 52);

class GameScreen extends StatefulWidget {
  final GameController controller;
  const GameScreen({super.key, required this.controller});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  GameController get c => widget.controller;

  int _dealt = 0;
  Timer? _dealer;
  int _matchShown = -1;
  int _roundShown = -1;

  /// Taking a morto is a consequence rather than an action, so the event log
  /// never mentions it. Two snapshots cover the two questions asked about it: one
  /// view back, for the sound, and one turn back, for the line that says what the
  /// opponent just did.
  List<bool> _mortoLastView = const [];
  List<bool> _mortoLastTurn = const [];
  int _turnShown = -1;
  int _historyWas = 0;

  /// How many of my side's melds were canastras, so sealing a new one can be
  /// heard. Counting beats looking for a meld of exactly seven, which stays true
  /// for as long as nothing is added to it.
  int _canastrasWas = 0;

  final SoundBoard _sound = SoundBoard();
  final CardIdentityTracker _cardIdentities = CardIdentityTracker();
  bool _matchRecorded = false;
  bool _confirmLeave = false;

  /// Which meld is being read, when a stack is too narrow to read on the felt.
  ///
  /// The place rather than the cards: a meld held onto here by value would go on
  /// showing the hand it had when it was tapped, and would outlive the round it
  /// belonged to. Resolved against the live layout on every build instead, so
  /// extending the meld updates the sheet and clearing the table closes it.
  ({bool mine, int slot})? _inspecting;

  /// The toggles, opened out, when the header is too narrow to carry them.
  bool _settingsOpen = false;

  /// Captured rather than read from `context` on demand: the match result is
  /// recorded from a controller callback, which is not a build.
  late AppPrefs _prefs;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    c.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _prefs = context.prefs;
  }

  @override
  void dispose() {
    _dealer?.cancel();
    c.removeListener(_onChange);
    c.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    final view = c.view;
    if (view != null) {
      final newMatch = view.matchNumber != _matchShown;
      final newRound = newMatch || view.roundIndex != _roundShown;
      if (newRound) {
        if (newMatch) _matchShown = view.matchNumber;
        _roundShown = view.roundIndex;
        _matchRecorded = false;
        _historyWas = view.history.length;
        _canastrasWas = 0;
        _mortoLastTurn = List.of(view.mortoTaken);
        _startDeal();
      } else {
        _cueFromHistory(view);
      }
      if (view.turnNumber != _turnShown) {
        _turnShown = view.turnNumber;
        // A new round already established its own baseline above. Reusing the
        // previous view here would bring a taken morto forward from the round
        // that just ended and hide a first-turn pickup in the activity line.
        if (!newRound) _mortoLastTurn = List.of(_mortoLastView);
      }
      _mortoLastView = List.of(view.mortoTaken);
      _canastrasWas = view.myMelds.where((m) => m.isCanastra).length;
      _recordMatchOnce(view);
    }
    setState(() {});
  }

  int get _dealTotal => c.cfg.table.cardsPerPlayer * c.cfg.table.numPlayers;

  void _startDeal() {
    _dealer?.cancel();
    _cardIdentities.reset();
    _dealt = 0;
    if (Motion.reduced(context)) {
      _dealt = _dealTotal;
      return;
    }
    _dealer = Timer.periodic(kDealTick, (timer) {
      if (!mounted || _dealt >= _dealTotal) {
        timer.cancel();
        return;
      }
      setState(() => _dealt += 1);
      _sound.play(Cue.deal);
    });
  }

  /// One cue per thing that happened since the last view.
  void _cueFromHistory(TableView view) {
    _sound.enabled = _prefs.sound;
    final fresh = view.history.skip(_historyWas).toList();
    _historyWas = view.history.length;

    // A morto arriving is louder than anything in the log.
    for (var side = 0; side < view.mortoTaken.length; side++) {
      final was = side < _mortoLastView.length && _mortoLastView[side];
      if (!was && view.mortoTaken[side]) {
        _sound.play(Cue.take);
        return;
      }
    }
    if (fresh.isEmpty) return;
    // A canastra outranks whatever action completed it.
    if (view.myMelds.where((m) => m.isCanastra).length > _canastrasWas) {
      _sound.play(Cue.limpa);
      return;
    }
    // Otherwise the newest event is the one worth hearing: a bot's whole turn
    // arrives at once and should not rattle.
    switch (fresh.last.kind) {
      case 'drawTrash':
        _sound.play(Cue.take);
      case 'goOut':
      case 'endRound':
        _sound.play(Cue.out);
      case 'createSeq':
      case 'createSet':
      case 'add':
      case 'discard':
        _sound.play(Cue.snap);
      default:
        _sound.play(Cue.deal);
    }
  }

  /// The streak only moves when a match ends, and only once.
  void _recordMatchOnce(TableView view) {
    if (c.spectating || !view.matchOver || _matchRecorded) return;
    _matchRecorded = true;
    _prefs.recordMatch(won: view.winnerSide == view.side);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.prefs;
    final p = prefs.palette;
    final l = prefs.copy;
    _sound.enabled = prefs.sound;

    if (c.fatalError != null) {
      return _Message(text: c.fatalError!, palette: p, isError: true);
    }
    final view = c.view;
    if (view == null) {
      if (c.inLobby) {
        final lobbyView = LobbyView(
          controller: c,
          palette: p,
          copy: l,
          onLeave: () {
            c.leave();
            Navigator.maybePop(context);
          },
        );
        final spectators = c.lobby!.spectators;
        if (spectators == 0) return lobbyView;
        return Stack(
          fit: StackFit.expand,
          children: [
            lobbyView,
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    l.lobby.spectators(spectators),
                    style: mono(10, color: p.ashDim),
                  ),
                ),
              ),
            ),
          ],
        );
      }
      return _Message(text: '${l.deal}…', palette: p);
    }

    // The stage decides which coordinate space this table is in, so the layout
    // is computed inside it rather than guessed above it. Re-running the builder
    // is safe: the identity tracker keys off card positions in the *table*, not
    // on screen, so the same spots always come back with the same identities.
    final table = Stage(
      palette: p,
      children: (stage) {
        final m = stage.portrait
            ? TableMetrics.portrait
            : TableMetrics.landscape;
        final layout = layOutTable(
          LayoutInput(
            view: view,
            moves: c.moves,
            metrics: m,
            handOverride: prefs.handOrder == HandOrder.rank
                ? ([...view.hand]..sort(rankMajorOrder))
                : null,
            selection: c.selection,
            openSlots: c.openSlots,
            canMeld: c.canMeldSelection,
            canDiscard: c.discardMove != null,
            discardGoesOut: c.discardGoesOut,
            dealt: _dealt,
            dealDone: _dealt >= _dealTotal,
            words: _zoneWords(l),
          ),
        );
        final cards = _cardIdentities.assign(layout.cards);
        final inspected = _inspectedIn(layout);

        return [
          ..._meldBoxes(layout, p),
          ..._zones(layout, p),
          ..._rowLabels(m, l, p),
          ..._cards(cards, p),
          _header(m, view, prefs, p, l),
          _opponents(m, view, l, p),
          if (!c.spectating) _strip(m, view, l, p),
          if (!c.spectating) _handOrder(m, prefs, p, l),
          _whyNot(m, l, p),
          if (_settingsOpen)
            Positioned.fill(
              child: _SettingsSheet(
                prefs: prefs,
                palette: p,
                copy: l,
                onClose: () => setState(() => _settingsOpen = false),
              ),
            ),
          if (inspected case final meld?)
            Positioned.fill(
              child: _MeldSheet(
                meld: meld,
                palette: p,
                onClose: () => setState(() => _inspecting = null),
              ),
            ),
          // The end of a round outranks anything the player opened over the
          // table, so it comes last and covers them rather than arriving behind.
          if (view.roundOver || view.matchOver)
            Positioned.fill(
              child: RoundSheet(
                view: view,
                palette: p,
                copy: l,
                onContinue: view.matchOver ? c.rematch : c.nextRound,
              ),
            ),
          if (_confirmLeave)
            Positioned.fill(
              child: _ConfirmLeave(
                palette: p,
                copy: l,
                onStay: () => setState(() => _confirmLeave = false),
                onLeave: () => Navigator.of(context).pop(),
              ),
            ),
        ];
      },
    );

    // A finished match leaves freely; mid-match, back asks first. The
    // overlay's Leave pops imperatively, which PopScope does not intercept.
    return PopScope(
      canPop: view.matchOver,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _confirmLeave = true);
      },
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              // A reconnect must not trap the player inside the game.
              ignoring: c.reconnecting && !_confirmLeave,
              child: Opacity(opacity: c.reconnecting ? 0.55 : 1, child: table),
            ),
            if (c.reconnecting)
              IgnorePointer(
                child: Center(
                  child: Text(l.reconnecting, style: mono(10, color: p.mint)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  ZoneWords _zoneWords(Copy l) => ZoneWords(
    stock: l.stock,
    pile: l.pile,
    morto: l.morto,
    playArea: l.playArea,
    playIdle: l.playIdle,
    playReady: l.playReady,
    pileDiscard: l.pileDiscard,
    pileBatida: l.pileBatida,
    empty: l.empty,
    waiting: l.waiting,
    taken: l.taken,
    left: l.countLeft,
    cards: l.countCards,
  );

  // --- the felt ------------------------------------------------------------

  List<Widget> _meldBoxes(TableLayout layout, Palette p) => [
    for (final spot in layout.melds)
      Positioned(
        left: spot.x,
        top: spot.y,
        child: MeldBox(
          key: ValueKey('meld:${spot.mine}:${spot.slot}'),
          meld: spot.meld,
          palette: p,
          width: spot.width,
          height: spot.height,
          bonus: spot.meld.isClean
              ? c.cfg.meld.canastraBonusClean
              : c.cfg.meld.canastraBonusDirty,
          compact: spot.compact,
          open: spot.open,
          // Playing onto a meld comes first. A stack that cannot be played onto
          // is the one place a card in a meld is not visible, so tapping it
          // opens the meld instead of doing nothing.
          onTap: spot.open
              ? () => c.extendMeld(spot.slot)
              : spot.compact
              ? () => setState(
                  () => _inspecting = (mine: spot.mine, slot: spot.slot),
                )
              : null,
        ),
      ),
  ];

  MeldView? _inspectedIn(TableLayout layout) {
    final at = _inspecting;
    if (at == null) return null;
    for (final spot in layout.melds) {
      if (spot.mine == at.mine && spot.slot == at.slot) return spot.meld;
    }
    return null;
  }

  List<Widget> _zones(TableLayout layout, Palette p) => [
    for (final zone in layout.zones)
      Positioned(
        left: zone.x,
        top: zone.y,
        width: zone.width,
        height: zone.height,
        child: TableZone(
          label: zone.label,
          foot: zone.foot,
          palette: p,
          hot: zone.hot,
          dashed: zone.dashed,
          terminal: zone.terminal,
          onTap: _zoneTap(zone),
        ),
      ),
  ];

  VoidCallback? _zoneTap(ZoneSpot zone) {
    switch (zone.id) {
      case 'stock':
        final move = c.moves.firstWithTarget(MoveTarget.stock);
        return move == null ? null : () => c.play(move);
      case 'pile':
        // In the play phase the pile is where a card goes; in the draw phase it
        // is where a whole handful comes from.
        if (c.selection.length == 1 && c.view?.phase == 'play') {
          return c.discardSelection;
        }
        final take = c.moves.firstWithTarget(MoveTarget.pile);
        return take == null ? null : () => c.play(take);
      case 'play':
        return c.selection.isEmpty ? null : c.meldSelection;
      default:
        return null;
    }
  }

  List<Widget> _rowLabels(TableMetrics m, Copy l, Palette p) {
    final open = c.openSlots.length;
    return [
      Positioned(
        left: m.margin,
        top: m.theirLabelY,
        child: Text(l.theirMelds, style: mono(10, color: p.ashDim)),
      ),
      Positioned(
        left: m.margin,
        top: m.myLabelY,
        child: Row(
          children: [
            Text(l.myMelds, style: mono(10, color: p.ashDim)),
            if (open > 0) ...[
              const SizedBox(width: 10),
              Text(l.spotsOpen(open), style: mono(10, color: p.mint)),
            ],
          ],
        ),
      ),
    ];
  }

  /// Cards are drawn last within the felt and stacked by their own depth, so a
  /// hand overlaps a meld overlaps the felt. Everything except your own hand
  /// ignores taps, so clicking the pile reaches the pile rather than the card
  /// lying on it.
  List<Widget> _cards(List<CardSpot> cards, Palette p) {
    final sorted = [...cards]..sort((a, b) => a.z.compareTo(b.z));
    return [
      for (final spot in sorted)
        if (!c.spectating || !spot.inHand)
          AnimatedPositioned(
            key: ValueKey(spot.key),
            duration: Motion.of(context, Motion.glide),
            curve: Motion.glideCurve,
            left: spot.x,
            top: spot.y,
            child: AnimatedScale(
              duration: Motion.of(context, Motion.glide),
              curve: Motion.glideCurve,
              scale: spot.scale,
              alignment: Alignment.topLeft,
              child: spot.inHand
                  ? Hoverable(
                      onTap: () => c.toggleCard(spot.card),
                      builder: (_) => PlayingCard(
                        card: spot.card,
                        palette: p,
                        selected: spot.selected,
                      ),
                    )
                  : IgnorePointer(
                      child: PlayingCard(
                        card: spot.card,
                        palette: p,
                        faceDown: !spot.faceUp,
                        asWild: spot.asWild,
                      ),
                    ),
            ),
          ),
    ];
  }

  // --- chrome --------------------------------------------------------------

  Widget _header(
    TableMetrics m,
    TableView view,
    AppPrefs prefs,
    Palette p,
    Copy l,
  ) {
    final narrow = m.narrow;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: m.headerHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: m.margin),
        child: Row(
          children: [
            BackLink(
              // Narrow: the arrow alone. Every point here is a point the score
              // cannot have.
              label: l.back,
              showLabel: !narrow,
              palette: p,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            SizedBox(width: narrow ? 10 : 14),
            if (!narrow) ...[
              Hoverable(
                onTap: () => Navigator.of(context).maybePop(),
                builder: (_) => BrandMark(size: 30, palette: p, ring: 6),
              ),
              const SizedBox(width: 14),
            ],
            // Capped rather than flexible: a second flexible child would split the
            // slack with the [Spacer] and pull everything after it out of place.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: m.headerTitleWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (c.spectating)
                    Text(l.watching, style: mono(8, color: p.mint)),
                  Text(
                    view.profile.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: T.display(14, tracking: -0.4, color: p.text),
                  ),
                  Text(
                    l.roundLine(view.roundIndex + 1, view.matchTarget),
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: mono(9, color: p.ashDim, height: 1.4),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // A narrow table has room for the score and one way in to everything
            // else. The streak is on the landing screen too, and the four toggles
            // move into a sheet where they are also finally big enough to hit.
            if (narrow) ...[
              Pill(
                label: l.settings,
                palette: p,
                onTap: () => setState(() => _settingsOpen = true),
              ),
              const SizedBox(width: 12),
            ] else ...[
              if (prefs.streak > 0) ...[
                _StreakBadge(streak: prefs.streak, palette: p, copy: l),
                const SizedBox(width: 14),
              ],
              Pill(
                label: prefs.sound ? l.soundOn : l.soundOff,
                palette: p,
                round: true,
                color: prefs.sound ? p.mint : p.ashDim,
                onTap: prefs.toggleSound,
              ),
              const SizedBox(width: 6),
              Pill(
                label: prefs.lang.toggleLabel,
                palette: p,
                round: true,
                onTap: prefs.toggleLang,
              ),
              const SizedBox(width: 6),
              Pill(
                label: prefs.dark ? l.themeLight : l.themeDark,
                palette: p,
                round: true,
                onTap: prefs.toggleTheme,
              ),
              const SizedBox(width: 12),
            ],
            for (var side = 0; side < view.matchScores.length; side++)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      side == view.side ? l.you : l.them,
                      style: mono(9, color: p.ashDim),
                    ),
                    Text(
                      '${view.matchScores[side]}',
                      style: mono(
                        17,
                        color: side == view.side ? p.mint : p.ash,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Widget _flexible(bool yes, Widget child) =>
      yes ? Flexible(child: child) : child;

  Widget _opponents(TableMetrics m, TableView view, Copy l, Palette p) {
    final seats = [
      for (var seat = 0; seat < view.numPlayers; seat++)
        if (seat != view.seat) seat,
    ];
    final activity = Text(
      _activity(view, l),
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: mono(10, color: p.ash),
    );
    // Three chips leave a narrow table nothing for the activity line, so there
    // it gets the row underneath instead of a sliver of this one.
    final ownRow = m.narrow;

    // Bounded, so three opponents plus a long activity line on a four-handed
    // table run out of room rather than off the felt.
    return Positioned(
      left: m.margin,
      right: m.margin,
      top: m.seatChipsY,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final seat in seats) ...[
                // On a narrow row the three chips share it and their names give
                // way; on a wide one they keep their natural size, because the
                // activity line is the flexible child there.
                _flexible(
                  ownRow,
                  _SeatChip(
                    name: seat < view.playerNames.length
                        ? view.playerNames[seat]
                        : l.seatFallback(seat),
                    cards: view.handSizes[seat],
                    toPlay: seat == view.currentPlayer && !view.roundOver,
                    partner: seat == view.partnerSeat,
                    palette: p,
                    nameWidth: m.seatNameWidth,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (!view.myTurn && !view.roundOver) ...[
                _Thinking(label: l.thinking, palette: p),
                const SizedBox(width: 12),
              ],
              if (!ownRow) Flexible(child: activity),
            ],
          ),
          if (ownRow) ...[
            const SizedBox(height: 4),
            SizedBox(width: double.infinity, child: activity),
          ],
        ],
      ),
    );
  }

  /// What the last player to act did, in the order they did it.
  ///
  /// Shown only once it is your turn again: while they are still playing, the
  /// pulse says they are thinking, and a running commentary would be noise.
  String _activity(TableView view, Copy l) {
    if (!view.myTurn || view.history.isEmpty) return '';
    final actor = view.history.last.actor;
    if (actor == view.seat) return '';

    final turn = view.history.reversed
        .takeWhile((e) => e.actor == actor)
        .toList()
        .reversed;

    var melded = 0;
    final drew = <String>[];
    final threw = <String>[];
    for (final event in turn) {
      switch (event.kind) {
        case 'drawDeck':
          drew.add(l.drew);
        case 'drawTrash':
          drew.add(l.tookPile);
        case 'createSeq':
        case 'createSet':
        case 'add':
          // Collapsed into one count: a bot laying three runs down is one thing
          // it did, not three.
          melded += 1;
        case 'discard':
          threw.add(
            event.card == null
                ? l.discarded
                : '${l.discarded} '
                      '${event.card == kJoker ? l.joker : cardStr(event.card!)}',
          );
      }
    }

    return [
      ...drew,
      if (melded > 0) '${l.melded} $melded',
      if (_tookMortoThisTurn(view)) l.tookMorto,
      ...threw,
    ].join(' · ');
  }

  /// Whether a side other than mine picked its morto up during the turn just
  /// played.
  bool _tookMortoThisTurn(TableView view) {
    for (var side = 0; side < view.mortoTaken.length; side++) {
      if (side == view.side) continue;
      final was = side < _mortoLastTurn.length && _mortoLastTurn[side];
      if (!was && view.mortoTaken[side]) return true;
    }
    return false;
  }

  Widget _strip(TableMetrics m, TableView view, Copy l, Palette p) {
    final selected = c.selection.length;
    final actions = _stripActions(l, p);

    return Positioned(
      left: m.margin,
      right: m.margin,
      top: m.stripY,
      height: m.stripHeight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: p.strip,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: view.myTurn && !view.roundOver ? p.mint : p.line,
          ),
        ),
        child: Row(
          children: [
            if (selected > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: p.mint,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$selected ${l.selected}',
                  style: mono(10, color: p.mintInk),
                ),
              ),
              const SizedBox(width: 12),
            ],
            for (final action in actions) ...[
              action,
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                _coach(view, l),
                style: T.body(13, color: p.ash, height: 1.4),
              ),
            ),
            if (selected > 0) ...[
              const SizedBox(width: 12),
              TextLink(
                label: l.clear,
                palette: p,
                fontSize: 10,
                color: p.ashDim,
                onTap: c.clearSelection,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Keeps the way your hand is ordered directly beneath the cards it moves.
  Widget _handOrder(TableMetrics m, AppPrefs prefs, Palette p, Copy l) =>
      Positioned(
        left: 0,
        right: 0,
        top: m.handOrderY,
        height: kHandOrderHeight,
        child: Center(
          child: HandOrderToggle(
            suitLabel: l.orderBySuit,
            rankLabel: l.orderByRank,
            rankSelected: prefs.handOrder == HandOrder.rank,
            palette: p,
            onChanged: (rank) =>
                prefs.setHandOrder(rank ? HandOrder.rank : HandOrder.suit),
          ),
        ),
      );

  /// The strip carries only the moves that have nowhere on the table to be
  /// pressed: going out, and conceding a round nobody can draw in.
  List<Widget> _stripActions(Copy l, Palette p) {
    final out = c.moves.firstWithTarget(MoveTarget.goOut);
    final end = c.moves.firstWithTarget(MoveTarget.endRound);
    return [
      if (out != null)
        _StripButton(
          label: l.batida,
          palette: p,
          tone: p.gold,
          ink: p.goldInk,
          onTap: () => c.play(out),
        ),
      if (end != null)
        _StripButton(
          label: l.roundOver,
          palette: p,
          tone: Colors.transparent,
          ink: p.ash,
          onTap: () => c.play(end),
        ),
    ];
  }

  String _coach(TableView view, Copy l) {
    if (view.roundOver || view.matchOver) return '';
    if (!view.myTurn) {
      final who = view.currentPlayer < view.playerNames.length
          ? view.playerNames[view.currentPlayer]
          : '';
      return l.coachBot(who);
    }
    if (view.phase == 'draw') return l.coachDraw;
    if (c.canMeldSelection) return l.coachReady;
    if (c.selection.length == 1) return l.coachDiscard;
    return l.coachPlay;
  }

  Widget _whyNot(TableMetrics m, Copy l, Palette p) {
    final text = _refusalText(l);
    return Positioned(
      left: m.margin,
      right: m.margin,
      top: m.whyNotY,
      height: 26,
      child: text == null
          ? const SizedBox.shrink()
          : Row(
              children: [
                Text(l.whyNot, style: mono(10, color: p.pink)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: T.body(13, color: p.ash, height: 1.4),
                  ),
                ),
              ],
            ),
    );
  }

  /// The host's own words win: it knows the reason, and it phrased it. The
  /// design's sentences cover what the screen worked out for itself.
  String? _refusalText(Copy l) {
    if (c.notice != null) return c.notice;
    return switch (c.refusal) {
      null => null,
      Refusal.tooShort => l.wnShort,
      Refusal.tooManyWilds => l.wnWilds,
      Refusal.notAMeld => l.wnMixed,
      Refusal.doesNotFit => l.wnExtend,
      Refusal.needCanastra => l.wnGoOut,
      Refusal.mortoFirst => l.wnMorto,
      Refusal.notAllowedYet => l.wnNotAllowedYet,
      Refusal.justBought => l.wnJustBought,
    };
  }
}

/// The table's toggles, opened out.
///
/// On a wide table these are four pills in the header. A narrow one has no room
/// for them there, and at ten-point mono they were never really big enough to
/// hit anyway — so they become the same choice rows the setup screen already
/// uses, at the size a thumb expects.
class _SettingsSheet extends StatelessWidget {
  final AppPrefs prefs;
  final Palette palette;
  final Copy copy;
  final VoidCallback onClose;

  const _SettingsSheet({
    required this.prefs,
    required this.palette,
    required this.copy,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final l = copy;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      child: ColoredBox(
        color: p.scrim,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SheetCard(
              palette: p,
              children: [
                Text(
                  l.settingsTitle,
                  style: T.display(24, tracking: -0.8, color: p.text),
                ),
                const SizedBox(height: 20),
                ChoiceField(
                  label: l.handOrder,
                  palette: p,
                  children: [
                    Segment(
                      label: l.orderBySuit,
                      selected: prefs.handOrder == HandOrder.suit,
                      palette: p,
                      onTap: () => prefs.setHandOrder(HandOrder.suit),
                    ),
                    Segment(
                      label: l.orderByRank,
                      selected: prefs.handOrder == HandOrder.rank,
                      palette: p,
                      onTap: () => prefs.setHandOrder(HandOrder.rank),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ChoiceRow(
                  children: [
                    Segment(
                      label: prefs.sound ? l.soundOn : l.soundOff,
                      selected: prefs.sound,
                      palette: p,
                      onTap: prefs.toggleSound,
                    ),
                    Segment(
                      label: prefs.dark ? l.themeLight : l.themeDark,
                      selected: false,
                      palette: p,
                      onTap: prefs.toggleTheme,
                    ),
                    Segment(
                      label: prefs.lang.toggleLabel,
                      selected: false,
                      palette: p,
                      onTap: prefs.toggleLang,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Center(
                  child: TextLink(
                    label: l.close,
                    palette: p,
                    color: p.ashDim,
                    onTap: onClose,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A stacked meld, opened out.
///
/// On a narrow table a meld is drawn as a stack, so only its top card shows.
/// This is how you read the rest of it: the same cards at meld size, spread the
/// way a wide table would already have shown them. Read-only — everything you
/// can *do* to a meld is still done by tapping it on the felt.
class _MeldSheet extends StatelessWidget {
  final MeldView meld;
  final Palette palette;
  final VoidCallback onClose;

  const _MeldSheet({
    required this.meld,
    required this.palette,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final l = context.copy;
    final scale = TableMetrics.landscape.meldScale;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      child: ColoredBox(
        color: p.scrim,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              decoration: BoxDecoration(
                color: p.sheet,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: p.line),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        meldLabel(meld),
                        style: mono(10, color: p.ash, tracking: 1.4),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${meld.points}',
                        style: mono(
                          10,
                          color: meld.isCanastra
                              ? (meld.isClean ? p.gold : p.pink)
                              : p.ashDim,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (var i = 0; i < meld.cards.length; i++)
                        SizedBox(
                          width: kCardWidth * scale,
                          height: kCardHeight * scale,
                          child: FittedBox(
                            child: PlayingCard(
                              card: meld.cards[i],
                              palette: p,
                              asWild: meld.wildIndices.contains(i),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: TextLink(
                      label: l.close,
                      palette: p,
                      color: p.ashDim,
                      onTap: onClose,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks before a match in progress is walked away from. Staying is the mint
/// button; leaving is a bare word in the colour the app uses for "watch out".
class _ConfirmLeave extends StatelessWidget {
  final Palette palette;
  final Copy copy;
  final VoidCallback onStay;
  final VoidCallback onLeave;

  const _ConfirmLeave({
    required this.palette,
    required this.copy,
    required this.onStay,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: ColoredBox(
        color: p.scrim,
        child: Center(
          child: Container(
            width: 380,
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 26),
            decoration: BoxDecoration(
              color: p.sheet,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: p.line),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  copy.leaveTitle,
                  style: T.display(24, tracking: -0.8, color: p.text),
                ),
                const SizedBox(height: 22),
                MintButton(label: copy.leaveStay, palette: p, onTap: onStay),
                const SizedBox(height: 16),
                Center(
                  child: TextLink(
                    label: copy.leaveConfirm,
                    palette: p,
                    color: p.pink,
                    onTap: onLeave,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StreakBadge extends StatelessWidget {
  final int streak;
  final Palette palette;
  final Copy copy;

  const _StreakBadge({
    required this.streak,
    required this.palette,
    required this.copy,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: p.goldWash,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: p.goldLine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: p.gold,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text('${copy.streak}$streak', style: mono(10, color: p.gold)),
        ],
      ),
    );
  }
}

/// An opponent, with the signal that matters most: how many cards they are
/// holding. One card means they are about to go out.
class _SeatChip extends StatelessWidget {
  final String name;
  final int cards;
  final bool toPlay;
  final bool partner;
  final Palette palette;

  /// How much room the name may take. Online names come from players, so on a
  /// narrow table three of them would otherwise push the card counts off the
  /// felt.
  final double nameWidth;

  const _SeatChip({
    required this.name,
    required this.cards,
    required this.toPlay,
    required this.partner,
    required this.palette,
    required this.nameWidth,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return AnimatedContainer(
      duration: Motion.of(context, Motion.base),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: toPlay ? p.mint : p.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: partner ? p.mint : p.avatar,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: mono(10, color: partner ? p.mintInk : p.avatarInk),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: nameWidth),
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: T.title(13, color: p.text),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Two cards or fewer is a threat, and the wild colour is the app's
          // word for "watch out".
          Text(
            '$cards',
            style: mono(13, color: cards <= 2 ? p.pink : p.ashDim),
          ),
        ],
      ),
    );
  }
}

class _Thinking extends StatefulWidget {
  final String label;
  final Palette palette;

  const _Thinking({required this.label, required this.palette});

  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  // Reduce-motion comes from the MediaQuery, which cannot be read until
  // dependencies are in place — so the pulse starts here rather than in
  // initState, and only once.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _pulse.stop();
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.55,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: p.mint,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 5),
          Text(widget.label, style: mono(10, color: p.mint)),
        ],
      ),
    );
  }
}

class _StripButton extends StatelessWidget {
  final String label;
  final Palette palette;
  final Color tone;
  final Color ink;
  final VoidCallback onTap;

  const _StripButton({
    required this.label,
    required this.palette,
    required this.tone,
    required this.ink,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: Hoverable(
      onTap: onTap,
      builder: (hovered) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: tone == Colors.transparent
              ? Colors.transparent
              : (hovered ? brighten(tone, 1.1) : tone),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: tone == Colors.transparent ? palette.line : tone,
          ),
        ),
        child: Text(label, style: mono(11, color: ink)),
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  final String text;
  final Palette palette;
  final bool isError;

  const _Message({
    required this.text,
    required this.palette,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Room(
      palette: palette,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: T.title(16, color: isError ? palette.pink : palette.ash),
          ),
        ),
      ),
    ),
  );
}
