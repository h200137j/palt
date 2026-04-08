import 'package:flutter/material.dart';

class OsInfo {
  final String label;
  final Color color;
  final IconData icon;

  const OsInfo(this.label, this.color, this.icon);
}

OsInfo getOsInfo(String os) {
  switch (os.toLowerCase()) {
    case 'android':
      return const OsInfo('Android', Color(0xFF34A853), Icons.phone_android);
    case 'linux':
      return const OsInfo('Linux', Color(0xFF5F6368), Icons.computer);
    case 'darwin':
      return const OsInfo('macOS', Color(0xFF202124), Icons.laptop_mac);
    case 'windows':
      return const OsInfo('Windows', Color(0xFF1A73E8), Icons.window);
    default:
      return OsInfo(
          os.isEmpty ? 'Unknown' : os, Colors.grey, Icons.device_unknown);
  }
}
