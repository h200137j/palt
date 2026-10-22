/// dock_screen.dart — the phone, turned sideways, as an app dock for a
/// computer (features/apps.dart).
///
/// Pinned apps fill pages of icons; swipe between pages. Tap opens an app,
/// or brings it forward when it is already open (a dot marks open apps).
/// Hold an icon for Quit and Unpin, or Rearrange: then drag icons to move
/// them, onto the edge of the screen to change page.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/apps.dart';
import '../../features/remote_input.dart';
import '../../models/peer.dart';
import '../../providers/link_provider.dart';
import '../../theme/app_theme.dart';
import 'touchpad_screen.dart';

class DockScreen extends ConsumerStatefulWidget {
  final Peer peer;
  const DockScreen({super.key, required this.peer});

  @override
  ConsumerState<DockScreen> createState() => _DockScreenState();
}

class _DockScreenState extends ConsumerState<DockScreen> with WidgetsBindingObserver {
  static const _poll = Duration(seconds: 3);

  DockApps? _dock;
  List<DockApp> _all = const [];
  Map<String, DockApp> _byId = const {};
  List<String> _pinned = const [];
  Set<String> _running = const {};
  String? _error;
  bool _loading = true;
  bool _editing = false;
  String? _opening; // id being opened, for a moment of feedback
  Timer? _pollTimer;
  final _pages = PageController();
  int _page = 0;
  final _icons = <String, Future<Uint8List?>>{};

