import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in ProviderScope');
});

final trustProvider = StateNotifierProvider<TrustNotifier, List<String>>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return TrustNotifier(prefs);
});

class TrustNotifier extends StateNotifier<List<String>> {
  static const _key = 'palt_trusted_devices';
  final SharedPreferences _prefs;

  TrustNotifier(this._prefs) : super(_prefs.getStringList(_key) ?? []);

  bool isTrusted(String peerName) {
    return state.contains(peerName);
  }

  void trust(String peerName) {
    if (!state.contains(peerName)) {
      state = [...state, peerName];
      _prefs.setStringList(_key, state);
    }
  }

  void revoke(String peerName) {
    if (state.contains(peerName)) {
      state = state.where((p) => p != peerName).toList();
      _prefs.setStringList(_key, state);
    }
  }
}
