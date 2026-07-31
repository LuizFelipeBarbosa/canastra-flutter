/// The handful of things that outlive a game.
///
/// Which table you like (noite or sol), which language you read, whether the app
/// makes a noise, how hard the opponent plays, how high the match goes — and the
/// streak, which is the only reason to come back tomorrow. All of it survives a
/// reload, because a preference you have to set twice is not a preference.
///
/// Everything here is a *presentation* choice or a *record of play*. No rule
/// lives in this file; the engine never reads it.
library;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/agent.dart';
import '../engine/profiles.dart';
import 'copy.dart';
import 'theme.dart';

/// Match targets the setup screen offers.
const List<int> kTargets = [1500, 3000, 5000];

/// How the cards in your hand are lined up.
enum HandOrder {
  suit,
  rank;

  HandOrder get other =>
      this == HandOrder.suit ? HandOrder.rank : HandOrder.suit;

  static HandOrder byName(String? name) => HandOrder.values.firstWhere(
    (o) => o.name == name,
    orElse: () => HandOrder.suit,
  );
}

class AppPrefs extends ChangeNotifier {
  static const _key = 'bl.prefs';

  SharedPreferences? _store;

  bool _dark = true;
  Lang _lang = Lang.en;
  bool _sound = true;
  int _level = 1;
  int _target = 3000;
  String _variant = 'buraco';
  int _players = 2;
  HandOrder _handOrder = HandOrder.suit;

  int _streak = 0;
  int _won = 0;
  int _played = 0;
  int _best = 0;
  bool _legacySent = false;

  bool get dark => _dark;
  Lang get lang => _lang;
  bool get sound => _sound;

  /// 0 loose, 1 steady, 2 sharp — the index the setup screen highlights.
  int get level => _level;
  int get target => _target;
  String get variant => _variant;
  int get players => _players;
  HandOrder get handOrder => _handOrder;

  int get streak => _streak;
  int get won => _won;
  int get played => _played;
  int get best => _best;
  bool get legacySent => _legacySent;

  Palette get palette => _dark ? Palette.dark : Palette.light;
  Copy get copy => Copy.of(_lang);

  AgentLevel get agentLevel => switch (_level) {
    0 => AgentLevel.easy,
    2 => AgentLevel.hard,
    _ => AgentLevel.normal,
  };

  /// The stored player count when [profile] offers it, else the profile's
  /// first — the preference can outlive a switch to a two-player-only variant.
  int playersFor(GameProfile profile) => profile.playerCounts.contains(_players)
      ? _players
      : profile.playerCounts.first;

  /// Read what was stored. Failure is not interesting — a fresh install and a
  /// corrupt store should both just start from the defaults.
  Future<void> load() async {
    try {
      _store = await SharedPreferences.getInstance();
      final raw = _store?.getString(_key);
      if (raw == null) return;
      _readFrom(raw);
    } on Object {
      return;
    }
    notifyListeners();
  }

  void _readFrom(String raw) {
    // A flat `key=value;` string rather than JSON: there are thirteen scalars,
    // and a codec would be more code than the thing it encodes.
    for (final pair in raw.split(';')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final value = pair.substring(eq + 1);
      switch (pair.substring(0, eq)) {
        case 'theme':
          _dark = value != 'light';
        case 'lang':
          _lang = Lang.byName(value);
        case 'sound':
          _sound = value != '0';
        case 'level':
          _level = (int.tryParse(value) ?? 1).clamp(0, 2);
        case 'target':
          final t = int.tryParse(value);
          if (t != null && kTargets.contains(t)) _target = t;
        case 'variant':
          _variant = value;
        case 'players':
          final n = int.tryParse(value);
          if (n != null && (n == 2 || n == 4)) _players = n;
        case 'handOrder':
          _handOrder = HandOrder.byName(value);
        case 'streak':
          _streak = int.tryParse(value) ?? 0;
        case 'won':
          _won = int.tryParse(value) ?? 0;
        case 'played':
          _played = int.tryParse(value) ?? 0;
        case 'best':
          _best = int.tryParse(value) ?? 0;
        case 'legacySent':
          _legacySent = value == '1';
      }
    }
  }

  void _save() {
    _store?.setString(
      _key,
      [
        'theme=${_dark ? 'dark' : 'light'}',
        'lang=${_lang.name}',
        'sound=${_sound ? '1' : '0'}',
        'level=$_level',
        'target=$_target',
        'variant=$_variant',
        'players=$_players',
        'handOrder=${_handOrder.name}',
        'streak=$_streak',
        'won=$_won',
        'played=$_played',
        'best=$_best',
        'legacySent=${_legacySent ? '1' : '0'}',
      ].join(';'),
    );
  }

  void _set(VoidCallback change) {
    change();
    _save();
    notifyListeners();
  }

  void toggleTheme() => _set(() => _dark = !_dark);
  void toggleLang() => _set(() => _lang = _lang.other);
  void toggleSound() => _set(() => _sound = !_sound);
  void setLevel(int level) => _set(() => _level = level);
  void setTarget(int target) => _set(() => _target = target);
  void setVariant(String id) => _set(() => _variant = id);
  void setPlayers(int players) => _set(() => _players = players);
  void setHandOrder(HandOrder order) => _set(() => _handOrder = order);
  void toggleHandOrder() => _set(() => _handOrder = _handOrder.other);
  void markLegacySent() => _set(() => _legacySent = true);

  /// Record a finished match. Only a win extends the streak; anything else ends
  /// it, which is what makes the number worth looking at.
  void recordMatch({required bool won}) => _set(() {
    _played += 1;
    if (won) {
      _won += 1;
      _streak += 1;
      if (_streak > _best) _best = _streak;
    } else {
      _streak = 0;
    }
  });
}

/// Carries [AppPrefs] down the tree and rebuilds whatever reads it.
class AppScope extends InheritedNotifier<AppPrefs> {
  const AppScope({super.key, required AppPrefs prefs, required super.child})
    : super(notifier: prefs);

  static AppPrefs of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope?.notifier != null, 'no AppScope above this widget');
    return scope!.notifier!;
  }
}

/// Sugar for the three things nearly every widget in the app needs.
extension AppContext on BuildContext {
  AppPrefs get prefs => AppScope.of(this);
  Palette get pal => AppScope.of(this).palette;
  Copy get copy => AppScope.of(this).copy;
}
