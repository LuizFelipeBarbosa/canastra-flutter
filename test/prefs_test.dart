/// That preferences actually come back.
///
/// [AppPrefs.load] treats failure as uninteresting and returns the defaults, so
/// a store that never opens looks exactly like a fresh install. That is how the
/// binding-not-initialised bug hid: every setting reset on launch and nothing
/// anywhere said so. These tests read through a second [AppPrefs] instance
/// rather than the one that wrote, so only a real round trip passes.
library;

import 'package:canastra/ui/app_scope.dart';
import 'package:canastra/ui/copy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A fresh instance that has read whatever the last one wrote.
Future<AppPrefs> _reload() async {
  final prefs = AppPrefs();
  await prefs.load();
  return prefs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a fresh install starts from the defaults', () async {
    final prefs = await _reload();
    expect(prefs.dark, isTrue);
    expect(prefs.lang, Lang.en);
    expect(prefs.target, 3000);
    expect(prefs.variant, 'buraco');
    expect(prefs.played, 0);
  });

  test('every setting survives a reload', () async {
    final first = await _reload();
    first.toggleTheme();
    first.toggleLang();
    first.toggleSound();
    first.setLevel(2);
    first.setTarget(5000);
    first.setVariant('canasta');

    final second = await _reload();
    expect(second.dark, isFalse);
    expect(second.lang, Lang.pt);
    expect(second.sound, isFalse);
    expect(second.level, 2);
    expect(second.target, 5000);
    expect(second.variant, 'canasta');
  });

  test('the streak survives a reload', () async {
    final first = await _reload();
    first.recordMatch(won: true);
    first.recordMatch(won: true);
    first.recordMatch(won: false);
    first.recordMatch(won: true);

    final second = await _reload();
    expect(second.played, 4);
    expect(second.won, 3);
    expect(second.streak, 1, reason: 'the loss ended the run');
    expect(second.best, 2);
  });

  test(
    'a corrupt store starts from the defaults rather than throwing',
    () async {
      SharedPreferences.setMockInitialValues({
        'bl.prefs': 'theme;lang=;;=x;target=nope',
      });
      final prefs = await _reload();
      expect(prefs.dark, isTrue);
      expect(prefs.target, 3000);
    },
  );
}
