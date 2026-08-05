/// The table.
///
/// The interaction model is one thing: pick cards up, and everywhere they can
/// legally go lights up. During the draw phase there is nothing in hand to pick up
/// yet, so the stock and the pile light up instead. Everything offered comes from
/// the host's legal-move list — the screen can never suggest a move the engine
/// would reject, and when a play needs more than one action the controller submits
/// them in order.
///
/// The table is solved against the safe viewport by `table_solver.dart`. This
/// file draws that result and nothing else, so the two hard problems — where
/// things are, and what they look like — stay apart.
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
import '../widgets/table_layout.dart'
    show CardIdentityTracker, CardSpot, rankMajorOrder;
import '../widgets/table_solver.dart';
import '../widgets/table_zone.dart';

/// How fast the opening deal lands, per card.
const Duration kDealTick = Duration(milliseconds: 52);

const double _kMeldSheetCardScale = 0.575;

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
  Size? _lastViewport;
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

    // The solver works in the real safe viewport. The identity tracker remains
    // a build-time cache: it rewrites positional observations into the stable
    // keys that let the same physical card glide between zones.
    final table = FluidStage(
      palette: p,
      builder: (viewport) {
        final input = TableSolverInput(
          viewport: viewport,
          view: view,
          selection: c.picked,
          openSlots: c.openSlots,
          dealt: _dealt,
          dealDone: _dealt >= _dealTotal,
          meldLabeler: (m) => shortMeldLabel(prefs.lang, m),
          handOverride: prefs.handOrder == HandOrder.rank
              ? ([...view.hand]..sort(rankMajorOrder))
              : null,
        );
        final solution = solveTable(input);
        final instant =
            _lastViewport != null && _lastViewport != solution.viewport;
        _lastViewport = solution.viewport;
        final cards = _cardIdentities.assign(solution.cards);
        final inspected = _inspectedIn(solution);

        return Stack(
          fit: StackFit.expand,
          children: [
            ..._meldBoxes(solution, p),
            ..._pileZones(solution, view, l, p),
            _newMeldSlot(solution, l, p),
            ..._cards(cards, p, instant),
            _header(solution, view, prefs, p, l),
            _theirStrip(solution, view, l, p),
            if (!c.spectating) _myStrip(solution, view, l, p),
            _handOrder(solution, prefs, p, l),
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
          ],
        );
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

  // --- the felt ------------------------------------------------------------

  List<Widget> _meldBoxes(TableSolution solution, Palette p) => [
    for (final meld in solution.melds)
      Positioned.fromRect(
        key: ValueKey('meld:${meld.mine}:${meld.slot}'),
        rect: meld.rect,
        child: MeldBox(
          meld: meld.meld,
          palette: p,
          width: meld.rect.width,
          height: meld.rect.height,
          meldCardWidth: solution.mcw,
          captionFontSize: meld.captionFontSize,
          bonus: meld.meld.isClean
              ? c.cfg.meld.canastraBonusClean
              : c.cfg.meld.canastraBonusDirty,
          compact: solution.stackedMelds,
          open: meld.hot,
          // Playing onto a meld comes first. A stack that cannot be played onto
          // is the one place a card in a meld is not visible, so tapping it
          // opens the meld instead of doing nothing.
          onTap: meld.hot
              ? () => c.extendMeld(meld.slot)
              : solution.stackedMelds
              ? () => setState(
                  () => _inspecting = (mine: meld.mine, slot: meld.slot),
                )
              : null,
        ),
      ),
  ];

  MeldView? _inspectedIn(TableSolution solution) {
    final at = _inspecting;
    if (at == null) return null;
    for (final meld in solution.melds) {
      if (meld.mine == at.mine && meld.slot == at.slot) return meld.meld;
    }
    return null;
  }

  List<Widget> _pileZones(
    TableSolution solution,
    TableView view,
    Copy l,
    Palette p,
  ) {
    final zones = <Widget>[];

    void zone(
      PileSolution pile, {
      required String label,
      required String foot,
      required bool hot,
      required bool terminal,
      VoidCallback? onTap,
    }) {
      zones.add(
        Positioned.fromRect(
          rect: pile.box,
          child: TableZone(
            label: label,
            foot: foot,
            palette: p,
            hot: hot,
            terminal: terminal,
            horizontalText: pile.horizontal,
            zoneCardWidth: solution.pileCardWidth,
            onTap: onTap,
          ),
        ),
      );
    }

    final stockMove = c.moves.firstWithTarget(MoveTarget.stock);
    zone(
      solution.stock,
      label: l.stock,
      foot: l.countLeft(view.stockCount),
      hot: stockMove != null,
      terminal: false,
      onTap: stockMove == null ? null : () => c.play(stockMove),
    );

    final canDiscard = c.discardMove != null;
    final takePile = c.moves.firstWithTarget(MoveTarget.pile);
    VoidCallback? pileTap;
    if (canDiscard || takePile != null) {
      pileTap = () {
        if (c.selection.length == 1 && view.phase == 'play') {
          c.discardSelection();
          return;
        }
        final take = c.moves.firstWithTarget(MoveTarget.pile);
        if (take != null) c.play(take);
      };
    }
    zone(
      solution.discard,
      label: l.pile,
      foot: canDiscard
          ? (c.discardGoesOut ? l.pileBatida : l.pileDiscard)
          : view.trash.isEmpty
          ? l.empty
          : l.countCards(view.trash.length),
      hot: takePile != null || canDiscard,
      terminal: canDiscard && c.discardGoesOut,
      onTap: pileTap,
    );

    if (solution.mortos.isNotEmpty) {
      final taken =
          view.side < view.mortoTaken.length && view.mortoTaken[view.side];
      zone(
        solution.mortos.first,
        label: l.morto,
        foot: taken ? l.taken : l.waiting,
        hot: false,
        terminal: false,
      );
    }
    return zones;
  }

  Widget _newMeldSlot(TableSolution solution, Copy l, Palette p) =>
      Positioned.fromRect(
        rect: solution.newMeldSlot,
        child: TableZone(
          label: l.newMeldLabel,
          foot: c.canMeldSelection ? l.playReady : l.playIdle,
          palette: p,
          hot: c.canMeldSelection,
          dashed: true,
          zoneCardWidth: solution.mcw,
          onTap: c.selection.isEmpty ? null : c.meldSelection,
        ),
      );

  /// Cards are drawn last within the felt and stacked by their own depth, so a
  /// hand overlaps a meld overlaps the felt. Everything except your own hand
  /// ignores taps, so clicking the pile reaches the pile rather than the card
  /// lying on it.
  List<Widget> _cards(List<CardSpot> cards, Palette p, bool instant) {
    final duration = instant ? Duration.zero : Motion.of(context, Motion.glide);
    final sorted = [...cards]..sort((a, b) => a.z.compareTo(b.z));
    return [
      for (final spot in sorted)
        if (!c.spectating || !spot.inHand)
          AnimatedPositioned(
            key: ValueKey(spot.key),
            duration: duration,
            curve: Motion.glideCurve,
            left: spot.x,
            top: spot.y,
            child: AnimatedScale(
              duration: duration,
              curve: Motion.glideCurve,
              scale: spot.scale,
              alignment: Alignment.topLeft,
              child: spot.inHand
                  ? Hoverable(
                      onTap: () => c.toggleCard(
                        spot.card,
                        selected: spot.selected,
                        copy: spot.copy,
                      ),
                      builder: (_) => PlayingCard(
                        card: spot.card,
                        palette: p,
                        selected: spot.selected,
                        renderScale: spot.scale,
                      ),
                    )
                  : IgnorePointer(
                      child: PlayingCard(
                        card: spot.card,
                        palette: p,
                        faceDown: !spot.faceUp,
                        asWild: spot.asWild,
                        flat: true,
                        renderScale: spot.scale,
                      ),
                    ),
            ),
          ),
    ];
  }

  // --- chrome --------------------------------------------------------------

  Widget _header(
    TableSolution solution,
    TableView view,
    AppPrefs prefs,
    Palette p,
    Copy l,
  ) {
    final fonts = solution.fonts;
    final gap = solution.veryTight ? 4.0 : 10.0;
    return Positioned.fromRect(
      rect: solution.header,
      child: Row(
        children: [
          SizedBox(
            key: ValueKey('back-${solution.veryTight}'),
            width: solution.veryTight
                ? fonts.backButtonSize
                : fonts.backButtonSize * 2.2,
            height: fonts.backButtonSize,
            child: FittedBox(
              fit: BoxFit.contain,
              child: BackLink(
                boxed: true,
                label: l.back,
                showLabel: !solution.veryTight,
                palette: p,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
          SizedBox(width: gap),
          // Keeping the dynamic title widget mounted at zero width preserves a
          // single header structure across resize while hiding it visually on
          // the very-tight rung of the solver.
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: solution.veryTight ? 0 : null,
                child: ExcludeSemantics(
                  excluding: solution.veryTight,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (c.spectating)
                        Text(
                          l.watching,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: mono(fonts.brandSubFs, color: p.mint),
                        ),
                      Text(
                        view.profile.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: T.display(
                          fonts.brandNameFs,
                          tracking: -0.4,
                          color: p.text,
                        ),
                      ),
                      if (!solution.tight)
                        Text(
                          l.roundLine(view.roundIndex + 1, view.matchTarget),
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: mono(
                            fonts.brandSubFs,
                            color: p.ashDim,
                            height: 1.25,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: gap),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _turnPill(solution, view, l, p),
                  SizedBox(width: gap),
                  _scoreRow(solution, view, l, p),
                  if (prefs.streak > 0) ...[
                    SizedBox(width: gap),
                    _StreakBadge(streak: prefs.streak, palette: p, copy: l),
                  ],
                  SizedBox(width: gap),
                  Pill(
                    label: l.settings,
                    palette: p,
                    round: true,
                    onTap: () => setState(() => _settingsOpen = true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _turnPill(TableSolution solution, TableView view, Copy l, Palette p) {
    final mine = view.myTurn;
    final who = view.currentPlayer < view.playerNames.length
        ? view.playerNames[view.currentPlayer]
        : l.seatFallback(view.currentPlayer);
    return Semantics(
      label: mine ? l.yourTurn : '$who, ${l.thinking}',
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: solution.veryTight ? 100 : 190),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: solution.veryTight ? 7 : 10,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: mine ? p.mint : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: mine ? null : Border.all(color: p.line),
          ),
          child: mine
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: solution.fonts.turnDotSize,
                      height: solution.fonts.turnDotSize,
                      decoration: BoxDecoration(
                        color: p.mintInk,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        l.yourTurn,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: mono(solution.fonts.turnFs, color: p.mintInk),
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        who,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: mono(solution.fonts.turnFs, color: p.ash),
                      ),
                    ),
                    if (!view.roundOver) ...[
                      const SizedBox(width: 6),
                      _Thinking(label: l.thinking, palette: p),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _scoreRow(TableSolution solution, TableView view, Copy l, Palette p) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var side = 0; side < view.matchScores.length; side++) ...[
            if (side > 0)
              Container(
                width: 1,
                height: solution.fonts.scoreValueFs * 1.15,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: p.line,
              ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    side == view.side ? l.you : l.them,
                    style: mono(
                      solution.fonts.scoreLabelFs,
                      color: side == view.side ? p.mint : p.ashDim,
                      height: 1,
                    ),
                  ),
                  Text(
                    '${view.matchScores[side]}',
                    style: mono(
                      solution.fonts.scoreValueFs,
                      color: side == view.side ? p.mint : p.text,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      );

  Widget _theirStrip(
    TableSolution solution,
    TableView view,
    Copy l,
    Palette p,
  ) {
    final seats = [
      for (final anchor in solution.seatAnchors)
        if (anchor.band == SeatAnchorBand.theirStrip) anchor.seat,
    ];
    return Positioned.fromRect(
      rect: solution.theirStrip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: p.strip,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.line),
        ),
        child: Row(
          children: [
            for (var i = 0; i < seats.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Flexible(
                child: _SeatChip(
                  name: seats[i] < view.playerNames.length
                      ? view.playerNames[seats[i]]
                      : l.seatFallback(seats[i]),
                  cards: seats[i] < view.handSizes.length
                      ? view.handSizes[seats[i]]
                      : 0,
                  toPlay: seats[i] == view.currentPlayer && !view.roundOver,
                  partner: false,
                  palette: p,
                  avatarSize: solution.fonts.avatarSize,
                  nameFontSize: solution.fonts.nameFs,
                  metaFontSize: solution.fonts.seatMetaFs,
                  semanticsLabel:
                      '${seats[i] < view.playerNames.length ? view.playerNames[seats[i]] : l.seatFallback(seats[i])}, '
                      '${l.countCards(seats[i] < view.handSizes.length ? view.handSizes[seats[i]] : 0)}'
                      '${seats[i] == view.currentPlayer && !view.roundOver ? ', ${l.thinking}' : ''}',
                ),
              ),
            ],
            if (!view.myTurn && !view.roundOver) ...[
              const SizedBox(width: 6),
              if (!solution.tight) _Thinking(label: l.thinking, palette: p),
            ],
            if (!solution.tight) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _activity(view, l),
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: mono(solution.fonts.seatMetaFs, color: p.ash),
                ),
              ),
            ],
          ],
        ),
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

  Widget _myStrip(TableSolution solution, TableView view, Copy l, Palette p) {
    final partnerSeat = view.numPlayers == 4
        ? view.partnerSeat ?? (view.seat + 2) % view.numPlayers
        : null;
    final refusal = _refusalText(l);
    final coach = refusal == null ? _coach(view, l) : '${l.whyNot}: $refusal';
    final coachColor = refusal != null
        ? p.pink
        : c.selection.isNotEmpty
        ? p.text
        : p.ashDim;
    final actions = _stripActions(solution, l, p);

    final identity = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: solution.fonts.avatarSize,
          height: solution.fonts.avatarSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: p.mint, shape: BoxShape.circle),
          child: Text(
            l.you.characters.first,
            style: mono(solution.fonts.seatMetaFs, color: p.mintInk),
          ),
        ),
        const SizedBox(width: 7),
        Text(l.you, style: T.title(solution.fonts.nameFs, color: p.text)),
        if (partnerSeat != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: _SeatChip(
              name: partnerSeat < view.playerNames.length
                  ? view.playerNames[partnerSeat]
                  : l.seatFallback(partnerSeat),
              cards: partnerSeat < view.handSizes.length
                  ? view.handSizes[partnerSeat]
                  : 0,
              toPlay: partnerSeat == view.currentPlayer && !view.roundOver,
              partner: true,
              palette: p,
              avatarSize: solution.fonts.avatarSize,
              nameFontSize: solution.fonts.nameFs,
              metaFontSize: solution.fonts.seatMetaFs,
              semanticsLabel:
                  '${partnerSeat < view.playerNames.length ? view.playerNames[partnerSeat] : l.seatFallback(partnerSeat)}, '
                  '${l.countCards(partnerSeat < view.handSizes.length ? view.handSizes[partnerSeat] : 0)}'
                  '${partnerSeat == view.currentPlayer && !view.roundOver ? ', ${l.thinking}' : ''}',
            ),
          ),
        ],
      ],
    );
    final coachText = Text(
      coach,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: T.body(solution.fonts.coachFs, color: coachColor, height: 1.2),
    );

    return Positioned.fromRect(
      rect: solution.myStrip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: p.strip,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: view.myTurn && !view.roundOver ? p.mint : p.line,
          ),
        ),
        child: solution.narrowAct
            ? Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(child: identity),
                        const SizedBox(width: 8),
                        Expanded(child: coachText),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: actions,
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Flexible(child: identity),
                  const SizedBox(width: 10),
                  Expanded(child: coachText),
                  const SizedBox(width: 10),
                  ...actions,
                ],
              ),
      ),
    );
  }

  List<Widget> _stripActions(TableSolution solution, Copy l, Palette p) {
    final selected = c.selection.length;
    final out = c.moves.firstWithTarget(MoveTarget.goOut);
    final end = c.moves.firstWithTarget(MoveTarget.endRound);
    final actions = <Widget>[];

    void add(Widget action) {
      if (actions.isNotEmpty) actions.add(const SizedBox(width: 8));
      actions.add(action);
    }

    if (selected > 0) {
      add(
        Pill(
          filled: true,
          round: true,
          label: '$selected ${l.selected}',
          palette: p,
          onTap: c.clearSelection,
        ),
      );
      add(
        TextLink(
          label: l.clear,
          palette: p,
          fontSize: solution.fonts.chipFs,
          color: p.ashDim,
          onTap: c.clearSelection,
        ),
      );
    }
    if (out != null) {
      add(
        GoldButton(
          outline: true,
          label: l.batida,
          palette: p,
          fontSize: solution.fonts.chipFs,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          onTap: () => c.play(out),
        ),
      );
    }
    if (end != null) {
      add(
        _StripButton(
          label: l.roundOver,
          palette: p,
          tone: Colors.transparent,
          ink: p.ash,
          onTap: () => c.play(end),
        ),
      );
    }
    return actions;
  }

  /// Keeps the way your hand is ordered directly beneath the cards it moves.
  Widget _handOrder(
    TableSolution solution,
    AppPrefs prefs,
    Palette p,
    Copy l,
  ) => Positioned.fromRect(
    rect: solution.handOrderToggle,
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
/// The header always folds these into the same choice rows the setup screen
/// already uses, at the size a thumb expects.
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
          child: SingleChildScrollView(
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
    const scale = _kMeldSheetCardScale;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      child: ColoredBox(
        color: p.scrim,
        child: Center(
          child: SingleChildScrollView(
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
          child: SingleChildScrollView(
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
  final double avatarSize;
  final double nameFontSize;
  final double metaFontSize;
  final String semanticsLabel;

  const _SeatChip({
    required this.name,
    required this.cards,
    required this.toPlay,
    required this.partner,
    required this.palette,
    required this.avatarSize,
    required this.nameFontSize,
    required this.metaFontSize,
    required this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.base),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: toPlay ? p.mint : p.line),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: avatarSize,
                height: avatarSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: partner ? p.mint : p.avatar,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                  style: mono(
                    metaFontSize,
                    color: partner ? p.mintInk : p.avatarInk,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: T.title(nameFontSize, color: p.text),
                ),
              ),
              const SizedBox(width: 6),
              // Two cards or fewer is a threat, and the wild colour is the app's
              // word for "watch out".
              Text(
                '$cards',
                style: mono(
                  metaFontSize,
                  color: cards <= 2 ? p.pink : p.ashDim,
                ),
              ),
            ],
          ),
        ),
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
