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
import '../multiplayer/room_rules.dart';
import '../multiplayer/table_view.dart';
import '../multiplayer/transport.dart';
import 'move_index.dart';
import 'selection_plan.dart';

class GameController extends ChangeNotifier {
  RulesConfig _cfg;
  final GameTransport transport;
  final bool autoReady;

  TableView? _view;
  LobbyUpdate? _lobby;
  int? _seat;
  bool _spectating = false;
  MoveIndex _moves = MoveIndex.empty;
  final List<CardId> _selection = [];
  List<int> _queue = [];
  Refusal? _refusal;
  String? _notice;
  bool _connecting = true;
  bool _reconnecting = false;
  String? _fatal;
  StreamSubscription<ServerEvent>? _eventSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  bool _disposed = false;

  /// Blocks duplicate submissions while `legalActions` is stale and the host's
  /// answering view has not arrived yet.
  bool _awaitingView = false;

  GameController({
    required RulesConfig cfg,
    required GameTransport transport,
    bool autoReady = true,
  }) : this._(cfg, transport, autoReady);

  GameController._(this._cfg, this.transport, this.autoReady);

  RulesConfig get cfg => _cfg;
  TableView? get view => _view;
  LobbyUpdate? get lobby => _lobby;
  int? get seat => _seat ?? transport.seat;
  bool get spectating => _spectating;
  bool get inLobby => _lobby != null && !_lobby!.started && _view == null;

  bool get myReady {
    final mySeat = seat;
    if (mySeat == null) return false;
    for (final info in _lobby?.seats ?? const <SeatInfo>[]) {
      if (info.seat == mySeat) return info.ready;
    }
    return false;
  }

  MoveIndex get moves => _moves;

  /// The cards you have picked up, in the order you picked them.
  List<CardId> get selection => List.unmodifiable(_selection);

  /// Why the last thing you tried is not allowed.
  Refusal? get refusal => _refusal;

  /// A message from the host — a rejected move, usually.
  String? get notice => _notice;

  bool get connecting => _connecting;

  bool get reconnecting => _reconnecting;

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
    _connectionSubscription = transport.connectionChanges.listen((value) {
      if (_disposed) return;
      _reconnecting = value;
      notifyListeners();
    });
    try {
      await transport.connect();
      if (_disposed) return;
      if (autoReady) {
        _send(const SetReady(ready: true));
      } else if (transport.seat != null) {
        // Local transports already occupy a seat and do not send JoinRoom.
        // Re-stating the initial value asks their host for the same lobby
        // snapshot an online JoinRoom produces, without readying the player.
        _send(const SetReady(ready: false));
      }
    } on TransportException catch (e) {
      if (_disposed) return;
      _fatal = e.message;
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      _fatal = '$e';
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
        _moves = MoveIndex.build(_cfg, view);
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

      case Joined(:final seat, :final spectator):
        _spectating = spectator;
        _seat = spectator ? null : seat;
        _connecting = false;

      case LobbyUpdate():
        _lobby = event;
        _connecting = false;
        _applyLobbyRules(event);
    }
    notifyListeners();
  }

  void _applyLobbyRules(LobbyUpdate lobby) {
    final target = lobby.matchTarget ?? _cfg.scoring.matchTarget;
    if (lobby.profile == _cfg.name &&
        lobby.numPlayers == _cfg.table.numPlayers &&
        target == _cfg.scoring.matchTarget) {
      return;
    }

    try {
      final next = RoomRules(
        profileId: lobby.profile,
        numPlayers: lobby.numPlayers,
        matchTarget: target,
      ).toConfig();
      // loadProfile deliberately has an offline fallback. On the wire, silently
      // turning a future profile into Buraco would be worse than keeping the
      // caller's known-good rules until this client understands it.
      if (next.name != lobby.profile) {
        throw FormatException('unknown profile id: ${lobby.profile}');
      }
      _cfg = next;

      // Lobby updates normally precede the first table. Rebuilding here too
      // keeps the derived move index coherent if a reconnect delivers corrected
      // rules after a view has already arrived.
      final view = _view;
      if (view != null) {
        _moves = MoveIndex.build(_cfg, view);
        _replan();
      }
    } catch (e) {
      _notice = 'Could not use table rules for ${lobby.profile}: $e';
    }
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
    if (!_send(SubmitAction(actionId: next))) {
      _queue = [];
      return;
    }
    _awaitingView = true;
  }

  // --- picking cards up ---------------------------------------------------

  /// Pick a card up, or put it back down.
  void toggleCard(CardId card) {
    if (_blockSpectatorAction()) return;
    if (!myTurn || busy) return;
    _notice = null;
    _refusal = null;
    if (!_selection.remove(card)) _selection.add(card);
    _replan();
    notifyListeners();
  }

  void clearSelection() {
    if (_blockSpectatorAction()) return;
    if (busy) return;
    if (_selection.isEmpty && _refusal == null) return;
    _selection.clear();
    _refusal = null;
    _replan();
    notifyListeners();
  }

  // --- playing ------------------------------------------------------------

  /// Lay the selection down as a new meld.
  void meldSelection() {
    if (_blockSpectatorAction()) return;
    _submitPlan((view) => planNewMeld(_cfg, view, _selection));
  }

  /// Add the selection to one of your side's melds.
  void extendMeld(int slot) {
    if (_blockSpectatorAction()) return;
    _submitPlan((view) => planExtendMeld(_cfg, view, slot, _selection));
  }

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
    _canMeld = planNewMeld(_cfg, view, _selection) is PlanReady;
    _openSlots = {
      for (var slot = 0; slot < view.myMelds.length; slot++)
        if (planExtendMeld(_cfg, view, slot, _selection) is PlanReady) slot,
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
    if (_blockSpectatorAction()) return;
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
    final out = _cfg.goingOut;
    if (out.discardToGoOut == discardOutForbidden) return false;
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
    final out = _cfg.goingOut;
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
      meld.isCanastra && (!_cfg.goingOut.requireCleanCanastra || meld.isClean);

  void play(MoveOption move) => playId(move.actionId);

  void playId(int actionId) {
    if (_blockSpectatorAction()) return;
    if (_awaitingView ||
        _view == null ||
        !_view!.legalActions.contains(actionId)) {
      return;
    }
    _notice = null;
    _refusal = null;
    if (_send(SubmitAction(actionId: actionId))) {
      _awaitingView = true;
    }
  }

  void setReady(bool ready) {
    if (_blockSpectatorAction()) return;
    _send(SetReady(ready: ready));
  }

  void leave() => _send(const LeaveRoom());

  void nextRound() {
    if (_blockSpectatorAction()) return;
    _send(const RequestNextRound());
  }

  void rematch() {
    if (_blockSpectatorAction()) return;
    _send(const RequestRematch());
  }

  bool _blockSpectatorAction() {
    if (!spectating) return false;
    _notice = 'Spectators can only watch.';
    notifyListeners();
    return true;
  }

  bool _send(ClientCommand command) {
    if (_disposed) return false;
    try {
      transport.send(command);
      return true;
    } catch (e) {
      _notice = e is TransportException ? e.message : '$e';
      notifyListeners();
      return false;
    }
  }

  void dismissNotice() {
    if (_notice == null) return;
    _notice = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _eventSubscription?.cancel();
    _connectionSubscription?.cancel();
    transport.dispose();
    super.dispose();
  }
}
