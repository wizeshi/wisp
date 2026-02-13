import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

class AppFocusService with WindowListener, WidgetsBindingObserver {
  AppFocusService._() {
    WidgetsBinding.instance.addObserver(this);
    if (_isDesktop) {
      windowManager.addListener(this);
    }
  }

  static final AppFocusService instance = AppFocusService._();

  final ValueNotifier<bool> isFocused = ValueNotifier(true);

  bool get _isDesktop => Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  @override
  void onWindowFocus() => _setFocused(true);

  @override
  void onWindowBlur() => _setFocused(false);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _setFocused(true);
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _setFocused(false);
        break;
      case AppLifecycleState.hidden:
        _setFocused(false);
        break;
    }
  }

  void _setFocused(bool focused) {
    if (isFocused.value == focused) return;
    isFocused.value = focused;
  }

  void dispose() {
    if (_isDesktop) {
      windowManager.removeListener(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    isFocused.dispose();
  }
}
