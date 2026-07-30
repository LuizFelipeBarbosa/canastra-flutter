/// The screen's model.
///
/// It holds a [GameTransport], the latest [TableView] the host sent, and the
/// small amount of genuinely local state — which cards you have picked up, and
/// the last thing the host said no to. It never computes game state: everything
/// authoritative arrives as an event, which is exactly how it will behave when
/// the host is a server instead of this device.
///
/// The one thing it does compute is the *order* to submit a multi-card play in.
/// Laying five cards down is several engine actions, and the host answers one at
/// a time, so a plan is queued here and drained as views come back. If the host
/// refuses a step, the queue is dropped and whatever is still in hand stays
/// picked up — a half-played meld is never left silently.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/cards.dart';
import '../engine/config.dart';
import '../multiplayer/protocol.dart';
import '../multiplayer/table_view.dart';
import '../multiplayer/transport.dart';
import 'move_index.dart';
import 'selection_plan.dart';

class GameController extends ChangeNotifier {
  final RulesConfig cfg;
  final GameTransport transport;

  TableView? _view;
  MoveIndex _moves = MoveIndex.empty;
  final List<CardId> _selection = [];
  List<int> _queue = [];
  Refusal? _refusal;
  String? _notice;
  bool _connecting = true;
  String? _fatal;
  StreamSubscription<ServerEvent>? _eventSubscription;
  bool _disposed = false;

  /// Blocks duplicate submissions while `legalActions` is stale and the host's
  /// answering view has not arrived yet.
  bool _awaitingView = false;

  GameController({required this.cfg, required this.transport});

  TableView? get view => _view;
  MoveIndex get moves => _moves;

  /// The cards you have picked up, in the order you picked them.
  List<CardId> get selection => List.unmodifiable(_selection);

  /// Why the last thing you tried is not allowed.
  Refusal? get refusal => _refusal;

  /// A message from the host — a rejected move, usually.
  String? get notice => _notice;

  bool get connecting => _connecting;

  /// Set when the game cannot continue; the screen shows this instead.
  String? get fatalError => _fatal;

  bool get myTurn => _view?.myTurn ?? false;

  /// A multi-card play is still being submitted, so the table should not accept
  /// another one on top of it.
  bool get busy => _queue.isNotEmpty;

  Future<void> start() async {
    _eventSubscription = transport.events.listen(
      _onEvent,
      onError: (Object e) {
        if (_disposed) return;
        _fatal = '$e';
        notifyListeners();
      },
    );
    try {
      await transport.connect();
      if (_disposed) return;
      transport.send(const SetReady(ready: true));
    } on TransportException catch (e) {
      if (_disposed) return;
      _fatal = e.message;
      notifyListeners();
    }
  }

  void _onEvent(ServerEvent event) {
    if (_disposed) return;
    switch (event) {
      case TableUpdate(:final view):
        _awaitingView = false;
        final previous = _view;
        _view = view;
        _moves = MoveIndex.build(cfg, view);
        _connecting = false;

        final tookMortoThisTurn =
            previous != null &&
            previous.turnNumber == view.turnNumber &&
            view.side < previous.mortoTaken.length &&
            view.side < view.mortoTaken.length &&
            !previous.mortoTaken[view.side] &&
            view.mortoTaken[view.side];

        // A new turn is a clean slate. So is a direct morto pickup: the hand was
        // replaced in place, and matching old selections by card type would
        // attach them to cards the player never picked up.
        if (previous != null &&
            (previous.turnNumber != view.turnNumber || tookMortoThisTurn)) {
          _selection.clear();
          _queue = [];
          _refusal = null;
          _notice = null;
        } else {
          // Keep only what you still hold. This is also what makes a partly
          // submitted plan behave: the cards it managed to play leave the
          // selection, and the ones it did not stay picked up.
          _retainHeld(view);
        }
        _pump();
        _replan();

      case ActionRejected(:final reason):
        _awaitingView = false;
        _notice = reason;
        // Whatever was queued was built on a state the host disagrees with.
        _queue = [];

      case ServerError(:final message):
        _awaitingView = false;
        _notice = message;
        _queue = [];

      case Joined():
      case LobbyUpdate():
        break;
    }
    notifyListeners();
  }

  void _retainHeld(TableView view) {
    final remaining = <CardId, int>{};
    for (final ct in view.hand) {
      remaining[ct] = (remaining[ct] ?? 0) + 1;
    }
    _selection.retainWhere((ct) {
      final n = remaining[ct] ?? 0;
      if (n == 0) return false;
      remaining[ct] = n - 1;
      return true;
    });
  }

  /// Send the next step of a queued plan, if the host will still take it.
  void _pump() {
    if (_queue.isEmpty) return;
    final view = _view;
    if (view == null || !view.myTurn) {
      _queue = [];
      return;
    }
    final next = _queue.first;
    if (!view.legalActions.contains(next)) {
      // The rest of the plan is no longer legal. Stop rather than push on: the
      // cards it did not spend are still in hand and still selected.
      _queue = [];
      _refusal = Refusal.notAllowedYet;
      return;
    }
    _queue = _queue.sublist(1);
    try {
      transport.send(SubmitAction(actionId: next));
      _awaitingView = true;
    } catch (e) {
      _queue = [];
      _notice = e is TransportException ? e.message : '$e';
      notifyListeners();
    }
  }

