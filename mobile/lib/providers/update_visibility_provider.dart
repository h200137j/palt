import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider to track if the update banner should be shown.
/// This allows the user to dismiss the banner or the app to force it visible
/// when a new update is detected.
final updateBannerVisibleProvider = StateProvider<bool>((ref) => false);
