import 'package:flutter/material.dart';

class SearchState extends ChangeNotifier {
  final TextEditingController controller = TextEditingController();
  int _submitSignal = 0;
  String _selectedSource = 'Spotify';

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
