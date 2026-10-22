/// local_device_card.dart — "this phone" strip at the top of home (Beacon).
///
/// One slim line: the name paired devices see, that it's visible nearby,
/// its address, and its battery.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/phone_features.dart';
import '../../providers/link_provider.dart';
import '../../providers/peer_provider.dart';
import '../../theme/app_theme.dart';
import 'device_status.dart';

class LocalDeviceCard extends ConsumerWidget {
  const LocalDeviceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ip = ref.watch(localIpProvider).valueOrNull ?? '…';
    // The name paired devices see this phone as.
    final hostname = ref.watch(localNameProvider).valueOrNull ?? '…';
    final status = ref.watch(localStatusProvider);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.smartphone_rounded, size: 20, color: kAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This phone · $hostname',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kText),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('Visible to nearby · $ip', style: mono(fontSize: 11)),
              ],
            ),
          ),
          if (status != null && status.battery >= 0) ...[
            const SizedBox(width: 8),
            if (status.charging) Icon(Icons.bolt_rounded, size: 14, color: batteryColor(status)),
            Text('${status.battery}%', style: mono(fontSize: 12, color: batteryColor(status))),
          ],
        ],
      ),
    );
  }
}
