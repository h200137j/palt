import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme/app_theme.dart';
import 'ui/screens/home_screen.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'providers/trust_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final sharedPrefs = await SharedPreferences.getInstance();

  runApp(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sharedPrefs),
    ],
    child: const PaltApp(),
  ));
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
