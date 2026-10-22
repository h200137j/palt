/// dock_view.dart — the Dock tab of a computer's page: its apps, from the
/// phone (features/apps.dart).
///
/// Open now lists every app open on the computer: tap brings it forward, ✕
/// quits it, hold to pin it. Pinned holds the apps you keep at hand: tap
/// opens (or brings forward; a dot marks open ones), hold for Quit, Unpin
/// and Rearrange, which lets you drag icons into a new order.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/apps.dart';
import '../../models/peer.dart';
import '../../providers/link_provider.dart';
import '../../theme/app_theme.dart';

class DockView extends ConsumerStatefulWidget {
  final Peer peer;

  /// Whether the tab is showing; open apps are only polled while it is.
  final bool active;
  const DockView({super.key, required this.peer, required this.active});

  @override
  ConsumerState<DockView> createState() => _DockViewState();
}

class _DockViewState extends ConsumerState<DockView> with WidgetsBindingObserver {
  static const _poll = Duration(seconds: 2);

  DockApps? _dock;
  List<DockApp> _all = const [];
  Map<String, DockApp> _byId = const {};
  List<String> _pinned = const [];
  List<String> _running = const [];
  String? _error;
  bool _loading = true;
  bool _editing = false;
  String? _opening; // id being opened, for a moment of feedback
  Timer? _pollTimer;
  bool _resumed = true;
  final _icons = <String, Future<Uint8List?>>{};

  String get _device => widget.peer.deviceName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(DockView old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      if (!widget.active) _editing = false;
      _updatePolling();
      if (widget.active) _dock == null ? _load() : _refreshRunning();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    _resumed = s == AppLifecycleState.resumed;
    _updatePolling();
    if (_resumed && widget.active) _refreshRunning();
  }

  void _updatePolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_dock != null && widget.active && _resumed) {
      _pollTimer = Timer.periodic(_poll, (_) => _refreshRunning());
    }
  }

  Future<void> _load() async {
    final l = ref.read(linkManagerProvider).byName(_device);
    if (!DockApps.supported(l)) {
      setState(() {
        _loading = false;
        _error = l == null ? '$_device isn\'t connected' : 'Update PALT on $_device for the dock';
      });
      return;
    }
    final dock = DockApps(l!);
    // A pull to refresh keeps the dock on screen.
    if (_dock == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
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
      _updatePolling();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _refreshRunning() async {
    try {
      final r = await _dock?.running();
      if (r != null && mounted && !_sameList(r, _running)) setState(() => _running = r);
    } catch (_) {}
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

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
    HapticFeedback.lightImpact();
    try {
      await _dock!.quit(a.id);
      Future.delayed(const Duration(milliseconds: 700), _refreshRunning);
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
    final pinned = _pinned.contains(a.id);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      showDragHandle: true,
      builder: (ctx) {
        Widget item(IconData icon, String label, VoidCallback onTap, {Color? color}) => ListTile(
              leading: Icon(icon, color: color),
              title: Text(label),
              onTap: () {
                Navigator.pop(ctx);
                onTap();
              },
            );
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(a.name, style: display(fontSize: 18)),
            ),
            item(Icons.open_in_new_rounded, _running.contains(a.id) ? 'Bring forward' : 'Open', () => _open(a)),
            if (_running.contains(a.id)) item(Icons.close_rounded, 'Quit', () => _quit(a), color: kDanger),
            if (pinned)
              item(Icons.push_pin_outlined, 'Unpin', () => _savePins([..._pinned]..remove(a.id)))
            else
              item(Icons.push_pin_rounded, 'Pin', () => _savePins([..._pinned, a.id])),
            if (pinned && _pinned.length > 1)
              item(Icons.open_with_rounded, 'Rearrange', () => setState(() => _editing = true)),
          ]),
        );
      },
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

  // ── Layout ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: kAccent));
    if (_error != null) {
      return _Empty(
        title: 'Dock unavailable',
        text: _error!,
        action: TextButton(onPressed: _load, child: const Text('Try again')),
      );
    }
    final open = [for (final id in _running) if (_byId[id] != null) _byId[id]!];
    open.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return RefreshIndicator(
      color: kAccent,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          _Header('Open now', trailing: open.isEmpty ? null : '${open.length}'),
          if (open.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Text('No apps are open.', style: TextStyle(color: kTextFaint, fontSize: 13)),
            )
          else
            _OpenApps(
              apps: open,
              icon: _icon,
              opening: _opening,
              onTap: _open,
              onQuit: _quit,
              onHold: _menu,
            ),
          const SizedBox(height: 18),
          _Header(
            'Pinned',
            action: _editing
                ? TextButton(onPressed: () => setState(() => _editing = false), child: const Text('Done'))
                : null,
          ),
          if (_editing)
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text('Drag an app onto another to move it there.',
                  style: TextStyle(color: kTextSecondary, fontSize: 12.5)),
            ),
          _pinnedGrid(),
        ],
      ),
    );
  }

  Widget _pinnedGrid() => LayoutBuilder(builder: (context, c) {
        const minTile = 84.0, gap = 6.0;
        final cols = math.max(3, (c.maxWidth + gap) ~/ (minTile + gap));
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        final tiles = [
          for (var i = 0; i < _pinned.length; i++) _tile(i, w),
          if (!_editing) _AddTile(width: w, onTap: _pick, first: _pinned.isEmpty),
        ];
        return Wrap(spacing: gap, runSpacing: 10, children: tiles);
      });

  Widget _tile(int index, double width) {
    final app = _byId[_pinned[index]]!;
    final tile = SizedBox(
      width: width,
      child: _AppTile(
        app: app,
        icon: _icon(app),
        running: _running.contains(app.id),
        opening: _opening == app.id,
        editing: _editing,
        onTap: _editing ? null : () => _open(app),
        onLongPress: _editing ? null : () => _menu(app),
        onRemove: () => _savePins([..._pinned]..remove(app.id)),
      ),
    );
    if (!_editing) return tile;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != app.id,
      onAcceptWithDetails: (d) {
        final from = _pinned.indexOf(d.data);
        final ids = [..._pinned]..removeAt(from);
        ids.insert(index, d.data);
        HapticFeedback.selectionClick();
        _savePins(ids);
      },
      builder: (context, over, _) => LongPressDraggable<String>(
        data: app.id,
        delay: const Duration(milliseconds: 120),
        feedback: Material(type: MaterialType.transparency, child: Opacity(opacity: 0.9, child: tile)),
        childWhenDragging: Opacity(opacity: 0.25, child: tile),
        child: AnimatedScale(scale: over.isNotEmpty ? 1.1 : 1, duration: const Duration(milliseconds: 120), child: tile),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String label;
  final String? trailing;
  final Widget? action;
  const _Header(this.label, {this.trailing, this.action});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
        child: SizedBox(
          height: 32,
          child: Row(children: [
            Text(label.toUpperCase(),
                style: const TextStyle(
                    color: kTextSecondary, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.4)),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Text(trailing!, style: mono(fontSize: 11)),
            ],
            const Spacer(),
            if (action != null) action!,
          ]),
        ),
      );
}

