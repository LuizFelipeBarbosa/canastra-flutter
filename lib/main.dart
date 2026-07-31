/// Starts Buraco Livre with preferences and identity ready for the first frame.
library;

import 'package:flutter/material.dart';

import 'account/account.dart';
import 'account/backend_factory.dart';
import 'account/legacy_stats.dart';
import 'account/presence.dart';
import 'ui/account_scope.dart';
import 'ui/app_scope.dart';
import 'ui/screens/landing_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  // Reading preferences talks to the platform over a method channel, which needs
  // the binding up. `runApp` initialises it, but only after `load()` has already
  // run and failed — and `load()` swallows failure, so every setting silently
  // reset on launch.
  WidgetsFlutterBinding.ensureInitialized();

  // Which table, which language and whether it makes a noise are all known before
  // the first frame, so the app never flashes the wrong one.
  final prefs = AppPrefs();
  final account = Account(backend: await openAuthBackend());
  await Future.wait([prefs.load(), account.restore()]);
  // Permanent profiles receive pre-account counters once, in the background.
  wireLegacyUpload(account: account, prefs: prefs);
  // Lifecycle-aware pause/resume (stopping the beat when the app is
  // backgrounded) is a later refinement; for now it just runs while open.
  PresenceHeartbeat(account: account).start();
  runApp(BuracoLivre(prefs: prefs, account: account));
}

class BuracoLivre extends StatelessWidget {
  final AppPrefs prefs;
  final Account account;
  const BuracoLivre({super.key, required this.prefs, required this.account});

  @override
  Widget build(BuildContext context) => AppScope(
    prefs: prefs,
    child: AccountScope(
      account: account,
      // Listens so a theme change repaints every route, including the ones already
      // on the stack behind the current one.
      child: ListenableBuilder(
        listenable: prefs,
        builder: (context, _) => MaterialApp(
          title: 'Buraco Livre',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(prefs.palette, dark: prefs.dark),
          home: const LandingScreen(),
        ),
      ),
    ),
  );
}
