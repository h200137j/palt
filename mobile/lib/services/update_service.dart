/// update_service.dart
///
/// Queries the GitHub Releases API and determines whether a newer version
/// of PALT is available. Uses dart:io [HttpClient] to avoid adding a new
/// package dependency.
///
/// The service returns an [UpdateInfo] that is safe to call from a
/// Riverpod [FutureProvider] — it never throws; it returns [UpdateInfo.none]
/// on any network or parse error so the app always starts cleanly offline.

import 'dart:convert';
import 'dart:io';

import '../utils/version.dart';

/// Holds the result of an update check.
class UpdateInfo {
  /// Whether a newer version exists on GitHub.
  final bool isNewer;

  /// The latest version tag from GitHub (e.g. "v1.1.0").
  final String latestVersion;

  /// Release notes (GitHub release body markdown).
  final String releaseNotes;

  /// Direct APK asset download URL, or the releases page as fallback.
  final String downloadUrl;

  const UpdateInfo({
    required this.isNewer,
    required this.latestVersion,
    required this.releaseNotes,
    required this.downloadUrl,
  });

  /// Returned when the check cannot be completed (offline, parse error, etc.).
  static const none = UpdateInfo(
    isNewer: false,
    latestVersion: kAppVersion,
    releaseNotes: '',
    downloadUrl: kGitHubReleasesUrl,
  );
}

class UpdateService {
  /// Performs the GitHub Releases API check.
  ///
  /// Returns [UpdateInfo.none] on any error so callers never have to
  /// handle exceptions.
  static Future<UpdateInfo> check() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);

      final request = await client.getUrl(Uri.parse(kGitHubApiUrl));
      request.headers.set('Accept', 'application/vnd.github+json');
      request.headers.set('User-Agent', 'palt-mobile/$kAppVersion');

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode != 200) {
        return UpdateInfo.none;
      }

      final json = jsonDecode(body) as Map<String, dynamic>;
      final tagName = (json['tag_name'] as String?)?.trim() ?? '';
      final releaseBody = (json['body'] as String?) ?? '';
      final assets = (json['assets'] as List<dynamic>?) ?? [];

      // Extract the APK asset download URL.
      String downloadUrl = kGitHubReleasesUrl;
      for (final asset in assets) {
        final name = (asset['name'] as String?) ?? '';
        if (name.endsWith('.apk')) {
          downloadUrl = (asset['browser_download_url'] as String?) ?? kGitHubReleasesUrl;
          break;
        }
      }

      final isNewer = _isNewerThan(tagName, kAppVersion);

      return UpdateInfo(
        isNewer: isNewer,
        latestVersion: tagName.isNotEmpty ? tagName : kAppVersion,
        releaseNotes: releaseBody,
        downloadUrl: downloadUrl,
      );
    } catch (_) {
      // Fail silently — network errors, JSON errors, etc.
      return UpdateInfo.none;
    }
  }

  /// Returns true if [latest] is strictly newer than [current].
  /// Both are expected in the form "vX.Y.Z".
  static bool _isNewerThan(String latest, String current) {
    List<int> parse(String v) {
      final stripped = v.startsWith('v') ? v.substring(1) : v;
      final parts = stripped.split('.');
      return List.generate(3, (i) => i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0);
    }

    final l = parse(latest);
    final c = parse(current);

    for (var i = 0; i < 3; i++) {
      if (l[i] > c[i]) return true;
      if (l[i] < c[i]) return false;
    }
    return false;
  }
}
