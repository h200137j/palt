/// asleep_devices.dart — computers that aren't connected but can be woken:
/// one row each on the home screen, with a Wake button (features/wake.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/wake.dart';
import '../../providers/peer_provider.dart';
import '../../theme/app_theme.dart';

class AsleepDevices extends ConsumerWidget {
  const AsleepDevices({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final here = {for (final p in ref.watch(peerListProvider).valueOrNull ?? []) p.deviceName};
    final targets = ref.watch(wakeTargetsProvider).values.where((t) => !here.contains(t.name)).toList();
    if (targets.isEmpty) return const SizedBox.shrink();
    return Column(children: [for (final t in targets) _AsleepRow(target: t)]);
  }
}

class _AsleepRow extends StatefulWidget {
  final WakeTarget target;
  const _AsleepRow({required this.target});

  @override
  State<_AsleepRow> createState() => _AsleepRowState();
}

class _AsleepRowState extends State<_AsleepRow> {
  bool _sent = false;

  Future<void> _wake() async {
    try {
      await wake(widget.target);
      setState(() => _sent = true);
      Future.delayed(const Duration(seconds: 30), () {
        if (mounted) setState(() => _sent = false);
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Couldn\'t wake it: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.target;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kHairline),
      ),
      child: Row(children: [
        Icon(Icons.bedtime_rounded, color: kTextFaint, size: 22),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.name, style: TextStyle(color: kText, fontWeight: FontWeight.w600, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text(
              _sent
                  ? 'Waking… it reconnects in a few seconds'
                  : t.ready
                      ? 'Asleep or away'
                      : 'Asleep or away · wake isn\'t on in its PALT settings',
              style: TextStyle(color: kTextSecondary, fontSize: 12),
            ),
          ]),
        ),
        FilledButton.tonal(
          onPressed: _sent ? null : _wake,
          child: const Text('Wake'),
        ),
      ]),
    );
  }
}
