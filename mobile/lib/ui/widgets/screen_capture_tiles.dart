/// screen_capture_tiles.dart — Screenshot and Record tiles on a computer's
/// Control tab (features/screen_capture.dart). Tap Screenshot for the whole
/// screen, hold it for the focused window; the preview offers Crop and Send
/// to phone. Record turns into a running Stop timer, and a
/// finished recording can be sent over too.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/screen_capture.dart';
import '../../models/peer.dart';
import '../../providers/link_provider.dart';
import '../../theme/app_theme.dart';
import '../screens/crop_screen.dart';

class ScreenCaptureTiles extends ConsumerStatefulWidget {
  final Peer peer;
  const ScreenCaptureTiles({super.key, required this.peer});

  @override
  ConsumerState<ScreenCaptureTiles> createState() => _ScreenCaptureTilesState();
}

class _ScreenCaptureTilesState extends ConsumerState<ScreenCaptureTiles> {
  bool _shooting = false;
  bool _busy = false; // starting or stopping a recording
  DateTime? _since; // recording since, null when not recording
  Timer? _tick;

  ScreenCapture? get _capture {
    final l = ref.read(linkManagerProvider).byName(widget.peer.deviceName);
    return ScreenCapture.supported(l) ? ScreenCapture(l!) : null;
  }

  @override
  void initState() {
    super.initState();
    // A recording may still be running from an earlier visit.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final st = await _capture?.record('status');
        if (st != null && mounted) _setRecording(st.recording ? st.since ?? DateTime.now() : null);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _setRecording(DateTime? since) {
    _tick?.cancel();
    _tick = since == null ? null : Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    setState(() => _since = since);
  }

  String _err(Object e) => e.toString().replaceFirst('Exception: ', '');

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  Future<void> _screenshot({bool window = false}) async {
    final c = _capture;
    if (c == null || _shooting) return;
    window ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact();
    setState(() => _shooting = true);
    try {
      final shot = await c.screenshot(window: window);
      if (mounted) _showCapture(c, shot, picture: true);
    } catch (e) {
      _toast('Screenshot failed: ${_err(e)}');
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
  }

  Future<void> _record() async {
    final c = _capture;
    if (c == null || _busy) return;
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      final st = await c.record(_since == null ? 'start' : 'stop');
      _setRecording(st.recording ? st.since ?? DateTime.now() : null);
      if (st.done != null && mounted) _showCapture(c, st.done!, picture: false);
    } catch (e) {
      _toast('Recording: ${_err(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _crop(ScreenCapture c, Capture cap) async {
    final box = await Navigator.push<Rect>(
        context, MaterialPageRoute(builder: (_) => CropScreen(image: cap.preview!)));
    if (box == null || !mounted) return;
    setState(() => _shooting = true);
    try {
      final cropped = await c.crop(cap, box);
      if (mounted) _showCapture(c, cropped, picture: true);
    } catch (e) {
      _toast('Couldn\'t crop it: ${_err(e)}');
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
  }

  void _showCapture(ScreenCapture c, Capture cap, {required bool picture}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(picture ? 'Screenshot taken' : 'Recording saved', style: display(fontSize: 20)),
            const SizedBox(height: 4),
            Text('On ${widget.peer.deviceName}: ${cap.name}',
                style: const TextStyle(color: kTextSecondary, fontSize: 12.5)),
            if (cap.preview != null) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(cap.preview!, fit: BoxFit.contain),
              ),
            ],
            const SizedBox(height: 16),
            if (picture && cap.preview != null) ...[
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _crop(c, cap);
                },
                icon: const Icon(Icons.crop_rounded),
                label: const Text('Crop'),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: kAccent,
                foregroundColor: kOnAccent,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await c.fetch(cap);
                  _toast('Sending ${cap.name}…');
                } catch (e) {
                  _toast('Couldn\'t send it: ${_err(e)}');
                }
              },
              icon: const Icon(Icons.download_rounded),
              label: const Text('Send to phone'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recording = _since != null;
    final elapsed = recording ? DateTime.now().difference(_since!) : Duration.zero;
    final mm = elapsed.inMinutes.toString(), ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return Row(children: [
      Expanded(
        child: _CaptureTile(
          icon: Icons.screenshot_monitor_rounded,
          label: 'Screenshot',
          busy: _shooting,
          onTap: _screenshot,
          onLongPress: () => _screenshot(window: true),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _CaptureTile(
          icon: recording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded,
          label: recording ? 'Stop  $mm:$ss' : 'Record screen',
          busy: _busy,
          live: recording,
          onTap: _record,
        ),
      ),
    ]);
  }
}

class _CaptureTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool busy, live;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _CaptureTile(
      {required this.icon, required this.label, required this.onTap, this.onLongPress, this.busy = false, this.live = false});

  @override
  Widget build(BuildContext context) {
    final fg = live ? kDanger : kText.withValues(alpha: 0.88);
    return Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: BoxDecoration(
          gradient: kTileGradient,
          borderRadius: BorderRadius.circular(20),
          border: live ? Border.all(color: kDanger.withValues(alpha: 0.6)) : null,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: busy ? null : onTap,
          onLongPress: busy ? null : onLongPress,
          child: SizedBox(
            height: 64,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent))
                  : Icon(icon, size: 20, color: fg),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: fg, fontWeight: FontWeight.w500, fontFeatures: const [
                      FontFeature.tabularFigures(),
                    ])),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
