// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SearchState extends ChangeNotifier {
  final TextEditingController controller = TextEditingController();
  int _submitSignal = 0;
  String _selectedSource = 'Spotify';

  // ---------------------------------------------------------------------------
  // History
  // ---------------------------------------------------------------------------

  /// Maximum number of history entries kept on disk and shown in the UI.
  /// Exposed as a constant so callers that render a subset (e.g. the desktop
  /// dropdown, which may show fewer) can reference the overall cap easily.
  static const int maxHistoryItems = 20;

  static const String _keyHistory = 'search_history';

  List<String> _history = [];

  /// The full stored history list, newest first. Read-only; mutate via
  /// [addToHistory], [removeFromHistory], or [clearHistory].
  List<String> get history => List.unmodifiable(_history);

  SearchState() {
    _loadHistory();
  }

  // ---------------------------------------------------------------------------
  // History helpers
  // ---------------------------------------------------------------------------

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _history = prefs.getStringList(_keyHistory) ?? [];
      notifyListeners();
    } catch (_) {
      // Ignore; keep the default empty list.
    }
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyHistory, _history);
    } catch (_) {
      // Best-effort; a save failure is non-fatal.
    }
  }

  /// Adds [query] to the top of the history, deduplicating and capping at
  /// [maxHistoryItems]. Blank queries are silently ignored.
  void addToHistory(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _history.remove(trimmed);
    _history.insert(0, trimmed);
    if (_history.length > maxHistoryItems) {
      _history = _history.sublist(0, maxHistoryItems);
    }
    _saveHistory();
    notifyListeners();
  }

  /// Removes [query] from the history list (no-op if not present).
  void removeFromHistory(String query) {
    if (_history.remove(query)) {
      _saveHistory();
      notifyListeners();
    }
  }

  /// Wipes the entire history.
  void clearHistory() {
    if (_history.isEmpty) return;
    _history = [];
    _saveHistory();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Core search state
  // ---------------------------------------------------------------------------

  int get submitSignal => _submitSignal;
  String get query => controller.text;
  String get selectedSource => _selectedSource;

  void setSelectedSource(String source) {
    if (_selectedSource == source) return;
    _selectedSource = source;
    notifyListeners();
  }

  void submit() {
    _submitSignal += 1;
    notifyListeners();
  }

  void clear() {
    controller.clear();
    _submitSignal += 1;
    notifyListeners();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
