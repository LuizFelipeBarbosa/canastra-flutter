import 'package:flutter/material.dart';

import 'ui/screens/home_screen.dart';
import 'ui/theme.dart';

void main() => runApp(const CanastraApp());

class CanastraApp extends StatelessWidget {
  const CanastraApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Canastra',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: const HomeScreen(),
  );
}