  String get _device => widget.peer.deviceName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _pages.dispose();
    SystemChrome.setPreferredOrientations(const []);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) {
      _pollTimer?.cancel();
    } else if (s == AppLifecycleState.resumed && _dock != null) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      _refreshRunning();
      _startPolling();
    }
  }

  Future<void> _load() async {
    final l = ref.read(linkManagerProvider).byName(_device);
    if (!DockApps.supported(l)) {
      setState(() {
        _loading = false;
        _error = l == null ? '$_device isn\'t connected' : 'Update PALT on $_device for the app dock';
      });
      return;
    }
    final dock = DockApps(l!);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (apps, running) = await dock.list();
      final pinned = await DockApps.pinned(_device);
      if (!mounted) return;
      setState(() {
        _dock = dock;
        _all = apps;
        _byId = {for (final a in apps) a.id: a};
        // Uninstalled apps drop out of the dock.
        _pinned = pinned.where(_byId.containsKey).toList();
        _running = running;
        _loading = false;
      });
      _startPolling();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_poll, (_) => _refreshRunning());
  }

  Future<void> _refreshRunning() async {
    try {
      final r = await _dock?.running();
      if (r != null && mounted && !_sameSet(r, _running)) setState(() => _running = r);
    } catch (_) {}
  }

  static bool _sameSet(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

  Future<Uint8List?> _icon(DockApp a) => _icons.putIfAbsent('${a.id}-${a.icon}', () => _dock!.icon(a));

  void _savePins(List<String> ids) {
    setState(() => _pinned = ids);
    DockApps.setPinned(_device, ids);
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _open(DockApp a) async {
    HapticFeedback.lightImpact();
    setState(() => _opening = a.id);
    try {
      await _dock!.launch(a.id);
      Future.delayed(const Duration(milliseconds: 900), _refreshRunning);
    } catch (e) {
      _toast('Couldn\'t open ${a.name}: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _opening == a.id) setState(() => _opening = null);
      });
    }
  }

  Future<void> _quit(DockApp a) async {
    try {
      await _dock!.quit(a.id);
      Future.delayed(const Duration(milliseconds: 900), _refreshRunning);
    } catch (e) {
      _toast('Couldn\'t quit ${a.name}: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  void _menu(DockApp a) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(a.name, style: display(fontSize: 18)),
          ),
          if (_running.contains(a.id))
            ListTile(
              leading: const Icon(Icons.close_rounded, color: kDanger),
              title: const Text('Quit'),
              onTap: () {
                Navigator.pop(ctx);
                _quit(a);
              },
            ),
          ListTile(
            leading: const Icon(Icons.push_pin_outlined),
            title: const Text('Unpin'),
            onTap: () {
              Navigator.pop(ctx);
              _savePins([..._pinned]..remove(a.id));
            },
          ),
          ListTile(
            leading: const Icon(Icons.open_with_rounded),
            title: const Text('Rearrange'),
            onTap: () {
              Navigator.pop(ctx);
              setState(() => _editing = true);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _pick() async {
    final picked = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _AppPicker(apps: _all, pinned: _pinned, icon: _icon),
      ),
    );
    if (picked != null) _savePins(picked);
  }

  void _touchpad() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => TouchpadScreen(peer: widget.peer))).then((_) {
      // The keyboard brings the system bars back.
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    });
  }

  // ── Layout ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final link = ref.watch(linkManagerProvider).byName(_device);
    return Scaffold(
      backgroundColor: kBg,
      body: Container(
        decoration: const BoxDecoration(gradient: kPageGlow),
        child: SafeArea(
          child: Column(children: [
            _bar(RemoteInput.supported(link)),
            Expanded(child: _body()),
          ]),
        ),
      ),
    );
  }

  Widget _bar(bool touchpad) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 8, 0),
        child: Row(children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded, color: kTextSecondary),
          ),
          Expanded(
            child: Text(_device,
                style: display(fontSize: 17, color: kTextSecondary), overflow: TextOverflow.ellipsis),
          ),
          if (_editing)
            FilledButton(
              onPressed: () => setState(() => _editing = false),
              style: FilledButton.styleFrom(backgroundColor: kAccent, foregroundColor: kOnAccent),
              child: const Text('Done'),
            )
          else ...[
            if (touchpad)
              IconButton(
                tooltip: 'Touchpad & keyboard',
                onPressed: _touchpad,
                icon: const Icon(Icons.mouse_rounded, color: kTextSecondary),
              ),
            if (_dock != null)
              IconButton(
                tooltip: 'Pin apps',
                onPressed: _pick,
                icon: const Icon(Icons.add_rounded, color: kTextSecondary),
              ),
          ],
        ]),
      );

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: kAccent));
    if (_error != null) {
      return _Empty(
        icon: Icons.apps_rounded,
        title: 'App dock unavailable',
        text: _error!,
        action: TextButton(onPressed: _load, child: const Text('Try again')),
      );
    }
    if (_pinned.isEmpty) {
      return _Empty(
        icon: Icons.apps_rounded,
        title: 'Your dock is empty',
        text: 'Pin the apps you open most on $_device. Tap one to open it, or to bring it forward.',
        action: FilledButton.icon(
          onPressed: _pick,
          style: FilledButton.styleFrom(backgroundColor: kAccent, foregroundColor: kOnAccent),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Pin apps'),
        ),
      );
    }
    return LayoutBuilder(builder: (context, c) {
      const tileW = 112.0, tileH = 118.0;
      final cols = math.max(2, (c.maxWidth - 48) ~/ tileW);
      final rows = math.max(1, (c.maxHeight - 28) ~/ tileH);
      final per = cols * rows;
      final pages = (_pinned.length / per).ceil() + (_editing ? 1 : 0);
      final page = math.min(_page, pages - 1);
      return Stack(children: [
        PageView.builder(
          controller: _pages,
          itemCount: pages,
          onPageChanged: (p) => setState(() => _page = p),
          itemBuilder: (_, p) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: cols,
              childAspectRatio: ((c.maxWidth - 48) / cols) / ((c.maxHeight - 28) / rows),
              children: [
                for (var i = p * per; i < math.min((p + 1) * per, _pinned.length); i++) _tile(i),
              ],
            ),
          ),
        ),
        if (pages > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var p = 0; p < pages; p++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: p == page ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: p == page ? kAccent : kTextFaint,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ]),
          ),
        if (_editing) ...[
          Positioned(left: 0, top: 0, bottom: 0, width: 28, child: _EdgeFlip(onFlip: () => _flip(-1, pages))),
          Positioned(right: 0, top: 0, bottom: 0, width: 28, child: _EdgeFlip(onFlip: () => _flip(1, pages))),
        ],
      ]);
    });
  }

  void _flip(int by, int pages) {
    final to = (_page + by).clamp(0, pages - 1);
    if (to != _page) _pages.animateToPage(to, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  Widget _tile(int index) {
    final app = _byId[_pinned[index]]!;
    final tile = _AppTile(
      app: app,
      icon: _icon(app),
      running: _running.contains(app.id),
      opening: _opening == app.id,
      editing: _editing,
      onTap: _editing ? null : () => _open(app),
      onLongPress: _editing ? null : () => _menu(app),
      onRemove: () => _savePins([..._pinned]..remove(app.id)),
    );
    if (!_editing) return tile;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != app.id,
      onAcceptWithDetails: (d) {
        final ids = [..._pinned]..remove(d.data);
        ids.insert(ids.indexOf(app.id) + (_pinned.indexOf(d.data) < index ? 1 : 0), d.data);
        HapticFeedback.selectionClick();
        _savePins(ids);
      },
      builder: (context, over, _) => Draggable<String>(
        data: app.id,
        feedback: SizedBox(width: 96, height: 104, child: Material(type: MaterialType.transparency, child: tile)),
        childWhenDragging: Opacity(opacity: 0.25, child: tile),
        child: AnimatedScale(scale: over.isNotEmpty ? 1.12 : 1, duration: const Duration(milliseconds: 120), child: tile),
      ),
    );
  }
}

/// Holding a dragged icon here flips to the next page.
class _EdgeFlip extends StatefulWidget {
  final VoidCallback onFlip;
  const _EdgeFlip({required this.onFlip});

