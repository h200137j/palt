import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class OsInfo {
  final String label;
  final Color color;
  final IconData icon;

  const OsInfo(this.label, this.color, this.icon);
}

OsInfo getOsInfo(String os) {
  switch (os.toLowerCase()) {
    case 'android':
      return OsInfo('Android', kTextSecondary, Icons.smartphone_rounded);
    case 'linux':
      return OsInfo('Linux', kTextSecondary, Icons.computer_rounded);
    case 'darwin':
      return OsInfo('macOS', kTextSecondary, Icons.laptop_mac_rounded);
    case 'windows':
      return OsInfo('Windows', kTextSecondary, Icons.window_rounded);
    default:
      return OsInfo(os.isEmpty ? 'Unknown' : os, kTextFaint,
          Icons.device_unknown_rounded);
  }
}
