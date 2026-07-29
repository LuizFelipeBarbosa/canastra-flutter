/// The table.
///
/// The interaction model is one thing: pick up a card, and everywhere it can
/// legally go lights up. During the draw phase there is nothing in hand to pick
/// up, so the stock and the pile light up instead. Everything offered comes
/// from the host's legal-move list, so the screen can never suggest a move the
/// engine would reject.
library;

import 'package:flutter/material.dart';

import '../../engine/cards.dart';
import '../../game/game_controller.dart';
import '../../game/move_index.dart';
import '../../multiplayer/table_view.dart';
import '../theme.dart';
import '../widgets/card_label.dart';
import '../widgets/hand_fan.dart';
import '../widgets/meld_strip.dart';
import '../widgets/playing_card.dart';
import '../widgets/round_sheet.dart';
import '../widgets/table_center.dart';
import '../widgets/table_surface.dart';

class GameScreen extends StatefulWidget {
  final GameController controller;
  const GameScreen({super.key, required this.controller});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  GameController get c => widget.controller;
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    c.start();
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    final view = c.view;
    if (view != null && (view.roundOver || view.matchOver) && !_sheetOpen) {
      _sheetOpen = true;
      // Let the final table state paint before the sheet covers it.
      Future<void>.delayed(const Duration(milliseconds: 450), _showRoundSheet);
    }
  }

  Future<void> _showRoundSheet() async {
    final view = c.view;
    if (!mounted || view == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => SingleChildScrollView(
        child: RoundSheet(
          view: view,
          onContinue: () {
            Navigator.of(context).pop();
            view.matchOver ? c.rematch() : c.nextRound();
          },
        ),
      ),
    );
    _sheetOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    if (c.fatalError != null) {
      return _Message(text: c.fatalError!, isError: true);
    }
    final view = c.view;
    if (view == null) return const _Message(text: 'Dealing…');

    return Scaffold(
      body: TableSurface(
        child: SafeArea(
          // A card table does not get better by being 2000px wide; past this
          // the layout centres and the felt keeps a hand's worth of scale.
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  _TopBar(
                    view: view,
                    onLeave: () => Navigator.of(context).maybePop(),
                  ),
                  _SeatRow(view: view),
                  Expanded(
                    child: _Felt(controller: c, view: view),
                  ),
                  if (c.notice != null)
                    _Notice(text: c.notice!, onDismiss: c.dismissNotice),
                  _ActionBar(controller: c, view: view),
                  HandFan(
                    cards: view.hand,
                    selected: c.selectedCard,
                    playable: c.moves.playableCards,
                    markUnplayable: view.phase == 'play',
                    onTap: (card) => c.selectCard(card),
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- chrome -------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  final TableView view;
  final VoidCallback onLeave;

  const _TopBar({required this.view, required this.onLeave});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
    child: Row(
      children: [
        IconButton(
          onPressed: onLeave,
          icon: const Icon(Icons.arrow_back, color: C.ash, size: 20),
          tooltip: 'Leave the table',
        ),
        // The scores on the right are fixed-width and must never be pushed
        // off, so the title column is what gives way on a narrow phone.
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                view.profile.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: T.display(17, color: C.bone),
              ),
              Text(
                'ROUND ${view.roundIndex + 1} · TO ${view.matchTarget}',
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: T.mono(10, color: C.ashDim),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        for (var side = 0; side < view.matchScores.length; side++)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Eyebrow(side == view.side ? 'You' : 'Them'),
                const SizedBox(height: 2),
                Text(
                  '${view.matchScores[side]}',
                  style: T.mono(16, color: side == view.side ? C.mint : C.ash),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// The other players, with the signal that matters most: how many cards they
/// are holding. A single card means they are about to go out.
class _SeatRow extends StatelessWidget {
  final TableView view;
  const _SeatRow({required this.view});

  @override
  Widget build(BuildContext context) {
    final others = [
      for (var p = 0; p < view.numPlayers; p++)
        if (p != view.seat) p,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          // Three opponents on a phone only fit if each takes an equal share
          // and gives up its name before its card count, which is the number
          // that actually matters.
          for (final p in others)
            Expanded(
              child: _Seat(
                name: p < view.playerNames.length
                    ? view.playerNames[p]
                    : 'Seat $p',
                cards: view.handSizes[p],
                isPartner: p == view.partnerSeat,
                toPlay: p == view.currentPlayer,
              ),
            ),
        ],
      ),
    );
  }
}

class _Seat extends StatelessWidget {
  final String name;
  final int cards;
  final bool isPartner;
  final bool toPlay;

  const _Seat({
    required this.name,
    required this.cards,
    required this.isPartner,
    required this.toPlay,
  });

  @override
  Widget build(BuildContext context) {
    final threat = cards <= 2;
    return AnimatedContainer(
      duration: Motion.of(context, Motion.base),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.black.withValues(alpha: toPlay ? 0.28 : 0.0),
        border: Border.all(color: toPlay ? C.mint : Colors.transparent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPartner ? Icons.handshake_outlined : Icons.person_outline,
            size: 14,
            color: isPartner ? C.mint : C.ash,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: T.title(13, color: C.bone),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$cards',
            style: T.mono(13, color: threat ? C.coringa : C.ashDim),
          ),
        ],
      ),
    );
  }
}

// --- the felt -----------------------------------------------------------------

class _Felt extends StatelessWidget {
  final GameController controller;
  final TableView view;

  const _Felt({required this.controller, required this.view});

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedCard;
    final movesForCard = selected == null
        ? const <MoveOption>[]
        : controller.moves.forCard(selected);
    final targetSlots = {
      for (final m in movesForCard)
        if (m.meldSlot != null) m.meldSlot!,
    };
    final discardMove = movesForCard
        .where((m) => m.target == MoveTarget.discard)
        .firstOrNull;

    final theirMelds = [
      for (final m in view.melds)
        if (m.owner != view.side) m,
    ];

    // The felt is centred in whatever space is left over so a table with few
    // melds does not sit in the top corner with a void beneath it, and scrolls
    // once the melds outgrow the space.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: _content(
            context,
            movesForCard,
            targetSlots,
            discardMove,
            theirMelds,
          ),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    List<MoveOption> movesForCard,
    Set<int> targetSlots,
    MoveOption? discardMove,
    List<MeldView> theirMelds,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MeldShelf(
          label: view.numPlayers == 4 ? "Their team's melds" : 'Their melds',
          melds: theirMelds,
          emptyText: 'Nothing down yet',
        ),
        const SizedBox(height: 10),
        TableCenter(
          stockCount: view.stockCount,
          trash: view.trash,
          mortoSizes: view.mortoSizes,
          mortoTaken: view.mortoTaken,
          mySide: view.side,
          stockActive:
              controller.moves.firstWithTarget(MoveTarget.stock) != null,
          pileActive:
              controller.moves.firstWithTarget(MoveTarget.pile) != null ||
              discardMove != null,
          pileFrozen: view.frozen,
          pileBlocked: view.pileBlocked,
          onStock: () {
            final m = controller.moves.firstWithTarget(MoveTarget.stock);
            if (m != null) controller.play(m);
          },
          onPile: () {
            if (discardMove != null) {
              controller.play(discardMove);
              return;
            }
            final m = controller.moves.firstWithTarget(MoveTarget.pile);
            if (m != null) controller.play(m);
          },
          onInspectPile: () => _showPile(context, view),
        ),
        const SizedBox(height: 10),
        _MeldShelf(
          label: view.numPlayers == 4 ? 'Your team\'s melds' : 'Your melds',
          melds: view.myMelds,
          emptyText: 'Lay a run or a set to open',
          targetSlots: targetSlots,
          onTapSlot: (slot) {
            final move = movesForCard
                .where((m) => m.meldSlot == slot)
                .firstOrNull;
            if (move != null) controller.play(move);
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  static void _showPile(BuildContext context, TableView view) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.night,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Eyebrow('The discard pile, bottom to top'),
            const SizedBox(height: 12),
            if (view.trash.isEmpty)
              Text('The pile is empty.', style: T.body(14, color: C.ash))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final ct in view.trash) PlayingCard(card: ct, width: 44),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _MeldShelf extends StatelessWidget {
  final String label;
  final List<MeldView> melds;
  final String emptyText;
  final Set<int> targetSlots;
  final ValueChanged<int>? onTapSlot;

  const _MeldShelf({
    required this.label,
    required this.melds,
    required this.emptyText,
    this.targetSlots = const {},
    this.onTapSlot,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Eyebrow(label),
      const SizedBox(height: 6),
      if (melds.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: C.line),
          ),
          alignment: Alignment.center,
          child: Text(emptyText, style: T.body(12, color: C.ashDim)),
        )
      else
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < melds.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    right: i == melds.length - 1 ? 0 : 8,
                  ),
                  child: MeldStrip(
                    meld: melds[i],
                    isTarget: targetSlots.contains(i),
                    onTap: targetSlots.contains(i)
                        ? () => onTapSlot?.call(i)
                        : null,
                  ),
                ),
            ],
          ),
        ),
    ],
  );
}

