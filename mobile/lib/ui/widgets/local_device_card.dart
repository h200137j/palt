import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/peer_provider.dart';
import '../../utils/os_icons.dart';
import '../../theme/app_theme.dart';
import 'dart:io';

class LocalDeviceCard extends ConsumerWidget {
  const LocalDeviceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ipAsync = ref.watch(localIpProvider);
    final ipAddress = ipAsync.valueOrNull ?? '...';
    
    // We assume the device is Android since this is the mobile app
    final osInfo = getOsInfo('android');
    final hostname = Platform.localHostname.isNotEmpty ? Platform.localHostname : 'palt-android';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kPaltYellow, kPaltYellow.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: kPaltYellow.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: kOnYellow.withOpacity(0.12),
            child: Icon(osInfo.icon, size: 32, color: kOnYellow),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'THIS DEVICE',
                  style: TextStyle(
                    color: kOnYellow.withOpacity(0.65),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hostname,
                  style: const TextStyle(
                    color: kOnYellow,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '$ipAddress:9876',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: kOnYellow.withOpacity(0.8),
                        fontSize: 13,
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      height: 12,
                      width: 1,
                      color: kOnYellow.withOpacity(0.3),
                    ),
                    Text(
                      osInfo.label,
                      style: TextStyle(
                        color: kOnYellow.withOpacity(0.8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: kOnYellow.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 14, color: kOnYellow),
                SizedBox(width: 4),
                Text(
                  'Active',
                  style: TextStyle(
                    color: kOnYellow,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
