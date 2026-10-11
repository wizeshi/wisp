// Copyright © 2026 wizeshi

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wisp/features/navigation/router/navigation_service.dart';

class NavigationHistory {
  NavigationHistory._();

  static final NavigationHistory instance = NavigationHistory._();

  final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  late final NavigationHistoryObserver observer = NavigationHistoryObserver(this);

  final ValueNotifier<Route<dynamic>?> currentRoute =
      ValueNotifier<Route<dynamic>?>(null);

  final List<String> _history = [];
  int _index = -1;
  bool _isNavigatingHistory = false;

  bool get canGoBack => _index > 0;
  bool get canGoForward => _index >= 0 && _index < _history.length - 1;
  String? get currentRouteName => currentRoute.value?.settings.name;
  String? get currentLocation =>
      (_index >= 0 && _index < _history.length) ? _history[_index] : null;

  void recordLocation(String location) {
    if (location.isEmpty) return;
    final path = Uri.tryParse(location)?.path ?? location;

    if (_isNavigatingHistory) {
      _isNavigatingHistory = false;
      final existingIndex = _history.indexOf(location);
      if (existingIndex != -1) {
        _index = existingIndex;
      }
      _updateCurrentRoute(path);
      return;
    }

    // Ignore duplicate consecutive updates
    if (_index >= 0 && _index < _history.length && _history[_index] == location) {
      return;
    }

    // If popped to previous history entry
    if (_index > 0 && _history[_index - 1] == location) {
      _index--;
      _updateCurrentRoute(path);
      return;
    }

    // Drop forward history on new navigation
    if (_index < _history.length - 1) {
      _history.removeRange(_index + 1, _history.length);
    }

    _history.add(location);
    _index = _history.length - 1;
    _updateCurrentRoute(path);
  }

  void _updateCurrentRoute(String path) {
    final route = MaterialPageRoute<dynamic>(
      settings: RouteSettings(name: path),
      builder: (_) => const SizedBox.shrink(),
    );
    try {
      final binding = WidgetsBinding.instance;
      if (binding.schedulerPhase == SchedulerPhase.idle) {
        currentRoute.value = route;
      } else {
        binding.addPostFrameCallback((_) {
          currentRoute.value = route;
        });
      }
    } catch (_) {
      currentRoute.value = route;
    }
  }

  void goBack() {
    if (!canGoBack) return;
    _isNavigatingHistory = true;
    final targetIndex = _index - 1;
    final targetUri = _history[targetIndex];

    if (NavigationService.instance.canPop()) {
      _index = targetIndex;
      _updateCurrentRoute(Uri.tryParse(targetUri)?.path ?? targetUri);
      NavigationService.instance.pop();
    } else {
      _index = targetIndex;
      _updateCurrentRoute(Uri.tryParse(targetUri)?.path ?? targetUri);
      NavigationService.instance.router.go(targetUri);
    }
  }

  void goForward() {
    if (!canGoForward) return;
    _isNavigatingHistory = true;
    final targetIndex = _index + 1;
    final targetUri = _history[targetIndex];
    _index = targetIndex;
    _updateCurrentRoute(Uri.tryParse(targetUri)?.path ?? targetUri);
    NavigationService.instance.router.go(targetUri);
  }

  void resetToHome() {
    while (NavigationService.instance.canPop()) {
      NavigationService.instance.pop();
    }
    NavigationService.instance.goHome();
  }
}

class NavigationHistoryObserver extends NavigatorObserver {
  final NavigationHistory _history;

  NavigationHistoryObserver(this._history);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) {
      _history.recordLocation(name);
    }
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final prevName = previousRoute?.settings.name;
    if (prevName != null && prevName.isNotEmpty) {
      _history.recordLocation(prevName);
    }
    super.didPop(route, previousRoute);
  }
}