/// Open apps as rows of two: icon, name and a quit button.
class _OpenApps extends StatelessWidget {
  final List<DockApp> apps;
  final Future<Uint8List?> Function(DockApp) icon;
  final String? opening;
  final ValueChanged<DockApp> onTap, onQuit, onHold;
  const _OpenApps({
    required this.apps,
    required this.icon,
    required this.opening,
    required this.onTap,
    required this.onQuit,
    required this.onHold,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        const gap = 8.0;
        final w = (c.maxWidth - gap) / 2;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final a in apps)
            SizedBox(
              width: w,
              height: 60,
              child: Material(
                type: MaterialType.transparency,
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: kTileGradient,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: opening == a.id ? kAccent : kHairline),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => onTap(a),
                    onLongPress: () => onHold(a),
                    child: Row(children: [
                      const SizedBox(width: 10),
                      _AppIcon(app: a, icon: icon(a), size: 32),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(a.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: kText, fontSize: 13, fontWeight: FontWeight.w500, height: 1.2)),
                      ),
                      IconButton(
                        tooltip: 'Quit',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => onQuit(a),
                        icon: const Icon(Icons.close_rounded, size: 18, color: kTextSecondary),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
        ]);
      });
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
            return Image.memory(bytes,
                width: size, height: size, filterQuality: FilterQuality.medium, gaplessPlayback: true);
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
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedScale(
                scale: opening ? 0.86 : 1,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: _AppIcon(app: app, icon: icon, size: 52),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(app.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kText, fontSize: 11.5, fontWeight: FontWeight.w500)),
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
              top: 0,
              right: 4,
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
        ]),
      );
}

class _AddTile extends StatelessWidget {
  final double width;
  final VoidCallback onTap;
  final bool first; // the dock is empty
  const _AddTile({required this.width, required this.onTap, required this.first});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: first ? kAccent : kHairline, width: 1.5),
                ),
                child: Icon(Icons.add_rounded, color: first ? kAccent : kTextSecondary),
              ),
              const SizedBox(height: 6),
              Text(first ? 'Pin apps' : 'Add',
                  style: TextStyle(color: first ? kAccent : kTextSecondary, fontSize: 11.5)),
              const SizedBox(height: 9),
            ]),
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  final String title, text;
  final Widget action;
  const _Empty({required this.title, required this.text, required this.action});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.apps_rounded, size: 36, color: kAccent),
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
            tooltip: 'Done',
            icon: const Icon(Icons.check_rounded),
            onPressed: () => Navigator.pop(context, _pinned),
          ),
          title: TextField(
            decoration: const InputDecoration(
              hintText: 'Search apps',
              border: InputBorder.none,
              prefixIcon: Icon(Icons.search_rounded, color: kTextFaint),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        body: GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 96, mainAxisExtent: 108),
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
                    _AppIcon(app: a, icon: widget.icon(a), size: 48),
                    const SizedBox(height: 6),
                    Text(a.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: on ? kText : kTextSecondary, fontSize: 11)),
                  ]),
                ),
                if (on)
                  const Positioned(
                    top: 2,
                    right: 8,
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