  @override
  State<_EdgeFlip> createState() => _EdgeFlipState();
}

class _EdgeFlipState extends State<_EdgeFlip> {
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DragTarget<String>(
        onWillAcceptWithDetails: (_) {
          _t ??= Timer.periodic(const Duration(milliseconds: 650), (_) => widget.onFlip());
          return false;
        },
        onLeave: (_) {
          _t?.cancel();
          _t = null;
        },
        builder: (_, __, ___) => const SizedBox.expand(),
      );
}

class _AppIcon extends StatelessWidget {
  final DockApp app;
  final Future<Uint8List?> icon;
  final double size;
  const _AppIcon({required this.app, required this.icon, required this.size});

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
        future: icon,
        builder: (_, s) {
          final bytes = s.data;
          if (bytes != null) {
            return Image.memory(bytes, width: size, height: size, filterQuality: FilterQuality.medium, gaplessPlayback: true);
          }
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(gradient: kTileGradient, borderRadius: BorderRadius.circular(size * 0.24)),
            alignment: Alignment.center,
            child: Text(app.name.isEmpty ? '?' : app.name.characters.first.toUpperCase(),
                style: display(fontSize: size * 0.42, color: kTextSecondary)),
          );
        },
      );
}

class _AppTile extends StatelessWidget {
  final DockApp app;
  final Future<Uint8List?> icon;
  final bool running, opening, editing;
  final VoidCallback? onTap, onLongPress;
  final VoidCallback onRemove;
  const _AppTile({
    required this.app,
    required this.icon,
    required this.running,
    required this.opening,
    required this.editing,
    required this.onTap,
    required this.onLongPress,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        onLongPress: onLongPress,
        child: LayoutBuilder(builder: (context, c) {
          final size = math.min(64.0, math.min(c.maxWidth, c.maxHeight) * 0.56);
          return Stack(children: [
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedScale(
                  scale: opening ? 0.86 : 1,
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  child: _AppIcon(app: app, icon: icon, size: size),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(app.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: kText, fontSize: 12, fontWeight: FontWeight.w500)),
                ),
                const SizedBox(height: 4),
                AnimatedOpacity(
                  opacity: running ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle),
                  ),
                ),
              ]),
            ),
            if (editing)
              Positioned(
                top: 2,
                right: 6,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: kSurfaceRaised,
                      shape: BoxShape.circle,
                      border: Border.all(color: kHairline),
                    ),
                    child: const Icon(Icons.remove_rounded, size: 16, color: kText),
                  ),
                ),
              ),
          ]);
        }),
      );
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title, text;
  final Widget action;
  const _Empty({required this.icon, required this.title, required this.text, required this.action});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 36, color: kAccent),
            const SizedBox(height: 10),
            Text(title, style: display(fontSize: 20)),
            const SizedBox(height: 6),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: kTextSecondary, fontSize: 13.5)),
            const SizedBox(height: 14),
            action,
          ]),
        ),
      );
}

/// Every app on the computer, with search; tap to pin or unpin. Returns the
/// new pinned list (new pins go at the end).
class _AppPicker extends StatefulWidget {
  final List<DockApp> apps;
  final List<String> pinned;
  final Future<Uint8List?> Function(DockApp) icon;
  const _AppPicker({required this.apps, required this.pinned, required this.icon});

  @override
  State<_AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends State<_AppPicker> {
  late final _pinned = [...widget.pinned];
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final shown = q.isEmpty ? widget.apps : widget.apps.where((a) => a.name.toLowerCase().contains(q)).toList();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _pinned);
      },
      child: Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          backgroundColor: kBg,
          leading: IconButton(
            icon: const Icon(Icons.check_rounded),
            onPressed: () => Navigator.pop(context, _pinned),
          ),
          title: TextField(
            autofocus: false,
            decoration: const InputDecoration(
              hintText: 'Search apps',
              border: InputBorder.none,
              prefixIcon: Icon(Icons.search_rounded, color: kTextFaint),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        body: GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 110, mainAxisExtent: 112),
          itemCount: shown.length,
          itemBuilder: (_, i) {
            final a = shown[i];
            final on = _pinned.contains(a.id);
            return InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => on ? _pinned.remove(a.id) : _pinned.add(a.id));
              },
              child: Stack(children: [
                Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    _AppIcon(app: a, icon: widget.icon(a), size: 52),
                    const SizedBox(height: 6),
                    Text(a.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: on ? kText : kTextSecondary, fontSize: 11.5)),
                  ]),
                ),
                if (on)
                  const Positioned(
                    top: 4,
                    right: 12,
                    child: Icon(Icons.check_circle_rounded, color: kAccent, size: 20),
                  ),
              ]),
            );
          },
        ),
      ),
    );
  }
}
