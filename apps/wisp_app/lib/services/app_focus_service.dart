// Copyright © 2026 wizeshi

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

  bool get _isDesktop =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

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
        // For some reason, Windows treats inactive as both when it's in the background (minimized),
        // but also when it's in the foreground but not focused. I prefer to just pause it then, but
        // a TODO is enable a toggle for this behavior in the settings page.
        if (_isDesktop) {
          _setFocused(false);
        } else {
          _setFocused(true);
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
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
