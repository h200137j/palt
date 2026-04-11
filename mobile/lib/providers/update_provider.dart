/// update_provider.dart
///
/// A Riverpod [FutureProvider] that runs [UpdateService.check] once per app
/// session. Because FutureProvider caches its result, the GitHub API is only
/// called a single time regardless of how many widgets watch this provider.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/update_service.dart';

final updateProvider = FutureProvider<UpdateInfo>((ref) async {
  return UpdateService.check();
});
