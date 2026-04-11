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
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: kPaltYellow.withOpacity(0.12),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32),
          side: BorderSide(color: kPaltYellow.withOpacity(0.1), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Premium Mesh/Organic Background
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      kPaltYellow.withOpacity(0.9),
                      kPaltYellow.withOpacity(0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            // Abstract "Glass" Blobs
            Positioned(
              top: -60,
              right: -40,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 1.0 + (_pulseController.value * 0.1),
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withOpacity(0.25),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              bottom: -40,
              left: -20,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withOpacity(0.15),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Row(
                children: [
                  // OS Icon with modern container
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                    ),
                    child: Icon(osInfo.icon, size: 34, color: kOnYellow),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YOUR DEVICE',
                          style: GoogleFonts.outfit(
                            color: kOnYellow.withOpacity(0.5),
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          hostname,
                          style: GoogleFonts.outfit(
                            color: kOnYellow,
                            fontWeight: FontWeight.w900,
                            fontSize: 24,
                            letterSpacing: -0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$ipAddress:9876',
                            style: GoogleFonts.ubuntuMono( // Using a cleaner mono font for IP
                              color: kOnYellow.withOpacity(0.8),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Pulse Status Indicator
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
                                decoration: const BoxDecoration(
                                  color: Colors.white,
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
                              boxShadow: [
                                BoxShadow(color: Colors.green, blurRadius: 4),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ONLINE',
                        style: GoogleFonts.outfit(
                          color: kOnYellow,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
