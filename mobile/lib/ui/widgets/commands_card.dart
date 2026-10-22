/// commands_card.dart — the commands a paired computer offers (Lock,
/// Suspend, Mute, Restart, Shut down and the user's own) as a row of round
/// icon buttons with a cool glow, one tap each; long-press shows the name.
/// The ones that end the session ask first.
///
/// Packets: commands.list / commands.run (desktop/commands_app.go).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/peer.dart';
import '../../providers/link_provider.dart';
import '../../theme/app_theme.dart';

class CommandsCard extends ConsumerStatefulWidget {
  final Peer peer;
  const CommandsCard({super.key, required this.peer});

  @override
  ConsumerState<CommandsCard> createState() => _CommandsCardState();
}

class _CommandsCardState extends ConsumerState<CommandsCard> {
  List<({String id, String name})>? _commands;
  String? _running;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = ref.read(linkManagerProvider).byName(widget.peer.deviceName);
    if (l == null || !l.supports('commands.list')) return;
    try {
      final p = await l.request('commands.list');
      final list = [
        for (final c in (p.body?['commands'] as List?) ?? [])
          (id: (c as Map)['id'] as String, name: c['name'] as String),
      ];
      if (mounted) setState(() => _commands = list);
    } catch (_) {}
  }

  /// Commands that end the computer's session ask first.
  static const _confirm = {
    'suspend': 'Put it to sleep?',
    'reboot': 'Restart it? Unsaved work there may be lost.',
    'poweroff': 'Shut it down? Unsaved work there may be lost.',
  };

  Future<void> _run(String id, String name) async {
    final l = ref.read(linkManagerProvider).byName(widget.peer.deviceName);
    if (l == null) return;
    final question = _confirm[id];
    if (question != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('$name ${widget.peer.deviceName}'),
          content: Text(question),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(name)),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _running = id);
    String msg;
    try {
      final p = await l.request('commands.run', body: {'id': id}, timeout: const Duration(seconds: 70));
      final err = p.body?['error'] as String?;
      final out = (p.body?['output'] as String?)?.trim() ?? '';
      msg = err != null && err.isNotEmpty ? '$name failed: $err' : (out.isEmpty ? '$name: done' : out);
    } catch (e) {
      msg = '$name failed: $e';
    }
    if (!mounted) return;
    setState(() => _running = null);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg, maxLines: 6, overflow: TextOverflow.ellipsis)));
  }

  static IconData _icon(String id) => switch (id) {
        'lock' => Icons.lock_rounded,
        'suspend' => Icons.bedtime_rounded,
        'mute' => Icons.volume_off_rounded,
        'reboot' => Icons.restart_alt_rounded,
        'poweroff' => Icons.power_settings_new_rounded,
        _ => Icons.terminal_rounded,
      };

  /// Cool blue, so commands stand apart from the amber actions.
  static const _glow = Color(0xFF6EA8FF);
  static const _size = 56.0, _gap = 10.0;

  Widget _button(({String id, String name}) c, double size) {
    final busy = _running == c.id;
    return Tooltip(
      message: c.name,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: _glow.withValues(alpha: 0.28), blurRadius: 16, spreadRadius: -2)],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Ink(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: kTileGradient,
              border: Border.all(color: _glow.withValues(alpha: 0.35)),
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _running == null ? () => _run(c.id, c.name) : null,
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _glow))
                    : Icon(_icon(c.id), size: 24, color: _glow, semanticLabel: c.name),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final commands = _commands;
    if (commands == null || commands.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: LayoutBuilder(builder: (context, box) {
        // One even row when they fit; shrink a little, then wrap.
        final perRow = commands.length.clamp(1, 6);
        final size = ((box.maxWidth - _gap * (perRow - 1)) / perRow).clamp(44.0, _size);
        return Wrap(
          alignment: WrapAlignment.spaceEvenly,
          spacing: _gap,
          runSpacing: _gap,
          children: [for (final c in commands) _button(c, size)],
        );
      }),
    );
  }
}
