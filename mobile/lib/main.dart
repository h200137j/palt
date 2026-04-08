import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme/app_theme.dart';
import 'ui/screens/home_screen.dart';

void main() {
  // ProviderScope is required by Riverpod for state management.
  runApp(const ProviderScope(child: PaltApp()));
}

class PaltApp extends StatelessWidget {
  const PaltApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PALT',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const HomeScreen(),
    );
  }
}
