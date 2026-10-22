/// bluetooth_card.dart — a computer's Bluetooth on its Control tab: a switch
/// and what's connected, with battery (features/bluetooth.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/bluetooth.dart';
import '../../models/peer.dart';
import '../../providers/link_provider.dart';
import '../../theme/app_theme.dart';

class BluetoothCard extends ConsumerStatefulWidget {
  final Peer peer;
  const BluetoothCard({super.key, required this.peer});

  @override
  ConsumerState<BluetoothCard> createState() => _BluetoothCardState();
}

class _BluetoothCardState extends ConsumerState<BluetoothCard> {
  bool? _pending; // the state asked for, until the computer reports it

  Future<void> _set(bool on) async {
    final l = ref.read(linkManagerProvider).byName(widget.peer.deviceName);
    if (l == null) return;
    setState(() => _pending = on);
    try {
      await setPeerBluetooth(l, on);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Bluetooth: $e')));
      }
    }
    // The computer's next report settles the switch.
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) setState(() => _pending = null);
    });
  }

  static IconData _icon(String kind) => switch (kind) {
        'headset' || 'headphones' || 'speaker' => Icons.headphones_rounded,
        'mouse' || 'keyboard' || 'input' || 'gaming' => Icons.mouse_rounded,
        'phone' => Icons.smartphone_rounded,
        'watch' => Icons.watch_rounded,
        _ => Icons.bluetooth_connected_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(peerBluetoothProvider)[widget.peer.deviceName];
    if (st == null || !st.available) return const SizedBox.shrink();
    if (_pending == st.on) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _pending = null);
      });
    }
    final on = _pending ?? st.on;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        gradient: kTileGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(on ? Icons.bluetooth_rounded : Icons.bluetooth_disabled_rounded,
                size: 20, color: on ? kRelay : kTextFaint),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Bluetooth', style: TextStyle(color: kText, fontWeight: FontWeight.w600, fontSize: 14)),
                Text(
                  _pending != null
                      ? (on ? 'Turning on…' : 'Turning off…')
                      : !on
                          ? 'Off'
                          : st.devices.isEmpty
                              ? 'On · nothing connected'
                              : 'On · ${st.devices.length} connected',
                  style: TextStyle(color: kTextSecondary, fontSize: 12),
                ),
              ]),
            ),
            Switch(value: on, onChanged: _pending == null ? _set : null),
          ]),
          if (on && _pending == null)
            for (final d in st.devices)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 8, 4),
                child: Row(children: [
                  Icon(_icon(d.kind), size: 17, color: kTextSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(d.name,
                        style: TextStyle(color: kText, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (d.battery >= 0)
                    Text('${d.battery}%', style: mono(fontSize: 12, color: d.battery <= 15 ? kDanger : kTextSecondary)),
                ]),
              ),
        ],
      ),
    );
  }
}
