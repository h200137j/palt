import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'trust_provider.dart';

final aliasProvider = StateNotifierProvider<AliasNotifier, Map<String, String>>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AliasNotifier(prefs);
});

class AliasNotifier extends StateNotifier<Map<String, String>> {
  static const _key = 'palt_peer_aliases';
  final SharedPreferences _prefs;

  AliasNotifier(this._prefs) : super(_loadAliases(_prefs));

  static Map<String, String> _loadAliases(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value.toString()));
    } catch (_) {
      return {};
    }
  }

  void setAlias(String peerName, String alias) {
    final newState = Map<String, String>.from(state);
    if (alias.isEmpty) {
      newState.remove(peerName);
    } else {
      newState[peerName] = alias;
    }
    state = newState;
    _prefs.setString(_key, json.encode(state));
  }
}
