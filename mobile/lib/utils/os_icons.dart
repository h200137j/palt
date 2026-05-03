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
      return const OsInfo('Android', kSecondary, Icons.phone_android);
    case 'linux':
      return const OsInfo('Linux', kSecondary, Icons.computer);
    case 'darwin':
      return const OsInfo('macOS', kPrimary, Icons.laptop_mac);
    case 'windows':
      return const OsInfo('Windows', kSecondary, Icons.window);
    default:
      return OsInfo(
          os.isEmpty ? 'Unknown' : os, kSecondary, Icons.device_unknown);
  }
}
