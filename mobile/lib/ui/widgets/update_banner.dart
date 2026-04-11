/// update_banner.dart
///
/// A prominent but non-intrusive banner card displayed in the HomeScreen
/// body when [updateProvider] resolves with [UpdateInfo.isNewer] = true.
///
/// The "Download" button opens the APK asset URL (or the releases page
/// as fallback) using [url_launcher].

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/update_service.dart';

class UpdateBanner extends StatelessWidget {
  final UpdateInfo info;

  const UpdateBanner({super.key, required this.info});

  Future<void> _openDownload() async {
    final uri = Uri.parse(info.downloadUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7), // amber-50
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B), width: 1), // amber-400
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.system_update_alt_rounded,
                color: Color(0xFF92400E), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Update available: ${info.latestVersion}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFF78350F),
                    ),
                  ),
                  const Text(
                    'Tap Download to get the latest APK',
                    style: TextStyle(fontSize: 11, color: Color(0xFF92400E)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _openDownload,
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: const Color(0xFF78350F),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Download',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