// --- the action bar -------------------------------------------------------------

class _ActionBar extends StatelessWidget {
  final GameController controller;
  final TableView view;

  const _ActionBar({required this.controller, required this.view});

  @override
  Widget build(BuildContext context) {
    if (!view.myTurn) {
      final who = view.currentPlayer < view.playerNames.length
          ? view.playerNames[view.currentPlayer]
          : 'Seat ${view.currentPlayer}';
      return _Strip(
        child: Text('$who is playing…', style: T.body(13, color: C.ash)),
      );
    }

    final selected = controller.selectedCard;
    final moves = controller.moves;

    if (view.phase == 'draw') {
      return _Strip(
        child: Row(
          children: [
            Expanded(
              child: Text(
                view.pendingPileCard != null
                    ? 'Meld the card you took from the pile'
                    : 'Draw from the stock, or take the pile',
                style: T.body(13, color: C.bone),
              ),
            ),
            if (moves.firstWithTarget(MoveTarget.endRound) != null)
              _Chip(
                move: moves.firstWithTarget(MoveTarget.endRound)!,
                tone: C.coringa,
                onTap: () => controller.play(
                  moves.firstWithTarget(MoveTarget.endRound)!,
                ),
              ),
          ],
        ),
      );
    }

    final goOut = moves.firstWithTarget(MoveTarget.goOut);
    if (goOut != null) {
      return _Strip(
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Your hand is empty — finish it.',
                style: T.title(14, color: C.limpa),
              ),
            ),
            _Chip(
              move: goOut,
              tone: C.limpa,
              onTap: () => controller.play(goOut),
            ),
          ],
        ),
      );
    }

    if (selected == null) {
      final hint = view.pendingPileCard != null
          ? 'You must meld ${cardStr(view.pendingPileCard!)} before anything else'
          : 'Tap a card to see where it can go';
      return _Strip(
        child: Row(
          children: [
            Expanded(
              child: Text(hint, style: T.body(13, color: C.ash)),
            ),
            _MoreMoves(controller: controller),
          ],
        ),
      );
    }

    final options = moves.forCard(selected);
    if (options.isEmpty) {
      return _Strip(
        child: CardSentence(
          prefix: '',
          cards: [selected],
          suffix: ' has nowhere to go this turn.',
          style: T.body(13, color: C.ashDim),
        ),
      );
    }

    // New melds need naming, so they get chips; adds and discards are done by
    // tapping the glowing target on the table.
    final creates = options
        .where((o) => o.target == MoveTarget.newMeld)
        .toList();
    return _Strip(
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final o in creates)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _Chip(
                        move: o,
                        tone: C.mint,
                        onTap: () => controller.play(o),
                      ),
                    ),
                  if (creates.isEmpty)
                    CardSentence(
                      prefix: 'Tap a glowing spot to play ',
                      cards: [selected],
                      style: T.body(13, color: C.ash),
                    ),
                ],
              ),
            ),
          ),
          _MoreMoves(controller: controller),
        ],
      ),
    );
  }
}

