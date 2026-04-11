/// version.dart — single source of truth for the PALT mobile app version.
///
/// Bump [kAppVersion] to match the git tag when cutting a release.
/// The CI pipeline can inject this via `--dart-define=APP_VERSION=$TAG`
/// in the future, but for now it is a manual bump.

const String kAppVersion = 'v1.0.9';

const String kGitHubApiUrl =
    'https://api.github.com/repos/h200137j/palt/releases/latest';

const String kGitHubReleasesUrl =
    'https://github.com/h200137j/palt/releases/latest';

/// Key used when persisting the last-seen version in SharedPreferences.
const String kLastSeenVersionKey = 'palt_last_seen_version';
