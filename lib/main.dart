import 'package:flutter/material.dart';

import 'ui/app_scope.dart';
import 'ui/screens/landing_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Which table, which language and whether it makes a noise are all known before
  // the first frame, so the app never flashes the wrong one.
  final prefs = AppPrefs();
  await prefs.load();
  runApp(BuracoLivre(prefs: prefs));
}

class BuracoLivre extends StatelessWidget {
  final AppPrefs prefs;
  const BuracoLivre({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) => AppScope(
    prefs: prefs,
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
  );
}