/// Every legal move, always reachable. Some moves — a run that spends a wild
/// you would rather keep, say — are hard to express by tapping, and a player
/// should never be unable to make a move the rules allow.
class _MoreMoves extends StatelessWidget {
  final GameController controller;
  const _MoreMoves({required this.controller});

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.night,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow('${controller.moves.options.length} legal moves'),
              const SizedBox(height: 10),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final o in controller.moves.options)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(o.label, style: T.body(14, color: C.bone)),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          controller.play(o);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    child: Text('All moves', style: T.mono(11, color: C.mint)),
  );
}

class _Strip extends StatelessWidget {
  final Widget child;
  const _Strip({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.30),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: C.line),
    ),
    child: child,
  );
}

class _Chip extends StatelessWidget {
  final MoveOption move;
  final Color tone;
  final VoidCallback onTap;

  const _Chip({required this.move, required this.tone, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: tone,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: CardSentence(
          prefix: move.prefix,
          cards: move.nameCards,
          style: T.mono(11, color: C.night),
        ),
      ),
    ),
  );
}

class _Notice extends StatelessWidget {
  final String text;
  final VoidCallback onDismiss;

  const _Notice({required this.text, required this.onDismiss});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: C.coringa.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: C.coringa.withValues(alpha: 0.5)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: T.body(12, color: C.bone)),
        ),
        GestureDetector(
          onTap: onDismiss,
          child: const Icon(Icons.close, size: 16, color: C.ash),
        ),
      ],
    ),
  );
}

class _Message extends StatelessWidget {
  final String text;
  final bool isError;
  const _Message({required this.text, this.isError = false});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TableSurface(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: T.title(16, color: isError ? C.coringa : C.ash),
          ),
        ),
      ),
    ),
  );
}
