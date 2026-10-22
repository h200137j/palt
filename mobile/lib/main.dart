import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
    themeController.beforeChange = _snapshot;
  }

  final _boundary = GlobalKey();
  final _fade = ValueNotifier<ui.Image?>(null);

  /// The old look, frozen, to fade out over the new one.
  void _snapshot() {
    final box = _boundary.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary) return;
    final view = View.of(context);
    if (view.platformDispatcher.accessibilityFeatures.disableAnimations) return;
    try {
      _fade.value?.dispose();
      _fade.value = box.toImageSync(pixelRatio: view.devicePixelRatio);
    } catch (_) {}
  }

  @override
  void dispose() {
    themeController.removeListener(_retheme);
    themeController.beforeChange = null;
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
      builder: (context, child) => Stack(children: [
        RepaintBoundary(key: _boundary, child: child),
        ValueListenableBuilder<ui.Image?>(
          valueListenable: _fade,
          builder: (context, image, _) => image == null
              ? const SizedBox.shrink()
              : IgnorePointer(
                  child: TweenAnimationBuilder<double>(
                    key: ObjectKey(image),
                    tween: Tween(begin: 1, end: 0),
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutCubic,
                    onEnd: () {
                      if (_fade.value == image) {
                        _fade.value = null;
                        image.dispose();
                      }
                    },
                    builder: (context, t, _) => Opacity(
                      opacity: t,
                      child: SizedBox.expand(child: RawImage(image: image, fit: BoxFit.fill)),
                    ),
                  ),
                ),
        ),
      ]),
      home: const HomeScreen(),
    );
  }
}
