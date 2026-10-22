/// computer_vitals.dart — a computer's state on its Control tab: locked or
/// not, CPU, memory, disk, temperature and uptime
/// (desktop/computer_status_linux.go).
library;

import 'package:flutter/material.dart';

import '../../features/phone_features.dart';
import '../../theme/app_theme.dart';

String _gb(int bytes) {
  final gb = bytes / (1 << 30);
  return gb >= 100 ? '${gb.round()} GB' : '${gb.toStringAsFixed(1)} GB';
}

String _uptime(int s) {
  final d = s ~/ 86400, h = (s % 86400) ~/ 3600, m = (s % 3600) ~/ 60;
  if (d > 0) return '${d}d ${h}h';
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

class ComputerVitals extends StatelessWidget {
  final DeviceStatus status;
  const ComputerVitals({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status;
    final ramFrac = s.ramTotal > 0 ? s.ramUsed / s.ramTotal : 0.0;
    final diskUsed = s.diskTotal - s.diskFree;
    final diskFrac = s.diskTotal > 0 ? diskUsed / s.diskTotal : 0.0;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: kTileGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(s.locked ? Icons.lock_rounded : Icons.lock_open_rounded, size: 18, color: s.locked ? kAccent : kOk),
            const SizedBox(width: 8),
            Text(s.locked ? 'Locked' : 'Unlocked',
                style: TextStyle(color: kText, fontWeight: FontWeight.w600, fontSize: 14)),
            const Spacer(),
            if (s.temp > 0) ...[
              Icon(Icons.thermostat_rounded, size: 16, color: s.temp >= 85 ? kDanger : kTextSecondary),
              Text('${s.temp}°C', style: mono(fontSize: 12, color: s.temp >= 85 ? kDanger : kTextSecondary)),
              const SizedBox(width: 12),
            ],
            Icon(Icons.schedule_rounded, size: 15, color: kTextSecondary),
            const SizedBox(width: 4),
            Text('up ${_uptime(s.uptime)}', style: mono(fontSize: 12, color: kTextSecondary)),
          ]),
          const SizedBox(height: 14),
          _Meter(label: 'CPU', value: '${s.cpu}%', frac: s.cpu / 100),
          _Meter(label: 'Memory', value: '${_gb(s.ramUsed)} of ${_gb(s.ramTotal)}', frac: ramFrac),
          if (s.diskTotal > 0)
            _Meter(label: 'Disk', value: '${_gb(s.diskFree)} free of ${_gb(s.diskTotal)}', frac: diskFrac),
        ],
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  final String label, value;
  final double frac;
  const _Meter({required this.label, required this.value, required this.frac});

  @override
  Widget build(BuildContext context) {
    final f = frac.clamp(0.0, 1.0);
    final hot = f >= 0.9;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(label, style: TextStyle(color: kTextSecondary, fontSize: 12.5)),
            const Spacer(),
            Text(value, style: mono(fontSize: 12, color: hot ? kDanger : kText)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(children: [
              Container(height: 6, color: Colors.white.withValues(alpha: 0.07)),
              AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                widthFactor: f,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    gradient: hot ? LinearGradient(colors: [kDanger, kDanger]) : kAccentGradient,
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
