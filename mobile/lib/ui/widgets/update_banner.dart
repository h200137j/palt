import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/update_service.dart';
import '../../theme/app_theme.dart';

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
        color: kTertiary,
        borderRadius: const BorderRadius.all(Radius.circular(2)),
        border: Border.all(color: kPrimary.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.system_update_alt_rounded, color: kOnPrimary, size: 22),
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
                      color: kOnPrimary,
                    ),
                  ),
                  const Text(
                    'Tap Download to get the latest APK',
                    style: TextStyle(fontSize: 11, color: kSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _openDownload,
              style: TextButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                shape: const RoundedRectangleBorder(),
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
