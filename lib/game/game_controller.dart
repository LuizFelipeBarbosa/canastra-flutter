/// The screen's model.
///
/// It holds a [GameTransport], the latest [TableView] the host sent, and the
/// small amount of genuinely local state — which card you have picked up, and
/// the last message from the host. It never computes game state: everything
/// authoritative arrives as an event, which is exactly how it will behave when
/// the host is a server instead of this device.
library;

import 'package:flutter/foundation.dart';

import '../engine/cards.dart';
import '../engine/config.dart';
import '../multiplayer/protocol.dart';
import '../multiplayer/table_view.dart';
import '../multiplayer/transport.dart';
import 'move_index.dart';

class GameController extends ChangeNotifier {
  final RulesConfig cfg;
  final GameTransport transport;

  TableView? _view;
  MoveIndex _moves = MoveIndex.empty;
  CardId? _selected;
  String? _notice;
  bool _connecting = true;
  String? _fatal;

  GameController({required this.cfg, required this.transport});

  TableView? get view => _view;
  MoveIndex get moves => _moves;
  CardId? get selectedCard => _selected;

  /// A transient message from the host — a rejected move, usually.
  String? get notice => _notice;

  bool get connecting => _connecting;

  /// Set when the game cannot continue; the screen shows this instead.
  String? get fatalError => _fatal;

  bool get myTurn => _view?.myTurn ?? false;

  Future<void> start() async {
    transport.events.listen(
      _onEvent,
      onError: (Object e) {
        _fatal = '$e';
        notifyListeners();
      },
    );
    try {
      await transport.connect();
      transport.send(const SetReady(ready: true));
    } on TransportException catch (e) {
      _fatal = e.message;
      notifyListeners();
    }
  }

  void _onEvent(ServerEvent event) {
    switch (event) {
      case TableUpdate(:final view):
        final previous = _view;
        _view = view;
        _moves = MoveIndex.build(cfg, view);
        _connecting = false;
        // Keep a selection only while it is still a card you hold and can play.
        if (_selected != null &&
            !(view.hand.contains(_selected) &&
                _moves.playableCards.contains(_selected))) {
          _selected = null;
        }
        // A new turn is a clean slate.
        if (previous != null && previous.turnNumber != view.turnNumber) {
          _selected = null;
          _notice = null;
        }

      case ActionRejected(:final reason):
        _notice = reason;

      case ServerError(:final message):
        _notice = message;

      case Joined():
      case LobbyUpdate():
        break;
    }
    notifyListeners();
  }

  /// Pick up (or put down) a card in your hand.
  void selectCard(CardId? card) {
    _selected = _selected == card ? null : card;
    _notice = null;
    notifyListeners();
  }

  void play(MoveOption move) => playId(move.actionId);

  void playId(int actionId) {
    if (_view == null || !_view!.legalActions.contains(actionId)) return;
    _notice = null;
    transport.send(SubmitAction(actionId: actionId));
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
    transport.dispose();
    super.dispose();
  }
}
