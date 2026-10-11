// Copyright © 2026 wizeshi

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LibraryView { all, playlists, albums, artists }

enum RightSidebarContent { library, connect }

class NavigationState extends ChangeNotifier {
  int _selectedNavIndex = 0;
  int _lastNonSettingsNavIndex = 0;
  LibraryView _selectedLibraryView = LibraryView.all;
  bool _rightSidebarVisible = true;
  RightSidebarContent _rightSidebarContent = RightSidebarContent.library;
  bool _desktopImmersiveMode = false;
  bool? _rightSidebarVisibleBeforeImmersive;
  double _rightSidebarWidth = 320;
  double _leftSidebarWidth = 240;

  NavigationState() {
    _loadPrefs();
  }

  int get selectedNavIndex => _selectedNavIndex;
  int get lastNonSettingsNavIndex => _lastNonSettingsNavIndex;
  LibraryView get selectedLibraryView => _selectedLibraryView;
  bool get rightSidebarVisible => _rightSidebarVisible;
  RightSidebarContent get rightSidebarContent => _rightSidebarContent;
  bool get desktopImmersiveMode => _desktopImmersiveMode;
  double get rightSidebarWidth => _rightSidebarWidth;
  double get leftSidebarWidth => _leftSidebarWidth;

  void setNavIndex(int index) {
    if (index == _selectedNavIndex) return;
    if (index != 3) {
      _lastNonSettingsNavIndex = index;
    }
    _selectedNavIndex = index;
    notifyListeners();
  }

  void setLibraryView(LibraryView view) {
    if (view == _selectedLibraryView) return;
    _selectedLibraryView = view;
    notifyListeners();
  }

  void toggleRightSidebar() {
    if (_desktopImmersiveMode) return;
    _rightSidebarVisible = !_rightSidebarVisible;
    notifyListeners();
  }

  void setRightSidebarVisible(bool visible) {
    if (_rightSidebarVisible == visible) return;
    _rightSidebarVisible = visible;
    notifyListeners();
  }

  void showConnectSidebar() {
    _rightSidebarContent = RightSidebarContent.connect;
    _rightSidebarVisible = true;
    notifyListeners();
  }

  void showLibrarySidebar() {
    if (_rightSidebarContent == RightSidebarContent.library) return;
    _rightSidebarContent = RightSidebarContent.library;
    notifyListeners();
  }

  void enterDesktopImmersiveMode() {
    if (_desktopImmersiveMode) return;
    _rightSidebarVisibleBeforeImmersive = _rightSidebarVisible;
    _desktopImmersiveMode = true;
    _rightSidebarVisible = false;
    notifyListeners();
  }

  void exitDesktopImmersiveMode() {
    if (!_desktopImmersiveMode) return;
    _desktopImmersiveMode = false;
    if (_rightSidebarVisibleBeforeImmersive != null) {
      _rightSidebarVisible = _rightSidebarVisibleBeforeImmersive!;
      _rightSidebarVisibleBeforeImmersive = null;
    }
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
    final next = width.clamp(180.0, 420.0);
    if (next == _leftSidebarWidth) return;
    _leftSidebarWidth = next;
    _savePrefs();
    notifyListeners();
  }

  void adjustLeftSidebarWidth(double delta) {
    setLeftSidebarWidth(_leftSidebarWidth + delta);
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _rightSidebarWidth =
          prefs.getDouble('wisp.shell.right_sidebar_width') ?? 320.0;
      _leftSidebarWidth =
          prefs.getDouble('wisp.shell.left_sidebar_width') ?? 240.0;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _savePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(
        'wisp.shell.right_sidebar_width',
        _rightSidebarWidth,
      );
      await prefs.setDouble(
        'wisp.shell.left_sidebar_width',
        _leftSidebarWidth,
      );
    } catch (_) {}
  }
}

