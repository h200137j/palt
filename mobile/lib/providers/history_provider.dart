import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/history_entry.dart';

final historyProvider = StateNotifierProvider<HistoryNotifier, List<HistoryEntry>>((ref) {
  return HistoryNotifier();
});

class HistoryNotifier extends StateNotifier<List<HistoryEntry>> {
  HistoryNotifier() : super([]) {
    _loadHistory();
  }

  static const _key = 'transfer_history';

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getStringList(_key);
      if (historyJson != null) {
        state = historyJson
            .map((e) => HistoryEntry.fromJson(jsonDecode(e)))
            .toList();
      }
    } catch (e) {
      print('[HistoryNotifier] Error loading history: $e');
    }
  }

  Future<void> addEntry(HistoryEntry entry) async {
    // Prepend new entry
    state = [entry, ...state];
    
    // Keep last 100 items for mobile to save space
    if (state.length > 100) {
      state = state.sublist(0, 100);
    }
    
    await _saveHistory();
  }

  Future<void> clearHistory() async {
    state = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = state.map((e) => jsonEncode(e.toJson())).toList();
      await prefs.setStringList(_key, historyJson);
    } catch (e) {
      print('[HistoryNotifier] Error saving history: $e');
    }
  }
}
