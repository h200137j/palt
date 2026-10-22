import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/trust_provider.dart';
import 'services/background.dart';
import 'theme/app_theme.dart';
import 'ui/screens/home_screen.dart';

/// Runs once per process, in the engine owned by PaltApplication — also at
/// boot with no window. The window attaches to the same engine when opened.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final sharedPrefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(sharedPrefs),
  ]);
  startCore(container);
  await themeController.load(sharedPrefs);

  runApp(UncontrolledProviderScope(
    container: container,
    child: const PaltApp(),
  ));
}

class PaltApp extends StatefulWidget {
  const PaltApp({super.key});

  @override
  State<PaltApp> createState() => _PaltAppState();
}

class _PaltAppState extends State<PaltApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    themeController.addListener(_retheme);
  }

  @override
  void dispose() {
    themeController.removeListener(_retheme);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => themeController.platformBrightnessChanged();

  /// Widgets read the theme from globals, so rebuild every one of them —
  /// in place, keeping routes and state.
  void _retheme() {
    setState(() {});
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PALT',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      themeAnimationDuration: Duration.zero,
      home: const HomeScreen(),
    );
  }
}
