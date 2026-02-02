import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/navigation.dart';

class NavigationState extends ChangeNotifier {
  int _selectedNavIndex = 0;
  LibraryView _selectedLibraryView = LibraryView.playlists;
  bool _rightSidebarVisible = true;
  double _rightSidebarWidth = 320;
  double _leftSidebarWidth = 240;

  NavigationState() {
    _loadPrefs();
  }

  int get selectedNavIndex => _selectedNavIndex;
  LibraryView get selectedLibraryView => _selectedLibraryView;
  bool get rightSidebarVisible => _rightSidebarVisible;
  double get rightSidebarWidth => _rightSidebarWidth;
  double get leftSidebarWidth => _leftSidebarWidth;

  void setNavIndex(int index) {
    if (index == _selectedNavIndex) return;
    _selectedNavIndex = index;
    notifyListeners();
  }

  void setLibraryView(LibraryView view) {
    if (view == _selectedLibraryView) return;
    _selectedLibraryView = view;
    notifyListeners();
  }

  void toggleRightSidebar() {
    _rightSidebarVisible = !_rightSidebarVisible;
    notifyListeners();
  }

  void setRightSidebarWidth(double width) {
    final next = width.clamp(240.0, 420.0);
    if (next == _rightSidebarWidth) return;
    _rightSidebarWidth = next;
    _savePrefs();
    notifyListeners();
  }

  void adjustRightSidebarWidth(double delta) {
    setRightSidebarWidth(_rightSidebarWidth - delta);
  }

  void setLeftSidebarWidth(double width) {
    final next = width.clamp(200.0, 320.0);
    if (next == _leftSidebarWidth) return;
    _leftSidebarWidth = next;
    _savePrefs();
    notifyListeners();
  }

  void adjustLeftSidebarWidth(double delta) {
    setLeftSidebarWidth(_leftSidebarWidth + delta);
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _rightSidebarWidth = prefs.getDouble('rightSidebarWidth') ?? _rightSidebarWidth;
    _leftSidebarWidth = prefs.getDouble('leftSidebarWidth') ?? _leftSidebarWidth;
    notifyListeners();
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('rightSidebarWidth', _rightSidebarWidth);
    await prefs.setDouble('leftSidebarWidth', _leftSidebarWidth);
  }
}