  // --- picking cards up ---------------------------------------------------

  /// Pick a card up, or put it back down.
  void toggleCard(CardId card) {
    if (!myTurn || busy) return;
    _notice = null;
    _refusal = null;
    if (!_selection.remove(card)) _selection.add(card);
    _replan();
    notifyListeners();
  }

  void clearSelection() {
    if (busy) return;
    if (_selection.isEmpty && _refusal == null) return;
    _selection.clear();
    _refusal = null;
    _replan();
    notifyListeners();
  }

  // --- playing ------------------------------------------------------------

  /// Lay the selection down as a new meld.
  void meldSelection() =>
      _submitPlan((view) => planNewMeld(cfg, view, _selection));

  /// Add the selection to one of your side's melds.
  void extendMeld(int slot) =>
      _submitPlan((view) => planExtendMeld(cfg, view, slot, _selection));

  void _submitPlan(PlanResult Function(TableView view) build) {
    final view = _view;
    if (view == null ||
        !view.myTurn ||
        busy ||
        _awaitingView ||
        _selection.isEmpty) {
      return;
    }
    switch (build(view)) {
      case PlanReady(:final plan):
        _refusal = null;
        _notice = null;
        _queue = plan.steps;
        _pump();
      case PlanRefused(:final reason):
        _refusal = reason;
    }
    notifyListeners();
  }

  /// Whether the selection could be laid down right now as a new meld.
  bool get canMeldSelection => _canMeld;

  /// Which of your side's meld slots the selection would fit onto.
  Set<int> get openSlots => _openSlots;

  bool _canMeld = false;
  Set<int> _openSlots = const {};

  /// Planning walks every create the engine offers and simulates each one, so it
  /// is done once when the selection or the table changes rather than on every
  /// rebuild — the table repaints far more often than either of those move.
  void _replan() {
    final view = _view;
    if (view == null || !view.myTurn || _selection.isEmpty || busy) {
      _canMeld = false;
      _openSlots = const {};
      return;
    }
    _canMeld = planNewMeld(cfg, view, _selection) is PlanReady;
    _openSlots = {
      for (var slot = 0; slot < view.myMelds.length; slot++)
        if (planExtendMeld(cfg, view, slot, _selection) is PlanReady) slot,
    };
  }

  /// The move that throws the one selected card, if the rules allow it.
  ///
  /// Not every held card may be discarded — a card taken from the pile has to be
  /// melded first, and a last card can only go down if you may go out — so the
  /// pile lights up for a discard only when there is really one to make.
  MoveOption? get discardMove {
    if (_view == null || !myTurn || busy || _selection.length != 1) return null;
    return _moves
        .forCard(_selection.single)
        .where((m) => m.target == MoveTarget.discard)
        .firstOrNull;
  }

  /// Throw the one selected card, ending your turn.
  void discardSelection() {
    final move = discardMove;
    if (move == null) {
      if (_selection.length == 1 && myTurn) {
        _refusal = goOutRefusal ?? Refusal.notAllowedYet;
        notifyListeners();
      }
      return;
    }
    playId(move.actionId);
  }

  /// True when throwing the selected card would be the last thing you do — the
  /// discard pile says "go out" rather than "discard" when it would.
  ///
  /// It is a prediction, not a promise: the host decides. It exists so the one
  /// move a whole round is spent working toward does not look like any other
  /// discard right up until it happens.
  bool get discardGoesOut {
    final view = _view;
    if (view == null || _selection.length != 1 || view.hand.length != 1) {
      return false;
    }
    final out = cfg.goingOut;
    if (out.requireMortoTaken &&
        !(view.side < view.mortoTaken.length && view.mortoTaken[view.side])) {
      return false;
    }
    if (!out.requireCanastra) return true;
    final canastras = view.myMelds.where(_isQualifyingCanastra);
    return canastras.length >= out.goOutMinCanastras;
  }

  /// Why going out is not on offer yet, for the "why not" line.
  Refusal? get goOutRefusal {
    final view = _view;
    if (view == null) return null;
    final out = cfg.goingOut;
    if (out.requireMortoTaken &&
        !(view.side < view.mortoTaken.length && view.mortoTaken[view.side])) {
      return Refusal.mortoFirst;
    }
    if (out.requireCanastra &&
        view.myMelds.where(_isQualifyingCanastra).length <
            out.goOutMinCanastras) {
      return Refusal.needCanastra;
    }
    return null;
  }

  bool _isQualifyingCanastra(MeldView meld) =>
      meld.isCanastra && (!cfg.goingOut.requireCleanCanastra || meld.isClean);

  void play(MoveOption move) => playId(move.actionId);

  void playId(int actionId) {
    if (_awaitingView ||
        _view == null ||
        !_view!.legalActions.contains(actionId)) {
      return;
    }
    _notice = null;
    _refusal = null;
    try {
      transport.send(SubmitAction(actionId: actionId));
      _awaitingView = true;
    } catch (e) {
      _notice = e is TransportException ? e.message : '$e';
      notifyListeners();
    }
  }

  void nextRound() => transport.send(const RequestNextRound());

  void rematch() => transport.send(const RequestRematch());

  void dismissNotice() {
    if (_notice == null) return;
    _notice = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _eventSubscription?.cancel();
    transport.dispose();
    super.dispose();
  }
}
