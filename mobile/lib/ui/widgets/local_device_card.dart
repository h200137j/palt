import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/peer_provider.dart';
import '../../utils/os_icons.dart';
import '../../theme/app_theme.dart';
import 'dart:io';

class LocalDeviceCard extends ConsumerStatefulWidget {
  const LocalDeviceCard({super.key});

  @override
  ConsumerState<LocalDeviceCard> createState() => _LocalDeviceCardState();
}

class _LocalDeviceCardState extends ConsumerState<LocalDeviceCard> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ipAsync = ref.watch(localIpProvider);
    final ipAddress = ipAsync.valueOrNull ?? '...';
    final osInfo = getOsInfo('android');
    final hostname = Platform.localHostname.isNotEmpty ? Platform.localHostname : 'palt-android';

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Card(
        elevation: 0,
        color: kTertiary,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Row(
            children: [
              Container(
                width: 68,
                height: 68,
                color: kOnPrimary.withValues(alpha: 0.08),
                child: Icon(osInfo.icon, size: 34, color: kOnPrimary),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR DEVICE',
                      style: GoogleFonts.archivoNarrow(
                        color: kOnPrimary.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      hostname,
                      style: GoogleFonts.archivo(
                        color: kOnPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 24,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      color: kOnPrimary.withValues(alpha: 0.08),
                      child: Text(
                        '$ipAddress:9876',
                        style: GoogleFonts.ubuntuMono(
                          color: kOnPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      ScaleTransition(
                        scale: Tween(begin: 1.0, end: 2.2).animate(
                          CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
                        ),
                        child: FadeTransition(
                          opacity: Tween(begin: 0.5, end: 0.0).animate(
                            CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
                          ),
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: kOnPrimary.withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ONLINE',
                    style: GoogleFonts.archivoNarrow(
                      color: kOnPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
