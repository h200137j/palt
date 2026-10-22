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
    final battery = status != null && status.battery >= 0 ? status : null;

    switch (palt.style) {
      case PaltStyle.material:
        // Like a search bar: a pill with the phone in it.
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Container(
            height: 56,
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            decoration: BoxDecoration(color: kSurfaceRaised, borderRadius: BorderRadius.circular(28)),
            child: Row(children: [
              Icon(Icons.smartphone_rounded, color: kTextSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Text('$hostname · visible nearby',
                    style: TextStyle(fontSize: 16, color: kTextSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (battery != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: kAccentSoft, borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(battery.charging ? Icons.bolt_rounded : Icons.battery_full_rounded, size: 16, color: kOnAccentSoft),
                    const SizedBox(width: 4),
                    Text('${battery.battery}%',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kOnAccentSoft)),
                  ]),
                ),
            ]),
          ),
        );
      case PaltStyle.paper:
        // The edition line.
        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
          child: Row(children: [
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'Edition for ', style: TextStyle(color: kTextSecondary, fontStyle: FontStyle.italic)),
                  TextSpan(text: hostname, style: TextStyle(color: kText, fontWeight: FontWeight.w700)),
                  TextSpan(text: ', visible at ', style: TextStyle(color: kTextSecondary, fontStyle: FontStyle.italic)),
                  TextSpan(text: ip, style: mono(fontSize: 12, color: kText)),
                ]),
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
            if (battery != null) Text('${battery.battery}%', style: mono(fontSize: 12, color: batteryColor(battery))),
          ]),
        );
      case PaltStyle.pop:
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 22, 0),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
            decoration: paltDeco(radius: 14, color: popColor(2, kSurface)),
            child: Row(children: [
              Icon(Icons.smartphone_rounded, color: kText),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('THIS PHONE', style: overline()),
                  Text(hostname,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kText),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: paltDeco(radius: 6, color: kSurface, flat: true),
                child: Text(battery != null ? '${battery.battery}%' : ip, style: mono(fontSize: 11, color: kText)),
              ),
            ]),
          ),
        );
      default:
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: isBeacon
          ? BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(16))
          : paltDeco(radius: 16),
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
